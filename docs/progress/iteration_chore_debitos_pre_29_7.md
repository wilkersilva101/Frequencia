# iteration chore: débitos pré-29.7 (contrato do PORO, log do scope, fixture multi-vínculo)

> **Modo:** AGILE | **Branch:** `chore/debitos-pre-29-7` | **Data:** 2026-10-02
> **Base:** `integration/sprint-29` @ `2b8e47a`
> **Worktree:** `wt-29x-debitos` (app em `wt-29x-debitos/api-ponto/`)
> **Tipo:** chore (fecha 3 débitos que bloqueiam a 29.7 — a `Ability` que expõe o fluxo)
> **COMMIT_MODE=manual** (sem commit/push nesta etapa — o coordenador commita).

## Motivação

A 29.7 expõe o fluxo de desconsideração e liga as regras das 29.4/29.5/29.6, fazendo tudo isto ter
consequência real. Três débitos medidos precisam ser fechados **antes**, cada um com gatilho/destino:

| Débito | Gatilho (o que quebra na 29.7) | Destino |
|---|---|---|
| **D1** — contrato FALSO no PORO da 29.5 | A 29.7 confia no `@param [User, Pessoas::Pessoa]` e passa uma `Pessoas::Pessoa` → `NoMethodError` no primeiro dia | `app/models/elegibilidade_desconsideracao.rb` + teste |
| **D2** — scope da 29.6 não loga | O shadow da 29.7 (D3) vê metade do sistema: o PORO loga negações, a listagem (que serve as telas) é cega | `app/models/frequentadores_visiveis.rb` + teste |
| **D3** — fixture da 29.6 sem multi-vínculo | Buraco de cobertura na D4 ("algum vínculo ativo"), num caso sensível, justo no passo 3 (terceirizado) | `test/models/frequentadores_visiveis_test.rb` |

---

## D1 — contrato do PORO `ElegibilidadeDesconsideracao`

### Diagnóstico

`elegibilidade_desconsideracao.rb:53` documentava `@param frequentador [User, Pessoas::Pessoa]`.
Falso: `Dia#registros` chama `user.time_records` (`app/models/dia.rb:44`) e `Pessoas::Pessoa` **não
tem** `time_records` → `NoMethodError`. Agrava: com acionador nulo, o guard de entrada (`return false
if acionador.blank?`) **mascara** o erro — o contrato falso só se manifestava num caminho específico.
E o código **antecipa** `alvo.is_a?(User)` (`:128`), ou seja, o contrato era **contradito pelo próprio
código**. Um contrato que o código contradiz **convida** o próximo agente ao erro.

### Decisão — (a) restringir a `User` + (b) fail-closed explícito com log

Escolhido o **híbrido (a)+(b)**: o contrato é **estrito a `User`** e uma entrada não-`User` é
**recusada explicitamente com log** (não um erro cru, não um `false` silencioso).

**Por quê (o alvo real da 29.7).** O alvo **não** vem de uma `Pessoas::Pessoa`:
- o scope da 29.6 resolve terceirizado por **VÍNCULO** e devolve `Pessoas::Vinculo` (readonly);
- o fluxo de desconsiderar parte do **registro a desconsiderar**, que é um `TimeRecord` cuja FK
  `user_id` aponta para `users` (não para `pessoas`);
- logo, o chamador tem em mãos um `User` (via `TimeRecord#user`), nunca uma `Pessoas::Pessoa`.

Nenhum chamador legítimo passa uma `Pessoas::Pessoa` — mas o contrato amplo **convidaria** a tentar.
Recusar explicitamente torna a armadilha visível e auditável no shadow.

### Patch

- `@param` passa a `[User]` com um bloco explicando o porquê (e por que NÃO aceitar `Pessoa`).
- Guard novo em `pode_desconsiderar?`: `unless frequentador.is_a?(User)` → `Rails.logger.warn(evento:
  "elegibilidade_desconsideracao.alvo_nao_user", classe_alvo:, acionador_id:)` e `return false`.
- Comentários de `mesmo_frequentador?`/`frequentador_de` ajustados (o alvo é sempre `User`; a ponte
  por CPF continua válida e serve para identidades que `User.id` não captura).

