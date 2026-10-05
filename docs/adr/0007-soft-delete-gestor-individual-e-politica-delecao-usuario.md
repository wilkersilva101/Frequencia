# ADR-0007: Soft-delete do vínculo de gestão individual, invariante de auto-gerência e política de deleção de `User`

> **[⌂ Home](../README.md)**

## Status

Aceito (CTO, 2026-09-29). Decorre da Tarefa 29.2 da Sprint 29 (`docs/progress/iteration_29.md`) e orienta as tarefas 29.3, 29.4 e 29.6.

## Contexto

- A Tarefa 29.2 migrou `GestorIndividual` e o vínculo `GestorIndividualGerenciado` para receber o dado real do Intranet (PRD §2.5). O dado legado passa a ser **fonte de verdade** no Frequencia quando o Intranet for descomissionado, então a preservação do histórico operacional passa a ser crítica.
- Três rodadas de Bug Finder (19 achados, `docs/quality/bug_report_29_2_*.md`) convergiram para o mesmo padrão estrutural: **assimetria entre validação-de-model e constraint-de-banco**. Cada rodada encontrou a mesma classe de defeito num eixo diferente (par gestor→gerido; auto-gerência "tardia"; eixo `ativo`/`inativo` do invariante). Os defeitos das rodadas 2–3 foram **regressões das correções** da rodada anterior.
- A causa-raiz estrutural: o concern `Desativavel` centraliza a mecânica (`desativar!`/`ativo?`/`scope :ativos`), mas **não** alcança as validações de invariante, que ficaram **duplicadas** entre `GestorIndividual` e `GestorIndividualGerenciado`. Um `CHECK` no Postgres não pode cruzar duas tabelas, então o invariante de auto-gerência ficou obrigatoriamente em validações de model, em dois pontos.
- Decisões já tomadas pelo usuário/dev e por revisões anteriores (a 29.2 foi aprovada explicitamente em 2026-09-29): soft-delete sem tocar `destroy`/UI (a tela só tem `index`); `id_legado` UNIQUE também no vínculo (chave de upsert idempotente da 29.3).
- Restrições: RN globais "não apague dados do usuário", "não remova histórico operacional sem arquivar", "nunca hard-delete"; a migration 29.2 é **forward-only nos dados** (rollback apaga as colunas de dado real — Bug 1 do Bug Finder).

## Alternativas Consideradas

### Alternativa A: manter as validações de invariante duplicadas nos dois models

- **Prós:** nenhuma refatoração; comportamento externo idêntico ao já testado.
- **Contras:** é a fonte estrutural dos Bugs 12/17/18. Corrigir um lado e esquecer o outro reintroduz a assimetria silenciosa no quadrante não testado — exatamente o que aconteceu 3 rodadas seguidas. Sem uma fonte única, o risco é **recorrente e previsível**, não residual.

### Alternativa B: substituir o soft-delete por hard-delete com arquivo morto

- **Contras:** viola a RN global "não remova histórico operacional sem arquivar"; perderia a rastreabilidade do gerido na cascata da 29.4/29.6; o índice parcial `WHERE ativo` deixaria de fazer sentido. Descartada.

### Alternativa C: centralizar o invariante em um concern compartilhado e manter o soft-delete + índice parcial (escolhida)

- **Descrição:** extrair as validações de invariante (par ativo + auto-gerência "nenhum vínculo ATIVO liga o gestor a si mesmo") para **um** `ActiveSupport::Concern` (`InvarianteAutoGerencia`), incluído nos dois models; manter o soft-delete (`Desativavel`) e o índice UNIQUE parcial em `(gestor_individual_id, user_id) WHERE ativo`; manter `dependent: :restrict_with_exception` no vínculo; tratar a deleção de `User` como política de domínio (sem hard-`destroy` de `User` referenciado).
- **Prós:** declara a regra **uma vez** e a cobre nos dois lados e no banco; elimina a classe de bug; documenta explicitamente o invariante canônico para a cascata da 29.4/29.6.
- **Contras:** refatoração pequena (sem mudança de comportamento externo) que exige re-run de suíte e re-review; a extração para concern é uma tarefa da própria 29.2 (`29.2-D7`), pré-condição da 29.3.

## Decisão

> **ADOTAMOS A ALTERNATIVA C.**

Regras de implementação:

