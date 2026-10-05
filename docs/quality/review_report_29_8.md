# Relatório de Revisão — Tarefa 29.8 (Matriz de aceite e auditoria)

> **Revisor:** Code Reviewer (AI Workflow) · **Data:** 2026-10-02
> **Worktree:** `/home/davi.queiroz/Área de trabalho/workspace_integração/wt-29.8` · **Branch:** `feature/demanda-29-8-matriz-aceite-auditoria` @ `df57cf5`
> **Modo:** `TASK_MODE=STANDARD`, `COMMIT_MODE=manual`, `MEMORY_MODE=classic`, `SUGGESTION_LEVEL=1`
> **Veredito:** ✅ **APROVADO** — **0 Blockers** · 🟡 3 · 🟠 2 · 🟢 3
> **Critério da 29.8 (3 itens):** 3/3 cumpridos e verificados nesta revisão.

---

## 1. Metadados

| Item | Valor |
|---|---|
| Branch origem → destino | `feature/demanda-29-8-matriz-aceite-auditoria` → `integration/sprint-29` |
| Commit base | `df57cf5` |
| Arquivos novos (2) | `test/controllers/admin/frequencia_matriz_aceite_test.rb`, `test/models/frequencia_shadow_report_test.rb` |
| Arquivos de código modificados (4) | `app/models/frequencia_autorizacao_cascata.rb`, `app/controllers/concerns/frequencia_authorization.rb`, `app/controllers/admin/frequencia_controller.rb`, `app/controllers/admin/frequentadores_controller.rb` |
| Arquivos de teste modificados (2) | `test/controllers/admin/frequencia_cascata_controller_test.rb`, `test/models/frequencia_autorizacao_cascata_test.rb` |
| Docs (2) | `docs/progress/iteration_29.md`, `docs/governance/lessons.md` |
| Artefatos a excluir do stage | `api-ponto/log/test.log`, `api-ponto/tmp/cache/bootsnap/load-path-cache` |
| Escopo adicional declarado | absorve os débitos S1/S3/S4 da 29.7 (S4 entra como CÓDIGO) |

---

## 2. Verificação independente (medida nesta revisão)

| Verificação | Comando | Resultado |
|---|---|---|
| Testes-alvo da 29.8 | `bin/rails test` (matriz + shadow + cascata controller + cascata model) | **33 runs / 184 asserts / 0F / 0E** ✅ |
| Shadow report (item 4) | idem | imprime `eventos=4 por_motivo={negado: 4} divergencias=0 causas_unidade_inelegivel=2` ✅ |
| Suíte completa | `bin/rails test` | **1080 runs / 3765 asserts / 1F + 11E / 0 skips** ✅ (as 12 são pré-existentes; +20 runs vs. baseline) |
| Zeitwerk | `bin/rails zeitwerk:check` | `All is good!` ✅ |
| RuboCop (8 arquivos novos/alterados) | `bin/rubocop` | **no offenses detected** ✅ |
| Restauração de mutações | `diff` vs. backup | **5/5 arquivos idênticos, 0 resíduo** ✅ |

---

## 3. Resultado item a item

### Item 1 — Matriz de aceite (12 cenários) ✅
`frequencia_matriz_aceite_test.rb`, 13 casos (2a/2b desdobram a role geral). Cobertura do critério:

| Cenário | Caso | Controle positivo ao lado? |
|---|---|---|
| próprio | 1 | — (positivo) |
| role geral | 2a admin / 2b `visualiza_frequentadores` | — (positivos) |
| terceirizado c/ role | 3 | — (positivo) |
| terceirizado s/ role | 4 | ✅ `com_flag(nil)` mostra; `:on` oculta |
| GI ativo | 5 | — (positivo) |
| GI inativo | 6 | ✅ controle duplo |
| hierarquia avô (atual) | 7 | — (positivo) |
| hierarquia pai (substituto) | 8 | — (positivo) |
| excepcional | 9 | — (positivo) |
| unidade inelegível (D6) | 10 | ✅ controle duplo |
| sem vínculo | 11 | ✅ controle + `refute can?(:read, próprio)` |
| sem CPF (S3) | 12 | ✅ controle + `refute can?(:read, próprio)` |