### Prova (dois sentidos)

- **Positivo (o teste discrimina):** `D1: alvo nao-User (Pessoas::Pessoa) e fail-closed com log, sem
  NoMethodError` — passa uma `Pessoas::Pessoa` REAL, assere `false` + log do evento. **Mutação:** ao
  **remover o guard**, o teste falha com o `NoMethodError` exato (`undefined method 'time_records' for
  an instance of Pessoas::Pessoa`, `dia.rb:45`). Prova que o teste exercita a MESMA condição real.
- **Controle positivo:** mesmo acionador/órgão com alvo `User` elegível **libera** — prova que o guard
  não é um `return false` incondicional.
- **Controle do mascaramento:** acionador nulo + alvo não-`User` nega **sem levantar** (o guard de
  entrada mascara, como documentado).

---

## D2 — o scope passa a logar (agregado) o que o PORO loga

### Diagnóstico

`frequentadores_visiveis.rb` tinha **0** logs; o PORO (`AutorizacaoFrequencia`) loga as **negações**
(`pessoa_ausente`, `pessoas_indisponivel`, `unidade_inelegivel`) — e só elas (não há log de
concessão). O `unidade_inelegivel` é explicitamente *"detalhe de auditoria... alimenta o shadow da
29.7/29.8"*. Sem o scope, o shadow veria **metade** do sistema.

### Decisão — agregado, uma vez por chamada (nunca por linha)

O scope é de **conjunto** (N vínculos); um `warn` por alvo negado inflaria o log proporcionalmente ao
universo de frequentadores. O PORO, que avalia **um** alvo, não tem esse problema. Decisão: replicar
os **mesmos eventos/formatos**, mas **agregados**.

| Evento | Fidelidade | Custo |
|---|---|---|
| `pessoa_ausente` (papel `:usuario`) | idêntico ao PORO, 1× por chamada | 0 query extra (reusa `pessoa_do_usuario`) |
| `pessoas_indisponivel` (papel `:usuario`) | mesmo resgate de erro do PORO | 0 query extra |
| `unidade_inelegivel` (agregado: `unidade_ids`+`unidades`) | **1 query** fixa por chamada | sem N+1 (medido) |

Três detalhes de fidelidade deliberados:
1. **`log_negacoes` só no caminho NÃO-role-geral.** O PORO de um usuário `role_geral` curto-circuita no
   passo 2 para todo alvo e **nunca** loga; emitir no scope seria log que o PORO nunca produz (e uma
   query a mais). O hook vem **depois** do `return base.distinct if role_geral?`.
2. **`pessoa_ausente` × `pessoas_indisponivel` são mutuamente exclusivos** (como no PORO): quando
   `por_user` levanta, o scope loga `pessoas_indisponivel` e NÃO loga `pessoa_ausente` por cima.
3. **Fidelidade de PRECEDÊNCIA da cascata** (fix do review, 2026-10-02). O PORO retorna no **primeiro
   match** (`AutorizacaoFrequencia#motivo`): um alvo liberado pelos passos **1/2/3/4** NUNCA chega ao
   passo 5 e NUNCA loga `unidade_inelegivel`. O agregado, se rodasse o D6 direto, contaria esses alvos
   — inflando o shadow de forma **sistemática** (todo alvo liberado por 1/3/4 com unidade inelegível na
   cadeia). Por isso o SQL exclui os alvos que 1–4 já liberariam (`liberado_por_passos_1_a_4`:
   `pessoas.cpf IN (cpfs_alvos)` ∪ o `EXISTS` de terceirizado). Provado por mutação: removida a
   cláusula, os dois testes de precedência (passo 1 e passo 4) falham reproduzindo o over-log.

