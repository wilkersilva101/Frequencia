# Relatório de Revisão — Code Reviewer — Complemento 29.3-D1..D4

> **Tipo:** review_report (revisão do complemento da 29.3 — rulings do CTO / ADR-0008 + achados F1/F2)
> **Data:** 2026-09-30
> **Branch de origem:** `feature/demanda-29-3-complemento` (worktree `wt-29.3-d1-d4`, base `7984ddf`) → destino: integração da Sprint 29
> **Base:** trabalho **NÃO commitado** (`COMMIT_MODE=manual`; sem commit/push)
> **Revisor:** Code Reviewer (sessão independente, worktree próprio)
> **Tarefas revisadas:** 29.3-D1 / 29.3-D2 / 29.3-D3 / 29.3-D4 (+ F1)
> **Arquivos alterados:**
> - `api-ponto/app/services/importar_gestores_individuais_service.rb` (modificado, `+202/-28`)
> - `api-ponto/test/services/importar_gestores_individuais_service_test.rb` (modificado, `+303`, 15 testes novos → 35)
> - `docs/progress/iteration_29.md`, `docs/governance/lessons.md` (modificados)
> **Insumos:** `docs/adr/0008-semantica-estado-gestor-individual-e-identidade-legado.md` (fonte dos 4 patches); `docs/quality/review_report_29_3.md`; models `GestorIndividual`/`GestorIndividualGerenciado`; `db/schema.rb` (índices UNIQUE parciais).

---

## Veredito

| Escopo | Veredito | Blockers | Sugestões |
|---|---|---|---|
| **29.3-D1..D4 + F1 (serviço + testes)** | ✅ **APROVADO** — os 4 rulings do ADR-0008 estão cumpridos e provados | 🔴 **0** | 🟡 4 / 🟠 1 / 🟢 3 |

**Nenhum blocker.** Os **4 rulings estão cumpridos e cada um tem teste que morre por mutação** (verifiquei M1–M9 independentemente, com harness descartável — as 9 morrem). A idempotência — critério central — **permanece** (`2ª/3ª execução = 0 criações`, medido). O commit está liberado (stage seletivo — ver 🟡4).

Os 4 achados 🟡 são **aprimoramentos de robustez**, não regressões: nenhum é coberto pelo baseline da 29.3 (a base não tinha tolerância de casing nem guarda de identidade), então esta entrega **melhora** o estado anterior em todos os eixos. O 🟡1 é o único que toca um risco já apontado pelo ADR-0008 (corrupção silenciosa de `ativo`) e merece atenção antes da importação real.

---

## Métricas medidas nesta revisão (independentes)

| Medição | Resultado medido | Declarado pelo autor | Status |
|---|---|---|---|
| Serviço 29.3 (isolado) | **35 runs / 123 assertions / 0 failures / 0 errors / 0 skips** | 35/123/0 | ✅ batido |
| Serviço + job + rake (direcionados) | **42 / 140 / 0 / 0 / 0** | — (o autor declarou 98/274/0 = serviço+job+rake+**models**; reconciliado abaixo) | ✅ |
| Direcionados declarados (98/274/0) | **89 / 274 / 0 / 0 / 0** (serviço 35 + job + rake + `test/models`) | 98/274/0 | ✅ assertions batem (274); `runs` diverge por `total_tests` do runner — sem impacto |
| `test/models` + `test/controllers/admin` | **518 / 1800 / 0 / 0 / 0** | 518/1800/0 | ✅ **baseline exato** |
| Suíte completa | **938 runs / 3289 assertions / 1 failure / 11 errors / 0 skips** | 938/3289 (923+15) / 12 pré-existentes | ✅ batido |
| RuboCop (2 arquivos do diff) | **0 offenses** | 0 offenses | ✅ |
| Zeitwerk | **All is good!** | OK | ✅ |
| Mutation testing (9) | **M1–M9 todas MORTAS** (reproduzidas independentemente) | 9 mortas | ✅ confirmado |
| Idempotência (2ª e 3ª execução) | **1/0 → 0/1 → 0/1**; 1 gestor e 1 vínculo; `updated_at` do gestor não muda na 2ª | — | ✅ preservada |
| Higiene (`application.css`) | **ausente** (só `.keep`); `git status` limpo de untracked | removido após medição | ✅ confirmado |