- **Negativos não-degenerados (lição 33):** os 5 negativos (4/6/10/11/12) têm controle positivo (sem flag) e o positivo sempre é medido no **mesmo** caminho. O cenário 11 passa a flag `nil` e `on` com `assert_ve` nos dois atores, e o `:on` refuta os dois — a negação não pode passar por "setup vazio".
- **Contrato "→ 403":** o app `rescue_from CanCan::AccessDenied → redirect_to dashboard` (`admin/application_controller.rb:47`) — o app **não** produz 403; a negação no `index` é a **filtragem** da listagem. A matriz prova o **substantivo** do critério (negado) por (a) listagem vazia e (b) `Ability#can?(:read, instância) = false`. Interpretação **arquiteturalmente correta e declarada** — aceita.

### Item 2 — Débito S2 (RuboCop das 4 offenses da 29.7) ✅ RESOLVIDO
`ability.rb` está limpo (`no offenses detected` no arquivo). Confirma que o autocorrect da 29.7 foi eficaz e o registro corrigido.

### Item 3 — S1 (isolar a flag em `time_records`) ✅
- O teste do admin agora roda o **mesmo cenário** com `com_flag(nil)` E `com_flag("on")`, asserindo a **invariância** do admin (passo 2).
- **Controle de discriminação** adicionado: um usuário **não-global** vê o próprio registro sem a flag e "Nenhum registro encontrado" sob a flag. Confirmei que o discriminador é o **conteúdo** da tabela (não o heading), corrigindo o sintoma original. **M11 (restringir no-op) mata 9F**, provando que a variável é exercitada.

### Item 4 — Relatório do shadow ✅ (determinístico)
- Método declarado e reproduzido: `RAILS_ENV=test bin/rails test test/models/frequencia_shadow_report_test.rb`. **Não há `rand`/`SecureRandom`/seed na lógica de visibilidade** — só `proximo_cpf()` (determinístico por pid) e cenários fixos → **estável e reproduzível**.
- **A contagem por motivo é ASSERTADA**, não só impressa: `assert_equal 4, shadow.size` e `assert_equal({ negado: 4 }, por_motivo)`. O `puts` é evidência.
- Números reproduzidos exatamente: **4 / {negado: 4} / 0 divergências / 2 `unidade_inelegivel`**.

### Item 5 — Mutação NÃO-morta declarada = **teste degenerado real** ⚠️
O agente declara que mutar o PORO da 29.4 não derruba a matriz. **Confirmei — e fui além:**
- Mutação aplicada: `AutorizacaoFrequencia#gestor_individual?` → `GestorIndividualGerenciado.all` (passo 4 ignora `.ativos`).
- **Matriz sozinha: 13/55/0F** — NÃO mata (confirmado).
- **`frequencia_shadow_report_test.rb` sozinho: MATA** (1F) — `por_motivo` vira `{negado: 3, gestor_individual: 1}` porque o GI **inativo** passa a ser liberado pelo PORO, mudando o `motivo` do log.

**Conclusão:** a matriz é cega ao PORO por design (correto, escopo da 29.4), MAS a **justificativa do agente de que "o PORO é coberto pela suíte da 29.4" NÃO se sustenta como está** — nenhuma suíte da 29.8/29.7 exercita o PORO no cenário GI. Isso é **falha de cobertura espelhada** no twin Ruby × SQL: o **mesmo bug no passo 4** existe em `FrequentadoresVisiveis#geridos_user_ids` (scope, usa `.ativos`) e no PORO. Ver **🟡 S2** (recomendação de baseline explícito).

### Item 6 — Suíte completa ✅
**1080/3765/1F+11E/0 skips** reproduzido. Baselines declarados: 29.7 = **1060/3663/1F+11E**; pré-chore = 1038/3543. Δ = **+20 runs, 0 falhas/erros novos**. As 12 são as pré-existentes (11× Devise `redirect_to` + 1× timezone em `PresencaEndpointsTest`).

### Item 7 — Qualidade ✅ (com o achado S4 abaixo)
- RuboCop **0 offenses** nos 8 arquivos; Zeitwerk OK; arquitetura preservada; **nenhuma migration/auth** tocada além do S4 (só log). A mutação do agente no fail-closed do scope (`"1 = 0"`→`"1 = 1"`) mata 2F — reproduzi e confirmei a discriminação.

---

## 4. Blockers (🔴)

**Nenhum.** Não foi encontrada fuga de autorização, quebra de baseline, nem regressão.

---

## 5. ⚠️ Achado prioritário — cobertura PARCIAL do S4 (classificado 🟠, não blocker)