O `unidade_inelegivel` agregado **reusa** os fragmentos `unidade_elegivel`/`path_valido` do próprio
scope (nenhuma segunda definição de "inelegível") e reproduz a **condição D6 dentro da cadeia**:
"a cadeia tem gestor-correspondente INELEGÍVEL E NENHUM gestor-correspondente ELEGÍVEL" — **adicionada
da precedência da cascata** (item 3 acima). Isto é: fidelidade de **evento** (mesmo evento/chaves),
fidelidade de **condição D6 na cadeia** (mesmo `houve_unidade_inelegivel_com_gestor`) **e** fidelidade
de **precedência** (só quando o passo 5 é de fato alcançado) — o código faz as três. Devolve o
`unid.id` da **unidade de lotação do alvo** — o mesmo id que o PORO registra (no caso `sub_inativa`,
loga a unidade ATIVA lotada, não a inativa ancestral).

### Limite declarado (não escondido)

- `pessoa_ausente` por **alvo** (o PORO pode logar com `papel: :alvo` para um alvo específico) NÃO é
  replicável numa query de conjunto sem varrer alvo a alvo (N+1). O scope cobre o **papel `:usuario`**
  (o gestor) — que é o mesmo objeto/causa de qualquer forma.
- O `ancestral_ausente` (o 4º log do PORO, emitido em `Pessoas::Unidade#cadeia_ascendente`) está **fora
  do escopo nomeado da tarefa** (a tarefa lista os 3 eventos do PORO; o `unidade_inelegivel` é o que
  ela marca como alimentador do shadow). Não replicado; registrado aqui como limite.
- O agregado `unidade_inelegivel` cobre a **unidade de lotação** (o `unidade_id` que o PORO registra),
  não a contagem exaustiva por ancestral.

### Patch

- Hook `log_negacoes` em `escopo` (linha após o curto-circuito de role geral).
- Novos métodos: `log_negacoes`, `log_ausencia`, `log_unidades_inelegiveis`,
  `ids_unidades_inelegiveis_como_gestor`, `gestor_match`, `cadeia_tem_gestor`,
  `liberado_por_passos_1_a_4` (fix de precedência do review).
- `pessoa_do_usuario` passa a logar `pessoas_indisponivel` no rescue (com flag anti-duplicação).
- **Nenhum comportamento do scope foi alterado** (só log) — os testes de propriedade/equivalência
  seguem verdes (104 pares / 34 visíveis / 70 negados / 0 divergências, agora **congelados** no teste).

### Prova (dois sentidos)

- `pessoa_ausente`: gestor com CPF sem pessoa no espelho → o scope loga o evento.
- `pessoas_indisponivel`: `por_user` levantando (stub por `com_metodo_de_classe_stubado`) → loga.
- `unidade_inelegivel` agregado: cenário `sub_inativa` → **sanidade** (o PORO loga no MESMO cenário) +
  o scope loga `unidade_inelegivel` com o **mesmo `unidade_id`** que o PORO registra (`sub`, a unidade
  de lotação — e NÃO a inativa ancestral).
- **Precedência (fix do review):** alvo liberado pelo passo 4 (e pelo passo 1) com unidade inelegível
  na cadeia → o scope **NÃO** loga (espelha o PORO).
- **Controles negativos:** sem unidade inelegível o scope **não** loga o evento; e o log **não**
  introduz N+1 (contagem de queries igual com poucos × 20 frequentadores extras).
- **Mutações:** (1) remover a chamada `log_negacoes` → falham `pessoa_ausente` e `unidade_inelegivel`;
  (2) neutralizar só o agregado → falha (e somente) o teste do `unidade_inelegivel`; (3) remover a
  cláusula de precedência → falham os dois testes de precedência (passo 1 e passo 4). Todas morrem.

### Bug encontrado e corrigido no caminho (3-valued logic)

O agregado `unidade_inelegivel` devolvia **vazio** no cenário que devia casar: `A AND NOT B`, com `B`
= `gestor_match` = `col1 IN (...) OR col2 IN (...) OR col3 IN (...)`. Numa unidade em que o usuário
**não** é gestor, os `IN` de colunas NULL devolvem `NULL` → `false OR NULL OR NULL` = **NULL** →
`NOT NULL` = NULL → a linha era descartada. **Fix:** `AND NOT COALESCE(B, FALSE)`. Provado por mutação
(remover o `COALESCE` faz o teste do agregado falhar). Lição registrada em `docs/governance/lessons.md`
(2026-10-02).