1. **Invariante canônico (fonte única):** *nenhum vínculo ATIVO liga o gestor a si mesmo*. Vale idêntico em três pontos — validação do lado do gestor (`GestorIndividual#gestor_user_nao_e_gerido_ativo`, com `if: -> { new_record? || will_save_change_to_gestor_user_id? }`), validação do lado do vínculo (`GestorIndividualGerenciado#gerido_nao_e_o_proprio_gestor`, com `if: :ativo?`) e a ausência de índice/constraint para o caso inativo. Um vínculo inativo de auto-gerência é **histórico**, não auto-autorização corrente, e pode ser reescrito.
2. **Validação de invariante é event-scoped:** dispara no **evento** que muda o invariante (`will_save_change_to_X?` / `new_record?`), nunca em todo save — senão um registro já inconsistente fica **travado** (não edita, não desativa) sem caminho de recuperação in-app (Bug 17).
3. **Fonte única da regra — `29.2-D7`:** extrair as validações de invariante para um `ActiveSupport::Concern` compartilhado, incluído em `GestorIndividual` e `GestorIndividualGerenciado`. O concern `Desativavel` permanece para a mecânica de soft-delete. A 29.3 passa a **depender** da 29.2-D7.
4. **Soft-delete é o único caminho de remoção de vínculo/gestor:** `desativar!` (preserva sempre a primeira `data_exclusao`; nunca hard-delete). `destroy` do gestor levanta `restrict_with_exception` com vínculo presente. A importação da 29.3 grava `data_exclusao` legada **direto no atributo**, nunca via `desativar!`.
5. **Índice UNIQUE parcial** em `(gestor_individual_id, user_id) WHERE ativo` (migration `20260929130000`): no máximo **um** vínculo ativo por par, permitindo histórico de inativos. Toda validação que o espelhe deve cobrir a mesma fatia (predicado `if: :ativo?`).
6. **`valid?` é proibido no caminho de leitura (D8):** nenhum `index`/`show` pode disparar `valid?` sobre registros importados — um registro válido-no-banco/inválido-no-model faz a renderização levantar `RecordInvalid`.
7. **Política de deleção de `User` (Bug 7):** manter o padrão `restrict` do projeto. Não é permitido hard-`destroy` de `User` referenciado por vínculo de gestão; a FK `gestor_user_id` bloqueia com `InvalidForeignKey`. Se existir fluxo de remoção de login, ele **desativa** (soft) o `User`; a FK permanece `restrict` (sem `on_delete: :nullify`).
8. **Modo de escrita da importação (29.3):** usar **ActiveRecord** (não `upsert_all`) para reconciliar gestor e vínculo enquanto o invariante não puder ser validado por SQL. O caminho `upsert_all` fica vetado para o par/auto-gerência.

## Consequências

### Positivas

- A regra de auto-gerência passa a ter **uma** fonte; consertar um lado não deixa o outro divergir.
- A importação da 29.3 entra em um terreno onde a classe de bug que mordeu 3 vezes foi eliminada na raiz.
- O invariante e a política de deleção ficam documentados para a cascata da 29.4/29.6, que dependem de "gestor ativo" e "gerido ativo" com semântica idêntica nos dois lados.

### Negativas / Trade-offs

- Refatoração pequena na 29.2 (`29.2-D7`) exige re-run de suíte e re-review; a 29.3 fica bloqueada até isso.
- O concern compartilhado não substitui a constraint do banco: a corrida entre inserts concorrentes continua coberta pelo índice parcial, e a auto-gerência "tardia" por **bypass puro** (`update_column`/SQL direto) permanece indetectável — documentado, não é caminho do app.
- `upsert_all` deixa de ser opção para o par/auto-gerência enquanto o invariante não for expressável em SQL.

### Neutras

- Não altera migrations já aplicadas, o schema do Pessoas2, nem gem alguma.
- Não altera o comportamento externo dos models (refatoração de validação).

## Compliance

- Nenhum PR da 29.3/29.4/29.6 pode ser aprovado sem o concern compartilhado (`29.2-D7`) e sem cobrir, para o invariante e para o índice parcial, os **4 quadrantes de `ativo`** (ativo/ativo, ativo/inativo, inativo/ativo, inativo/inativo) **pelos dois lados** (validação Rails de cada model + `insert_all!` no banco).
- Nenhum caminho de leitura pode chamar `valid?` (D8); o `structural-conformity-checklist` deve conter os itens "4 quadrantes × 2 lados", "caminho de leitura não revalida" e "`dependent:` verificado em nichos de bypass".
- A importação da 29.3 não pode exibir `e.message` cru de `RecordInvalid` (locale pt-BR sem `record_invalid`) — usar `errors.full_messages`.

## Notas

- ADRs relacionados: 0001 (integração com o Pessoas), 0006 (schema de teste do espelho Pessoas).
- Fontes: `docs/quality/bug_report_29_2_bug-finder.md`, `..._r2.md`, `..._r3.md`; `docs/progress/iteration_29.md` (seção `🧭 Plano do CTO — Tarefa 29.2`); `docs/governance/lessons.md` (lições de 2026-09-29 sobre índice parcial e event-scope de invariante).
- Modelos: `api-ponto/app/models/gestor_individual.rb`, `gestor_individual_gerenciado.rb`, `app/models/concerns/desativavel.rb`; migrations `20260929120000`, `20260929130000`.
- Decisões do usuário/dev já aprovadas (2026-09-29): soft-delete sem tocar `destroy`/UI; `id_legado` UNIQUE também no vínculo.