**O débito S4 existe para dar rastro às negações do modo `:on`. Foi implementado em apenas 2 das telas que NEGAM.**

| Tela | Restringe sob `:on`? | Loga negação `:on`? |
|---|---|---|
| `frequencia#index` | ✅ (`restringir_frequencia`) | ✅ `registrar_negacoes_frequencia` |
| `time_records#index` | ✅ (`restringir_frequencia`) | ❌ **MUDO** |
| `frequencia_por_orgao#index` | ✅ (interseção `cpfs &= frequentadores_visiveis_cpfs`) | ❌ **MUDO** |
| `frequentadores#index` | ✅ (`incluir_cpfs_com_cascata`) | ✅ `registrar_negacoes_frequentadores` |
| `parcial#index` | ❌ (`@registros = []`) | — (`:off` no-op) |
| `relatorio_terceirizados#index` | ❌ (`@registros = []`) | — (`:off` no-op) |

**Impacto:** com a flag `:on`, **2 das 4 telas que negam** (`time_records`, `frequencia_por_orgao`) negam frequentadores **sem emitir nenhum log**. O objetivo declarado da tarefa é "auditoria"; auditar em produção com metade das telas mudas é cobertura **parcial que parece completa** — exatamente o buraco que o S4 existia para fechar.

**Agravantes verificados:**
1. **Assimetria shadow×on no `time_records`:** `observar_cascata_frequencia(registros)` (shadow) é chamado, mas **não** `registrar_negacoes_frequencia` (on). No `frequencia`, os **dois** são chamados. O commit torna o `:on` **menos** auditável que o shadow na MESMA tela — o inverso da finalidade (auditar de verdade).
2. **`frequencia_por_orgao` não tem shadow nem on-log:** nenhuma observabilidade, apesar de negar via interseção de CPFs.
3. **Declaração imprecisa no `iteration_29.md`:** o texto diz "wiring das chamadas de log do `:on` antes da restrição (`restringir_frequencia`/`incluir_cpfs_com_cascata`)" — omite que há 2 caminhos de restrição **sem** log.
4. **O relatório do shadow sugere que os eventos `:on` "saem no log" em produção** ("os mesmos eventos `EVENTO_SHADOW`/`EVENTO_NEGACAO` saem no log") — verdadeiro só para 2 das 4 telas.

**Classificação: 🟠 (débito), não blocker.** Não há vazamento nem regressão; a decisão de acesso é idêntica (o log é aditivo). Mas é um débito **material** de observabilidade e deve ter dono (ver Ações Corretivas) — **não** deixar implícito como "coberto".

---

## 6. Mutations que EU reproduzi (backup `/tmp/rev298_backup/`, restauração verificada por `diff`)

| # | Mutação | Arquivo | Teste | Resultado |
|---|---|---|---|---|
| M1 | `log_negacao` ignora a flag (`return unless ligada?` → `true`) | `frequencia_autorizacao_cascata.rb` | cascata model | **1F** ☠️ |
| M2 | `registrar_negacoes_frequencia` no-op | concern | cascata controller | **1F** ☠️ |
| M4 | `EVENTO_NEGACAO == EVENTO_SHADOW` | `frequencia_autorizacao_cascata.rb` | model + controller | **4F** ☠️ |
| M11 | `restringir_frequencia` no-op | concern | matriz | **6F** (agente: 9F) ☠️ |
| — | PORO `gestor_individual?` ignora `.ativos` | `autorizacao_frequencia.rb` | matriz | **0F — NÃO morre** ⚠️ |
| — | PORO idem | `autorizacao_frequencia.rb` | shadow report | **1F** ☠️ (por outro teste) |

**Restauração:** `cp` do backup + `diff -q` → 4/4 arquivos **idênticos**; `git diff --stat HEAD` inalterado; zero resíduo `MUTATED`. Suíte-alvo re-rodada pós-restauração: **33/184/0F/0E**.

---

## 7. Sugestões

### 🟡 S1 — Estender o log de negação às demais telas que restringem (débito S4 incompleto)
Adicionar `registrar_negacoes_*` em `time_records` e `frequencia_por_orgao` (ou justificar por que não cabem), e **simetrizar shadow×on** no `time_records`. Ação recomendada: abrir item rastreável (ex.: 29.9 ou chore de observabilidade) com dono e prazo; corrigir a declaração do `iteration_29.md`.