---

## D3 — fixture da 29.6 exercita a semântica multi-vínculo da D4

### Diagnóstico

O helper `alvo_lotado` cria **1 vínculo** por alvo. A 29.4 tem um teste com **2 vínculos ativos** (1
Não-Terceirizado + 1 Terceirizado) fixando a D4 ("algum vínculo ativo" → pessoa terceirizada); a 29.6
**não**. O Code Reviewer explicou por que **não é divergência de regra** (o scope resolve terceirizado
por VÍNCULO; o PORO por PESSOA; a união dos vínculos aprovados equivale à pessoa aprovada) — mas é um
**buraco de cobertura** num caso que o projeto marcou como sensível.

### Decisão — asserção POR PESSOA sob `visualiza_terceirizados`

O contrato do chamador (29.7) é por **pessoa**: a pessoa é visível quando **qualquer** dos seus
vínculos aparece no scope. O teste assere esse contrato (união dos vínculos ⇔ PORO), sob a role
`visualiza_terceirizados` (o passo 3, o único em que o PORO opera por PESSOA).

### Patch

- `pessoa_visivel_no_scope?(usuario, pessoa)` (união `escopo_ids ∩ vinculos_ativos`).
- Teste positivo: pessoa com 1 vínculo Efetivo + 1 Terceirizado (ambos ativos) → visível.
- **Controle negativo:** a MESMA pessoa sem o vínculo Terceirizado → **não** visível.
- Teste de contrato por pessoa para todo o fixture, restrito ao passo 3.

### Prova (dois sentidos, por mutação)

- **Mutação A** (`role_terceirizados?` → sempre `false`): o positivo **falha**.
- **Mutação C** (`TIPO_TERCEIRIZADO` = `"Efetivo"`): o **controle negativo falha**.
  Ou seja, a asserção **discrimina** — se o tipo do vínculo for ignorado, um dos lados morre.

---

## O que foi MEDIDO vs. SUPOSTO

### MEDIDO

| Medição | Resultado |
|---|---|
| Baseline dos arquivos-alvo (antes) | 39 runs, 0F/0E |
| Arquivos-alvo (depois, juntos) | 52 runs, 138 assertions, **0F/0E** |
| Suíte completa (depois, com o fix do review) | **1038 runs / 3543 assertions / 1F+11E / 0 skips** |
| Baseline declarado | 1025 / 3500 / 1F+11E / 0 skip |
| Delta | **+13 runs** = os 13 testes novos (3 D1 + 7 D2 + 3 D3); **mesmos** 1F+11E pré-existentes |
| Teste de propriedade (congelado) | **104 pares / 34 visíveis / 70 negados / 0 divergências** |
| A/B serial multi-arquivo (8 arquivos, seeds 1–6) | 0F/0E em **6/6 seeds** |
| Mutação D1 (remover guard) | falha com `NoMethodError` em `dia.rb:45` |
| Mutação D2 (remover `log_negacoes`) | 2 failures |
| Mutação D2 (neutralizar agregado) | 1 failure (só o teste do agregado) |
| Mutação D2 (remover `COALESCE`) | falha do teste do agregado (regressão do bug de 3-valued logic) |
| **Mutação D2 (remover a precedência)** | **2 failures** (passo 1 e passo 4 — reproduz o over-log do review) |
| Mutação D3 (role→false / tipo→Efetivo) | positivo falha / controle negativo falha |

> **Nota de medição:** uma execução intermediária deu 173 errors por `application.css` ausente (eu
> havia removido o artefato após a rodada anterior — a suíte precisa dele). Não é regressão: re-copiado
> o css, a suíte volta a 1F+11E. O css é gitignored e removido ao fim.

Os 12 pré-existentes da suíte: 11× `private method 'redirect_to'` (9 `Users::SessionsController`, 2
`Users::PasswordsController`) + 1× timezone em `presenca_endpoints_test.rb`. Nenhum é desta tarefa.

### SUPOSTO

- Que o 2º failure intermitente (`TimeRecordsControllerTest`, "08:00:00" vs "00:00:00",
  order-dependent) não é meu: **suposto** — não apareceu em nenhuma execução desta sessão (nem na
  suíte completa nem nos A/B seriais), mas não foi isolado por mim.