**Composição dos 12 pré-existentes (confirmada, nenhum novo):** **9×** `NoMethodError: private method 'redirect_to'` em `Users::SessionsController` + **2×** idem em `Users::PasswordsController` (Sprint 23/Devise) + **1×** timezone/`Expected "15/07/2026 11:30:45"` em `test/integration/presenca_endpoints_test.rb:171`. Todos fora do escopo da 29.3 (não tocam serviço/model de gestores). O briefing citava "11× Devise"; contei **11 no total** (9+2). A "13ª variação" flaky (`Pessoas::Vinculo.ativos` por `remove_method` destrutivo) **não se manifestou** nesta ordem de seed — coerente com o carácter order-dependent já provado no review da 29.3.

> **Nota de reconciliação do "98/274/0":** o conjunto que reproduz exatamente as **274 assertions** é `test/services test/jobs test/lib test/models` (89 runs nesta ordem de seed). O `runs` difere porque o Minitest conta `total_tests` do runner (o autor pode ter invocado os diretórios em ordem/agrupamento diferente). As **assertions (274)** e o **0/0** batem — o número não é inflado.

---

## Cumprimento dos 4 rulings (ADR-0008) — critério "o código cumpre o ruling?"

| Ruling | Veredito | Evidência |
|---|---|---|
| **D1 (Ruling 3)** — `ativo` do gestor determinístico, projeção pós-loop | ✅ **CUMPRIDO** | `aplicar_estado` para o gestor **removido** do loop; `recalcular_gestores_tocados` pós-loop (`service:139`, `unless @dry_run`). Teste de ordem A/B (`test:442`) verde; mutações M1/M2/M3 morrem. Ordem A e B dão o **mesmo** resultado. |
| **D2 (Ruling 1)** — guarda de identidade | ✅ **CUMPRIDO** | `conflito_de_identidade` (`service:402`) só no casamento por `id_legado` (`origem == :por_chave`); CPF e `gestor_user` do existente intactos; vínculo não criado. M4 morre. |
| **D3 (Ruling 2)** — marcador de nome + precedência | ✅ **CUMPRIDO** | `MARCADOR_SEM_NOME = "(sem nome — CPF "` (`service:76`); `aplicar_nome` (`service:441`) dá precedência ao nome real e nunca deixa o marcador sobrescrever nome real. M8/M9 morrem. |
| **D4 (F2)** — casing tolerante + contrato | ⚠️ **CUMPRIDO PARCIALMENTE** | Tolerância bidirecional **funciona** (M6 morre; camelCase e snake_case verdes). O `verificar_contrato!` (`service:193`), porém, é **frouxo demais** — não cobre o campo de exclusão (ver 🟡1). |
| **F1 (Ruling 5)** — reancoragem só na criação | ✅ **CUMPRIDO** | `encontrar_gestor` (`service:386`) casa só por `id_legado` quando presente; `aplicar_gestor` só reancora `id_legado`/`gestor_cpf` **na criação** (`service:307/311`). M5 morre. Colisão do índice parcial: teste `F1: reimportacao que recria...` verde. **Ressalva de criação duplicada — ver 🟡2.** |

---

## Achados por severidade

### 🔴 Blockers

**Nenhum.**

### 🟡 Sugestões de Melhoria