### 🟡 S2 — Travar o passo 4 (GI) do PORO com baseline explícito
A matriz não mata e o shadow report só mata **incidentalmente** (via `por_motivo`) a mutação do passo 4 do PORO; a suíte da 29.4 não cobre GI **inativo**. Risco: o **mesmo bug no twin SQL** (`FrequentadoresVisiveis#geridos_user_ids`) ficaria verde → furo de **segurança** (um GI inativo liberando um gerido). Adicionar um teste de baseline assertando `AutorizacaoFrequencia.new(gestor).motivo(gerido_inativo) == :negado`.

### 🟡 S3 — `frequencia_por_orgao`: celular "por orgão" não é o mesmo grão da visibilidade "por pessoa"
A tela é de **agregação por orgão**; o critério da matriz (por pessoa) não a cobre. Nenhum teste da 29.8 a exercita `:on` com ator não-global. Registrar como fora-de-escopo assumido ou cobrir.

### 🟠 D1 — Declaração de mutação do agente: "o PORO é coberto pela suíte da 29.4"
Ver item 5. A justificativa, como está, **não se sustenta** para o passo 4 (GI) — refutada por medição.

### 🟠 D2 — "→ 403" é interpretação, não o literal do critério
O critério diz "→ 403"; o app não produz 403. A interpretação é correta, mas o registro deve deixar explícito que o critério foi **reinterpretado** (filtragem + `can?`), para o PO decidir com clareza.

---

## 8. Elogios (🟢)

- 🟢 **G1 — Controles positivos sistemáticos:** todos os 5 negativos da matriz têm controle sem-flag no mesmo caminho — anti-degeneração aplicada de verdade (lição 33).
- 🟢 **G2 — Lição registrada com evidência real:** a lição "twin Ruby × SQL" foi escrita a partir de medição (mutação do scope mata 1F), e a revisão confirmou a tese parcialmente — inclusive descobrindo que há um furo espelhado (S2).
- 🟢 **G3 — Shadow report determinístico e assertado:** números fixos, sem aleatoriedade na lógica, e asserção (não só `puts`).

---

## 9. Ações corretivas

- [ ] (Não-bloqueante, 🟡 S1) Abrir item rastreável para estender `log_negacao` a `time_records` e `frequencia_por_orgao` + simetrizar shadow×on; corrigir a declaração do `iteration_29.md`.
- [ ] (Não-bloqueante, 🟡 S2) Adicionar baseline explícito do passo 4 (GI inativo) no PORO.
- [ ] (Não-bloqueante, 🟡 S3/🟠 D2) Registrar a reinterpretação do "→ 403" e o escopo de `frequencia_por_orgao`.

Nenhuma ação corretiva é pré-requisito para o commit.

---

## 10. Recomendação de commit

**Aprovado para commit** (`COMMIT_MODE=manual`), com **stage seletivo**:

```
git add api-ponto/app/models/frequencia_autorizacao_cascata.rb \
        api-ponto/app/controllers/concerns/frequencia_authorization.rb \
        api-ponto/app/controllers/admin/frequencia_controller.rb \
        api-ponto/app/controllers/admin/frequentadores_controller.rb \
        api-ponto/test/controllers/admin/frequencia_matriz_aceite_test.rb \
        api-ponto/test/models/frequencia_shadow_report_test.rb \
        api-ponto/test/controllers/admin/frequencia_cascata_controller_test.rb \
        api-ponto/test/models/frequencia_autorizacao_cascata_test.rb \
        docs/governance/lessons.md docs/progress/iteration_29.md
```
**Excluir:** `api-ponto/log/test.log`, `api-ponto/tmp/cache/bootsnap/load-path-cache`.
Sugestão semântica: `test: matriz de aceite da cascata + auditoria de negacao no modo on (Sprint 29, task 29.8)`.

---

## 11. Nota pós-revisão

Após o commit, o fechamento da rastreabilidade é **pré-requisito** para a próxima tarefa. Recomenda-se que o CTO registre a lição do **twin Ruby × SQL** como padrão do projeto (já há lição em `lessons.md`) e catalogue o débito S1 (observabilidade parcial do `:on`) com dono e prazo.

---

# 2ª RODADA — Re-review da correção do furo S4 (2026-10-02)