- Que o shadow da 29.7 consome os eventos por nome (`evento`), não por chave exata: **suposto** — o
  formato foi replicado do PORO (`evento` + ids), mas a 29.7 ainda não existe para confirmar.

---

## Riscos

- **Baixo.** D1/D2 são aditivos (D1 só recusa uma entrada que hoje já estouraria; D2 só adiciona log,
  sem alterar o conjunto devolvido pelo scope — os testes de equivalência seguem verdes).
- **D2 — volume:** o log é agregado (1 evento por chamada quando há negação), não por linha. Medido
  sem N+1.
- **D2 — alcance:** o `ancestral_ausente` (4º log do PORO) não foi replicado no scope (limite
  declarado); se a 29.7 precisar dele no shadow, é trabalho novo.
- **D3** é só teste — risco zero em produção.

## Arquivos alterados

- `api-ponto/app/models/elegibilidade_desconsideracao.rb` (D1)
- `api-ponto/app/models/frequentadores_visiveis.rb` (D2)
- `api-ponto/test/models/elegibilidade_desconsideracao_test.rb` (D1)
- `api-ponto/test/models/frequentadores_visiveis_test.rb` (D2 + D3)
- `docs/governance/lessons.md` (lição: 3-valued logic em SQL)
- `docs/progress/iteration_chore_debitos_pre_29_7.md` (esta rastreabilidade)

Sem alteração na `Ability` (29.7), no motor de cálculo, no `pode_ver?` da 29.4, no `desconsiderar!`
ou no comportamento do scope.

## Pendências / débitos

| Débito | Dono | Critério de pronto |
|---|---|---|
| Replicar `ancestral_ausente` no shadow do scope, se a 29.7 precisar | 29.7 | evento presente no log do scope |

---

## 📋 Relatório de Revisão — Code Reviewer (2026-10-02)

**Veredito: ✅ APROVADO — com blockers 0.** Relatório completo em
`docs/quality/review_report_chore_debitos_pre_29_7.md`.

**Status das tarefas:** D1 ✅ Implementado, ✅ Aprovado · D2 ✅ Implementado, ✅ Aprovado
(1 🟡) · D3 ✅ Implementado, ✅ Aprovado.

**O que foi reproduzido independentemente:**
- Arquivos-alvo juntos: **50 runs / 128 assertions / 0F / 0E**; A/B serial seeds 1/42 = verde.
- Serial de arquivos relacionados (PORO/Ability/Dia/TimeRecord/Calculo/Pessoa) seeds 1/42/6000 =
  **95/266/0F/0E** em 3/3.
- Equivalência propriedade = **104 = 34 T / 70 F / 0 div.** (probe independente).
- Fidelidade `sub_inativa`: PORO e scope logam 1× `unidade_inelegivel`, com o **mesmo** `unidade_id`.
- Mutações: D1 guard off → `NoMethodError` em `dia.rb:45`; D2 `COALESCE` off → 1 failure (só agregado);
  D2 `log_negacoes` off → 2 failures; D3 A/C → positivo/controle-negativo falham. **Todas as críticas morreram.**

**Apontamentos:** 🔴 0 · 🟡 2 (🟡1 sobre-reporte do agregado `unidade_inelegivel` vs a precedência da
cascata — conservador, alinhar com a 29.7; 🟡2 redação da linha 97) · 🟠 2 · 🟢 6.

**Falsos positivos refutados:** (1) testes D2 após `private` **não** são pulados — o macro `test` usa
`define_method`, que ignora `private` (provado por execução: 5 runs); (2) não há contaminação
cross-arquivo; (3) o PORO loga `pessoas_indisponivel` via `resolver_pessoa_por_user`; (4) sem N+1/volume.

**Pré-requisito de commit:** stage seletivo (2 models + 2 testes + `lessons.md` + esta iteration + o
relatório); **excluir** `api-ponto/log/test.log` e `api-ponto/tmp/cache/*`. Sem blocker técnico —
liberado para commit (`COMMIT_MODE=manual`).