**🟡1 — `verificar_contrato!` é decorativo para o campo de EXCLUSÃO (o caso de pior risco do próprio ADR-0008).**
Arquivo: `app/services/importar_gestores_individuais_service.rb:193-205`.
Cenário **reproduzido** (harness descartável, removido): payload com `data_criacao` em snake_case **reconhecido** e a **exclusão** num terceiro casing desconhecido (`data_exclusao_legado`):
```
PROBE A -> nao_resolvidos=0  vinculo.ativo=true  vinculo.data_exclusao=nil  gestor.ativo=true
PROBE A -> CORRUPCAO SILENCIOSA? true
```
O `any?` sobre a linha inteira "perdoa" a linha porque **qualquer** uma das 4 chaves (criação **ou** exclusão) casa. Resultado: um gestor excluído no legado entra **ATIVO sem `data_exclusao`** — exatamente a corrupção silenciosa que o D4 foi criado para matar. Pior: o contrato **não** é exercitado com o campo mais crítico (`data_exclusao`), e um payload **parcialmente** migrado (metade das linhas com o casing antigo, metade com um novo) passa em silêncio. O `any?` sobre a lista também é frouxo (uma única linha reconhecida "protege" as demais).
Sugestão: verificação **por campo e por linha**, não por "alguma chave": exigir que, se **alguma** linha traz uma data de exclusão não-nula, ela venha num casing conhecido; ou (mais simples) fazer o check por campo — `linha.key?(:data_exclusao) || linha.key?(:dataExclusao)` deve valer para toda linha cujo `id` é válido, e abortar se nenhuma linha reconhecer **exclusão** quando o payload tem qualquer indício de exclusão. Alternativa pragmática: registrar no relatório (não abortar) as linhas cujo campo de exclusão não foi encontrado em nenhum casing, para que a importação real fique auditável. **Não bloqueia o commit** (a tolerância bidirecional primária funciona e o ADR-0008 já classifica o F2 como "bloqueia a importação real, não o commit"), mas **deve ser resolvido antes de rodar a importação real** — é o mesmo eixo de risco.

**🟡2 — F1 introduz criação duplicada quando a base veio da ponte CPF e depois chega `id_vinculo_gestor`.**
Arquivo: `app/services/importar_gestores_individuais_service.rb:386-398` (`encontrar_gestor`) + `:307-311` (`aplicar_gestor`).
Cenário **reproduzido** (harness descartável, removido):
```
PROBE E -> gestores CPF=1 -> apos linha com id_legado=900: 2 ([nil, 900])
```
Se uma base foi importada **antes** de o vínculo existir (linha sem `id_vinculo_gestor` → gestor casado pela ponte CPF, com `id_legado = nil`), e **depois** chega uma linha com `id_vinculo_gestor = 900` para o **mesmo CPF**, o ramo `:por_chave` não encontra por `id_legado: 900` e cria um **segundo** `GestorIndividual` para o mesmo CPF (um com `id_legado` nil, outro com 900). F1 resolveu o sentido "não mover/reancorar um gestor existente" (M5 morre), mas o sentido inverso (base legada por ponte → vínculo aparece) **duplica a PESSOA-gestor**. Não é colisão de índice (não há UNIQUE em `gestor_cpf`), então não quebra a suíte — mas viola o propósito do `GestorIndividual` (uma linha por PESSOA) e poluiria a tela `admin/gestores_individuais` com o gestor duplicado.
Sugestão: na criação, além de procurar por `id_legado`, procurar também por `gestor_cpf` **apenas quando o candidato tem `id_legado` nil** (adoção: assume o registro de ponte e grava o `id_legado` nele), evitando a duplicação sem reintroduzir o "mover entre linhas". Ou documentar explicitamente que a base de ponte é transitória e não convive com a base ancorada. **Não bloqueia o commit** (cenário só ocorre com base mista; a base legada está estável e ancorada hoje).