> **Revisor:** Code Reviewer (AI Workflow) · **Worktree:** `wt-29.8` @ `df57cf5` · `COMMIT_MODE=manual`
> **Motivo:** o furo 🟠 S1 da 1ª rodada (log do `:on` em 2 de 4 telas que negam) foi corrigido.
> **Veredito:** ✅ **APROVADO** — **0 Blockers** · 🟡 1 (residual) · 🟢 2 · paridade 4×4 confirmada.

## R1. Paridade 4×4 é REAL (não fachada) ✅
Instrumentação conferida no diff: `time_records` e `frequencia_por_orgao` agora **emitem** o evento `frequencia_autorizacao_cascata.negacao` sob `:on`.
- `time_records#index`: `observar_cascata_frequencia` (shadow) **+** `registrar_negacoes_frequencia(registros)` (`:on`), **antes** de `restringir_frequencia` (linhas 29/34/35). Ordem correta: loga o que FOI negado, depois restringe.
- `frequencia_por_orgao#index`: `observar_cascata_por_cpf(cpfs)` + `registrar_negacoes_por_cpf(cpfs)`, antes da interseção `cpfs &= frequentadores_visiveis_cpfs`.
- `parcial`/`relatorio_terceirizados`: confirmado que **não negam** — `@registros = []` é o comportamento real; as views só iteram `@registros` (nada) / não têm fonte de dado própria, e não há outra query de listagem. Logo não há barreira a auditar (logger ali seria log de fachada). **Fora por não negarem** ✅.

**Paridade confirmada: 4 telas negam (frequencia, frequentadores, time_records, frequencia_por_orgao) × 4 logam.**

## R2. `frequencia_por_orgao` — bounded e alvo correto ✅
- **Bounded:** `user_ids_ocultos_por_cpf` faz `User.where(cpf: negados).limit(LIMITE_SHADOW).pluck(:id)` → no máximo `LIMITE_SHADOW` (200). Não varre o universo.
- **Alvo correto:** derivado de `Array(cpfs) - frequentadores_visiveis_cpfs` — os CPFs do órgão **fora** dos visíveis, exatamente o que a interseção `cpfs &= frequentadores_visiveis_cpfs` remove. O alvo logado é o que a cascata oculta. ✅
- **Consistência de formato:** `cpfs_por_orgao` e `cpfs_frequentadores_visiveis` ambos fazem `pluck("pessoas.cpf")` da mesma tabela do espelho — mesma forma (sem máscara), o `-` de array é correto.
- **Nota (não-bloqueante):** quando o operador filtra por `params[:orgao]`, o log cobre só o(s) órgão(s) em tela; quando não filtra, são vários órgãos e o `LIMITE_SHADOW` capa em 200 (documentado via `LIMITE_SHADOW`).

## R3. Simetria shadow×on — asserção DISCRIMINANTE ✅
O teste "SIMETRIA shadow x on" em `time_records` roda os DOIS modos sobre os mesmos alvos e assere `shadow.size == negacao.size` **e** igualdade dos conjuntos de `alvo_id`. Não é degenerado:
- **Mutação M12** (comentar o on-log em `time_records`) → **2 failures** (a igualdade de contagens quebra) ✅
- **M13** (comentar o on-log em `frequencia_por_orgao`) → **1 failure** ✅
- **M14** (comentar o shadow-log em `frequencia_por_orgao`) → **1 failure** ✅

**Observação adversarial honesta:** a asserção de simetria compara **contagens/conjuntos**, não **motivos**. Se o PORO divergir do scope (ex.: passar a classificar como `:gestor_individual` um alvo oculto), a asserção permanece verde — mas isso é o débito 🟡 S2 (cobertura do PORO), já registrado. A simetria aqui cumpre o que promete (mesmos alvos, eventos distintos).

## R4. Nenhuma decisão de acesso mudou ✅
Verificado no diff (não no relato): as únicas linhas **removidas** de `app/` são a chamada antiga `log_shadow` (refatorada para `emitir`) e o `private` movido. Todo o resto é **adição** (2 chamadas de log + comentários). `restringir_frequencia`, `Ability`, migrations e auth intactos. Log é aditivo. ✅

## R5. Declaração do `iteration_29.md` corrigida ✅
A linha antes imprecisa (1ª rodada) agora diz explicitamente: **quais 4 telas logam o `:on`, quais 2 não logam e por quê** ("não negam; sem fonte de dado; logger seria log de fachada"), com a paridade **4 negam × 4 logam**. Corresponde ao código. ✅

## R6. Débito 🟡 S2 registrado com dono e gatilho binário ✅
O parágrafo "Débito 🟡 S2" está no `iteration_29.md`, com: **o quê** (baseline do passo 4/GI inativo no PORO **E** no twin SQL), **onde** (`FrequentadoresVisiveis#geridos_user_ids` e `AutorizacaoFrequencia#gestor_individual?`), **dono** (Sprint 30 ou chore de hardening), **gatilho binário** (existe teste que exercita o PORO com GI inativo assertando `:negado` **e** o twin SQL com o mesmo cenário, no baseline). Rastreável e correto. ✅

## R7. Qualidade ✅
- **RuboCop:** 0 offenses novas. As **10** de `time_records_controller` são **pré-existentes** — confirmei contra o HEAD (`git show HEAD:...` → mesmas 10 offenses). Nenhuma nas linhas novas da 2ª rodada (27-35 / 43-52).
- **Zeitwerk:** OK. **Suíte completa:** **1083/3789/1F+11E/0 skips** (baseline 1060/3663/1F+11E; **+23 runs, 0 novas**; as 12 são as pré-existentes).
- **Testes-alvo da 29.8:** **36/208/0F/0E**; shadow report segue **4 / {negado: 4} / div=0 / causas=2**.

## R8. Mutations que reproduzi (2ª rodada) — backup `/tmp/rev298b/`, restauração verificada por `diff` (3/3 idênticos, 0 resíduo)

| # | Mutação | Arquivo | Teste | Resultado |
|---|---|---|---|---|
| M12 | comentar `registrar_negacoes_frequencia(registros)` | `time_records_controller.rb` | cascata controller | **2F** ☠️ |
| M13 | comentar `registrar_negacoes_por_cpf(cpfs)` | `frequencia_por_orgao_controller.rb` | cascata controller | **1F** ☠️ |
| M14 | comentar `observar_cascata_por_cpf(cpfs)` | `frequencia_por_orgao_controller.rb` | cascata controller | **1F** ☠️ |

## R9. Pendências residuais (não-bloqueantes)
- 🟡 **S2** (residual da 1ª rodada) — baseline do passo 4/GI inativo no PORO E no twin SQL: **registrado no `iteration_29.md` com dono e gatilho binário** (ver R6). Mantido como débito aberto.
- 🟡 S3 (1ª rodada) — `frequencia_por_orgao` no grão por-pessoa da matriz: agora parcialmente coberto pelo teste de paridade shadow×on da tela; o grão agregado segue sem teste de listagem próprio. Aceito.
- 🟠 D1/D2 (1ª rodada) — declaração de mutação e reinterpretação do "→ 403": a declaração foi **corrigida** (agora aponta o débito S2); D2 segue como nota de registro.

## R10. Recomendação de commit (2ª rodada)
**Aprovado para commit** (`COMMIT_MODE=manual`), **stage seletivo** — 12 arquivos agora (2 controllers novos entraram):

```
git add api-ponto/app/models/frequencia_autorizacao_cascata.rb \
        api-ponto/app/controllers/concerns/frequencia_authorization.rb \
        api-ponto/app/controllers/admin/frequencia_controller.rb \
        api-ponto/app/controllers/admin/frequentadores_controller.rb \
        api-ponto/app/controllers/admin/time_records_controller.rb \
        api-ponto/app/controllers/admin/frequencia_por_orgao_controller.rb \
        api-ponto/app/controllers/admin/parcial_controller.rb \
        api-ponto/app/controllers/admin/relatorio_terceirizados_controller.rb \
        api-ponto/test/controllers/admin/frequencia_matriz_aceite_test.rb \
        api-ponto/test/models/frequencia_shadow_report_test.rb \
        api-ponto/test/controllers/admin/frequencia_cascata_controller_test.rb \
        api-ponto/test/models/frequencia_autorizacao_cascata_test.rb \
        docs/governance/lessons.md docs/progress/iteration_29.md \
        docs/quality/review_report_29_8.md
```
**Excluir:** `api-ponto/log/test.log`, `api-ponto/tmp/cache/bootsnap/load-path-cache`.
Sugestão semântica: `test: matriz de aceite da cascata + auditoria de negacao no modo on em 4 telas (Sprint 29, task 29.8)`.

**Veredito da 2ª rodada: ✅ APROVADO — 0 Blockers. A entrega técnica está liberada para commit.**