**🟡3 — D2 descarta a linha inteira em mudança benigna de CPF (perde vínculo legítimo).**
Arquivo: `app/services/importar_gestores_individuais_service.rb:256-259` + `:402-408`.
Cenário **reproduzido** (harness descartável, removido): gestor importado com `id_vinculo_gestor=900` / CPF `A`; numa execução futura o **mesmo** `id_legado` resolve para CPF `B` (correção cadastral no Pessoas, exoneração+novo vínculo com o mesmo id, etc.):
```
PROBE C -> imp=0  nao_resolvidos=1  motivo="conflito de identidade: o id_legado do g..."
PROBE C -> vinculo id2 criado? false
```
A guarda **funciona como ruling** (não reescreve CPF/`gestor_user`) e o motivo é acionável (traz ambos os CPFs e diz que nada foi tocado). Mas um vínculo gerido→gestor **legítimo é silenciosamente perdido** por uma mudança de CPF de motivo benigno — e o relatório fica só com o "não resolvido" para quem inspecionar. Mudança de CPF é rara, mas existe (esta é a ressalva do briefing #3, e o ADR-0008 regra 4 a admite como trade-off defensivo aceito). Sugestão: como o ruling já foi tomado, **não** alterar a decisão, mas (a) qualificar o motivo no relatório (`"conflito de identidade (possível mudança de CPF do gestor) — verifique manualmente e reancore"`) e (b) registrar um teste de que a linha continua **reenviável** após correção manual do `gestor_cpf`. Alternativa a submeter ao CTO: distinguir "CPF divergente **sem** `id_vinculo` novo" (provável mudança cadastral → reancorar) de "CPF divergente **com** `id_vinculo` novo" (provável reaproveitamento → `nao_resolvido`). **Não bloqueia o commit** — é o comportamento decidido pelo CTO; a sugestão é de acionabilidade/refinamento.

**🟡4 — Higiene de stage: `log/test.log` e `tmp/cache/bootsnap/load-path-cache` continuam rastreados e modificados.**
Arquivo: `wt-29.3-d1-d4/.gitignore:7-8`. Herdado do review da 29.3 (🟡1 de lá; ainda em aberto). Cenário: `git status` mostra os dois como `M` apesar do `.gitignore` (foram rastreados antes de o ignore cobri-los). O commit é manual (`COMMIT_MODE=manual`), então a disciplina é do dev. Sugestão: stage **seletivo** (apenas os 2 arquivos de código/teste + os 2 `.md`), nunca `git add -A`; débito correlato: `git rm --cached` dos dois. **Não bloqueia.**

### 🟠 Sugestão de Qualidade / Débito

**🟠1 — A suíte continua sem o **payload real** do endpoint; o D4 fecha o risco por construção, não por evidência.**
Arquivo: `test/services/importar_gestores_individuais_service_test.rb:54-67` (`linha_camel` — payload sintético). O ADR-0008 (regra 8) pede "normalizar a leitura para aceitar ambos os casings **e adicionar teste com o payload real**". O teste com camelCase existe, mas é **construído pelo próprio autor** a partir da evidência indireta (o Pessoas2 lê camelCase); não é uma amostra real. O 🟡1 mostra que a rede de proteção para um **terceiro** casing é incompleta. Débito: obter uma **amostra real/contrato** de `gestores_individuais` (ou o código do endpoint Sticapi, ausente do repo) e fixá-la como fixture — é a única forma de transformar o D4 de "cobre os casings que imaginamos" em "prova o casing real". **Débito de sistema externo, fora do controle do dev; não bloqueia o commit.** Já registrado como suposição no `iteration_29.md:269-274`.

### 🟢 Elogios

| ID | Elogio | Tarefa |
|---|---|---|
| 🟢1 | **Ruling 3 fechado com prova de ordem, não com código.** O teste `D1: ativo do gestor independe da ORDEM` (`test:442`) exercita as duas ordens e o controle negativo, e ainda prova que a reimportação **restaura** o `ativo` verdadeiro. Fecha o order-dependence do 🟡2 do review da 29.3 por regra explícita. | 29.3-D1/F1 |
| 🟢2 | **Guarda de identidade como segunda condição barata, com `[gestor, origem]` explícito.** `encontrar_gestor` devolve a origem e a guarda só roda em `:por_chave` — a assimetria vínculo↔pessoa do ADR-0008 regra 4 fica tratada sem custo no caminho comum, e o teste prova que CPF **e** `gestor_user` do existente ficam intactos (evita auto-autorização na cascata). | 29.3-D2 |
| 🟢3 | **`recalcular_gestor` usa o escopo `ativos` e escreve só `if gestor.changed?`.** Consumo via índice parcial (fecha o Bug 16 no próprio D1) e sem UPDATE espúrio — a idempotência do gestor se mantém (`updated_at` não muda na 2ª execução, medido). | 29.3-D1 |

---

## Falsos positivos refutados

| Alegação a verificar | Resultado |
|---|---|
| "A projeção pós-loop pode **perder** alguma atualização que antes acontecia (um gestor cujo vínculo não mudou)" | ❌ **Refutada.** `@gestores_tocados[gestor.id] = true` é marcado para **toda** linha aplicada com sucesso (`service:277`), e `recalcular_gestor` sempre grava o estado correto derivado dos vínculos — não depende de o vínculo ter mudado. Um gestor com vínculos inalterados entra em `@gestores_tocados` e é recalculado igualmente (idempotente: `changed?` falso → nenhum UPDATE). Medido: 2ª/3ª execução = 0 criações e `updated_at` estável. |
| "O `unless @dry_run` cobre o dry-run corretamente (não deixa estado)?" | ❌ **Refutada a preocupação.** Sem recálculo, o dry-run **não** escreve o gestor; e no ramo não-dry o gestor já tem `save!` no loop e o recálculo só o atualiza. Em dry-run os contadores de `importados/atualizados` contam a projeção **sem** persistir (testes `dry-run` verdes, `assert_no_difference`). |
| "A F1 fecha a colisão do índice parcial na reimportação que reativa um vínculo" | ✅ **Confirmada.** Teste `F1: reimportacao que recria um vinculo apos exclusao legada nao colide com o indice parcial` (`test:520`) verde: um único vínculo ATIVO por par (`ativos.count == 1`), sem `RecordNotUnique`. O índice UNIQUE parcial `WHERE ativo` comporta o histórico. |
| "A mutação que mata a guarda de identidade realmente morre?" | ✅ **Confirmada.** M4 (guarda neutralizada) → `D2` falha (`Expected 0, Actual 1`). Também M5 (F1 volta à ponte CPF) → `F1` falha. |
| "9 mutações mortas" | ✅ **Confirmada integralmente.** Reproduzi **as 9** (M1–M9) com harness descartável; todas morrem, com a contagem de falhas declarada pelo autor (M1=3, M2=5, M3=1, M4=1, M5=1, M6=1, M7=1, M8=2, M9=1). |
| "O `application.css` copiado temporariamente foi removido" | ✅ **Confirmada.** `api-ponto/app/assets/builds/` contém só `.keep` (gitignored fora do `.keep`); `git status --untracked-files=all` limpo além de log/tmp. `credentials.yml.enc`/`.ruby-version`/`.tool-versions` intocados. |
| "A suíte tem 12 pré-existentes e +15 novos = 938 exatos" | ✅ **Confirmada.** 938 runs / 3289 assertions; 1 failure + 11 errors, composição 9 Sessions + 2 Passwords + 1 timezone. |

---

## Ações corretivas

- [ ] **(Antes do commit)** Stage seletivo (🟡4): incluir apenas `api-ponto/app/services/importar_gestores_individuais_service.rb`, `api-ponto/test/services/importar_gestores_individuais_service_test.rb`, `docs/progress/iteration_29.md` e `docs/governance/lessons.md`; **não** incluir `log/test.log` nem `tmp/cache/...` (nunca `git add -A`).
- [ ] **(Antes da importação real em produção, não do commit)** Endurecer `verificar_contrato!` para cobrir o campo de **exclusão** por linha (🟡1) e obter uma amostra real do payload (🟠1) — o ADR-0008 já classifica o F2 como bloqueio da importação real.
- [ ] **(Antes da 29.4/29.6, não do commit)** Endereçar a duplicação de criação da base mista de F1 (🟡2) e melhorar a acionabilidade do motivo de conflito de identidade (🟡3) — sem alterar a decisão do CTO.
- [ ] **(Oportunístico)** `git rm --cached` de `log/test.log` e `tmp/cache/bootsnap/load-path-cache` (🟡4, débito correlato).

**Nenhum item acima é bloqueio do commit desta tarefa.** Todas as ações **pré-commit** estão satisfeitas no working tree (a única pendência é a disciplina de stage, e `COMMIT_MODE=manual` deixa o commit ao dev).

---

## Certificação de entrega

Entrega técnica **aprovada** (0 blockers 🔴). O commit/merge desta entrega exige o **protocolo de entrega do Code Specialist**: agrupamento de commits atômicos e push conforme a convenção semântica. O fechamento desta rastreabilidade é pré-requisito para o início da próxima tarefa.

---

# 🔁 RE-REVIEW do achado 🟡1 — contrato endurecido (Code Reviewer, 2026-09-30)

> **Nota histórica:** o veredito acima (**✅ APROVADO, 0 blockers**, 🟡1..🟡4 / 🟠1 / 🟢1..3) é preservado como registro da 1ª passada. Esta seção é o re-review do **único** ponto reaberto: o 🟡1 (`verificar_contrato!` frouxo para o campo de exclusão), corrigido pelo autor após o veredito. Mesma branch/worktree (`feature/demanda-29-3-complemento`, `wt-29.3-d1-d4`), `COMMIT_MODE=manual`, sem commit/push.

## Veredito do re-review

| Escopo | Veredito | Blockers | Observações novas |
|---|---|---|---|
| **Fechamento do 🟡1 (contrato por campo e por linha)** | ✅ **FECHADO** | 🔴 0 | 🟡 reaberto como **risco residual** (heurística pode rejeitar payload válido); não bloqueia o commit nem a importação real (payload real é camelCase = casing conhecido) |

## O que o autor mudou (verificado no código)

`app/services/importar_gestores_individuais_service.rb`:
- `verificar_contrato!` (`:210-230`) agora itera `linhas.each` e chama `verificar_campo_de_data!` para **exclusão** (`:214`) e **criação** (`:215`) — fecha o `any?` sobre a linha **e** sobre a lista.
- `verificar_campo_de_data!` (`:235-245`): casing conhecido → OK; ausente o conhecido **mas** há chave "parecida" (via `chave_normalizada` → `downcase.gsub(/[^a-z0-9]/, "")`, `:251-253`) → `ArgumentError` nomeando o campo; nenhuma parecida → ausência legítima → OK.
- Rede secundária mantida (`:218-229`); `registros: []` segue não-violacão (`:211`).

## Probes independentes (harness descartável, removido)

| Probe | Cenário | Resultado medido |
|---|---|---|
| Q1 | exclusão em `dataExclusao2` (3º casing) + criação reconhecida | **ABORTA** ✅ (furo original fechado); 0 gestores / 0 vínculos gravados |
| Q2 | linha OK + linha com `data_exclusao_legado` | **ABORTA** ✅ (furo do `any?` sobre a lista fechado); 0 gravados |
| Q3 | linha sem nenhum campo de exclusão | **PASSA** ✅ (importados=1, vínculo ativo; sem falso positivo) |
| B1 | variante `data_fim` (não contém "exclusao") | **PASSA EM SILÊNCIO** ⚠️ (vínculo ativo, `data_exclusao=nil`) |
| B2 | variante `dt_exclusao` (contém "exclusao") | **ABORTA** ✅ |
| D1 | criação em `dt_criacao` | **ABORTA** ✅ |
| A1 | `observacao_exclusao` sem campo real de exclusão | **REJEITA payload válido** ⚠️ (falso positivo) |
| A2 | `exclusao_motivo` sem campo real de exclusão | **REJEITA payload válido** ⚠️ (falso positivo) |
| A3/E1 | `observacao` normal / `data_exclusao: nil` | **PASSA** ✅ |
| C1 | nenhuma linha com casing conhecido | **ABORTA** ✅ (rede secundária alcançável) |
| C2 | só criação conhecida (sem exclusão) | **PASSA** ✅ (rede secundária **não** alcançável aqui) |

## Análise crítica dos pontos dirigidos

**1. O fechamento abre outro furo?** O furo original está fechado (Q1/Q2 abortam, nada gravado). A discriminação por `chave_normalizada` é heurística de **substring**: um campo de exclusão que mude de nome sem a palavra `exclusao` (ex.: `data_fim`) **passa em silêncio** e reproduz a corrupção (B1). Escopo: o endpoint real usa `dataExclusao` (casing conhecido), então é cenário de "campo renomeado" — o mesmo risco global que a rede secundária já cobria imperfeitamente. Resíduo, não regressão.

**2. O falso positivo foi evitado?** Não de forma absoluta. **A1/A2 são falsos positivos reais**: um payload cujo campo de exclusão está **ausente** (vínculo nunca excluído) mas que carrega uma chave homônima que contém a palavra (`observacao_exclusao`, `exclusao_motivo`) é **rejeitado alto**. Com o contrato **por linha**, uma linha assim **aborta a importação inteira**. O payload real (lido por `pessoas2/app/models/gestao_individual.rb:23`) tem as chaves `id`, `id_vinculo_gestor`, `matricula_gestor`, `id_vinculo_gerido`, `matricula_gerido`, `dataCriacao`, `dataExclusao`, `observacao` — nenhuma homônima de risco; logo **não** é falso positivo contra o contrato real. É o trade-off de um gate fail-closed, decidido pelo autor como "falha ALTO". Registro como **🟡A — risco de falso positivo em payload futuro**, não blocker.

**3. A rede secundária serve para algo?** Sim, mas só numa janela estreita: ela dispara **só quando nenhuma linha traz qualquer casing conhecido de criação ou exclusão** (C1 aborta). No caminho normal o per-field já decidiu antes e a rede é inalcançável (C2). É guarda de "troca global de formato", não código morto — mantida como está. Sem impacto.

**4. As mutações M10–M13 morrem?** Sim, todas (reproduzi com backup manual; `git checkout` seria destrutivo sobre trabalho não commitado): **M10** (per-field vira no-op) → 2 failures ✅; **M11** (`chave_normalizada` quebrada) → **1 failure** ✅ (autor declarou 2 — divergência de contagem, mutação morta); **M12** (remove o `return` de ausente-legítimo) → **1 error** ✅ (rejeita payload válido, como previsto); **M13** (volta ao `any?` sobre a linha) → 2 failures ✅. Serviço restaurado ao md5 original (`1d16289a...`) após cada uma.

**5. Nada regrediu?** Não. Serviço isolado **38/136/0** (baseline); serviço+job+rake **45/153/0/0/0**; `test/models`+`test/controllers/admin` **518/1800/0/0/0** (baseline exato); suíte **941/3295/1F+12E** (2ª execução reproduziu exato; na 1ª houve 13E, sendo o 13º a variação flaky `Pessoas::Vinculo.ativos` por `remove_method` destrutivo, que **passa isolado** e não toca o diff — o serviço só usa `Pessoas::Vinculo.where`, nunca `.ativos`). D1–D4 e idempotência seguem intactos (nenhum caminho legítimo quebrado; o endurecimento só adiciona um gate pré-loop).

**6. Higiene.** ✅ `log/test.log`/`tmp/cache` modificados mas **fora do escopo de stage** (stage seletivo); `credentials.yml.enc`/`.ruby-version`/`.tool-versions` **intocados** (`git diff` vazio); `app/assets/builds/` contém só `.keep` (o `application.css` temporário que copiei para as medições foi **removido** — e o harness descartável também).

## Métricas do re-review

| Medição | Resultado | Declarado pelo autor | Status |
|---|---|---|---|
| Serviço isolado | **38 / 136 / 0 / 0 / 0** | 38/136/0 | ✅ batido |
| Serviço+job+rake | **45 / 153 / 0 / 0 / 0** | 45/153/0 | ✅ batido |
| `test/models` + `test/controllers/admin` | **518 / 1800 / 0 / 0 / 0** | — (baseline exato) | ✅ |
| Suíte completa (2ª exec.) | **941 / 3295 / 1F + 12E / 0 skips** | 941/3295/1F+12E | ✅ batido exato |
| RuboCop (2 arquivos) | **0 offenses** | 0 | ✅ |
| Zeitwerk | **All is good!** | OK | ✅ |
| Mutation M10/M11/M12/M13 | **todas MORTAS** (2/1/1 erro/2) | 2/2/1/2 | ✅ mortas (M11 difere em nº, não em status) |
| Falso positivo (payload real camelCase) | **NÃO** (chaves reais não são homônimas) | não contemplado | ✅ |

## Ações corretivas (re-review)

- [ ] **(Oportunístico, não-bloqueante)** Considerar tornar a heurística de variante mais estrita (igualdade da palavra distintiva em vez de substring, ou ignorar chaves cujo nome contenha `observacao`/`motivo`/`justificativa`) para eliminar o falso positivo A1/A2 em payloads futuros — hoje inofensivo porque o payload real usa `dataExclusao` (casing conhecido).
- [ ] **(Antes do commit)** Stage seletivo inalterado (🟡4).
- [x] **🟡1 — contrato endurecido por campo e por linha: FECHADO** (Q1/Q2 abortam, Q3 não é falso positivo contra o contrato real).

**Nenhum blocker no re-review.** O 🟡1 está fechado e não abre furo novo contra o payload real; o risco residual (falso positivo A1/A2 / variante renomeada B1) é de payload futuro e fica como observação 🟡A.

## Certificação de entrega (re-review)

Entrega técnica **aprovada** (0 blockers 🔴), 🟡1 **fechado**. O commit segue liberado com **stage seletivo** (`COMMIT_MODE=manual`); o protocolo de entrega do Code Specialist (commits atômicos + push) permanece como fechamento da rastreabilidade, pré-requisito da próxima tarefa.
