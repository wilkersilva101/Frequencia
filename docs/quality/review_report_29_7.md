# Relatório de Revisão — Tarefa 29.7 (Integração na `Ability` e controllers de frequência, atrás de flag)

> **Revisor:** Code Reviewer (AI Workflow) · **Data:** 2026-10-02
> **Worktree:** `/home/davi.queiroz/Área de trabalho/workspace_integração/wt-29.7` · **Branch:** `feature/demanda-29-7-ability-frequencia` @ `16c1c9a`
> **Modo:** `TASK_MODE=STANDARD`, `COMMIT_MODE=manual`, `MEMORY_MODE=classic`, `SUGGESTION_LEVEL=1`
> **Veredito:** ✅ **APROVADO** — **0 Blockers** · 🟡 1 · 🟠 3 · 🟢 3
> **Critério da 29.7 (7 itens):** 7/7 verificados; nenhuma fuga de autorização encontrada.

---

## 1. Metadados

| Item | Valor |
|---|---|
| Branch origem → destino | `feature/demanda-29-7-ability-frequencia` → `integration/sprint-29` |
| Commit base | `16c1c9a` |
| Arquivos novos (5) | `app/models/frequencia_autorizacao_cascata.rb`, `app/controllers/concerns/frequencia_authorization.rb`, `test/models/frequencia_autorizacao_cascata_test.rb`, `test/models/ability_cascata_test.rb`, `test/controllers/admin/frequencia_cascata_controller_test.rb` |
| Arquivos modificados (8, de código/docs) | `app/models/ability.rb`, `app/models/pessoas/vinculo.rb`, 6 controllers em `app/controllers/admin/`, `docs/governance/lessons.md`, `docs/progress/iteration_29.md` |
| Artefatos a excluir do stage | `api-ponto/log/test.log`, `api-ponto/tmp/cache/bootsnap/load-path-cache` (gitignored/runtime) |
| Tarefa revisada | 29.7 (depende de 29.4/29.5/29.6, D2, D3) |

**Nota de escopo:** `test/support/class_method_stub_helper.rb` **não** é arquivo desta entrega — é rastreado desde `43b7d84` (`fix(test): torna nao-destrutivos os stubs de metodo de classe`). Confirmado via `git ls-files`.

---

## 2. Verificação independente (medida nesta revisão)

| Verificação | Comando | Resultado |
|---|---|---|
| Testes novos | `bin/rails test` (3 arquivos) | **22 runs / 120 asserts / 0F / 0E** ✅ |
| Zeitwerk | `bin/rails zeitwerk:check` | `All is good!` ✅ |
| Flag default | `grep FREQUENCIA_AUTORIZACAO_CASCATA config/ .env*` | ausente → `:off` ✅ |
| Baseline flag OFF (`ability_test.rb`) | `bin/rails test test/models/ability_test.rb` | **13/82/0/0** ✅ idêntico ao HEAD |
| Baseline flag OFF (`controllers/admin`) | `bin/rails test test/controllers/admin` | **182/1025/0F/0E** ✅ sem regressão |
| Módulos afetados (`ability`, `intervencao_frequencia`, `frequentadores_visiveis`, `autorizacao_frequencia`, `sidebar`) | — | **104/408/0F/0E** ✅ |
| Matriz de autorização | `authorization_matrix_test.rb` | **6/140/0/0** — OFF e ON **idênticos** ✅ |
| `Presenca::*` tocados? | `git status`, `git diff --name-only` | **nenhum** ✅ |
| RuboCop | ver §6 | 🟠 4 offenses **em linhas novas** de `ability.rb` |

---

## 3. Resultado item a item (o que foi pedido)

### Item 1 — Flag OFF = comportamento IDÊNTICO ao HEAD ✅
- `FrequenciaAutorizacaoCascata.modo` → `:off` quando a env está ausente/vazia/desconhecida (`else :off`), e a env **não é setada** por `config/`/`.env*`/CI. Logo a suíte roda em `:off`.
- Com `:off`, `ligada?` é falso → `deny_frequencia_baseline!` **não roda**, `grant_leitura_frequencia` **não roda**, e `grant_gestao_frequencia` cai exatamente no `else`: `can :manage, TimeRecord` + `can :manage, IntervencaoFrequencia` — byte a byte o que o HEAD fazia.
- Nos controllers, o concern é no-op em `:off`/`:shadow` (`restringir_frequencia` devolve a relação intacta; `observar_*` retornam cedo).
- **Medição:** `ability_test.rb` 13/82/0/0 e `controllers/admin` 182/1025/0F/0E — sem mudança. ✅

### Item 2 — D2 correta ✅
- `RECURSOS_FREQUENCIA = [TimeRecord, CalculoDiario, RegistroMensalFrequencia, IntervencaoFrequencia]`. Com `:on`, `deny_frequencia_baseline!` emite `cannot :read, recurso` para **exatamente** esses 4; as demais telas seguem com `can :read, :all`.
- Probe: com `:on`, `can?(:read, :all)=true`, `can?(:read, User/EstacaoPonto/RelatorioFrequenciaFinal)=true`, `can?(:read, TimeRecord)=true` (classe, necessário p/ sidebar/`load_and_authorize`), `can?(:read, TR de oculto)=false`. ✅
- **Admin preservado:** `deny_frequencia_baseline!` roda **antes** do `can :manage, :all` do admin; probe comportamental confirma que com `can :manage, TimeRecord` também bloqueado a leitura do oculto continua negada → `manage` **inclui `read`**, e o `manage :all` do admin, sendo mais recente, sobrepõe o `cannot`. `can?(:read, TR oculto)` do admin = **true**. ✅
- **Passo 2 (`visualiza_frequentadores`) NÃO restringido:** `deny` só toca os 4 recursos; a role não é tocada (não há `cannot` sobre ela). ✅
- **Contraste deliberado (correto)** com `cannot :manage` explorado como contra-probe: como `manage` inclui `read`, bloquear `manage` bastaria *hoje*; a escolha por `read` é mais precisa (lê a intenção: "tira a LEITURA do baseline") e à prova de um `can :update, TimeRecord` futuro. ✅

### Item 3 — Limite do `accessible_by` ✅ (alegação VERDADEIRA)
- Probe real (`bin/rails runner`, `:on`): `TimeRecord.accessible_by(ability)` → **`CanCan::Error: The accessible_by call cannot be used with a block 'can' definition`**. Reproduzido. ✅
- **Contorno cobre o critério:** as listagens (`frequencia`, `time_records`, `frequencia_por_orgao`, `frequentadores`) filtram por `frequentadores_visiveis` (`cpfs`/`user_ids`) — não usam `accessible_by`.
- **Grep repo-wide:** **nenhum** `accessible_by` em `app/`/`lib/` (só comentários e o `_context`). **Nenhum** ponto de código vai explodir com `:on`. ✅
- Nota de design (não-bloqueante): como `can?(:read, Classe)` é `true` por design, o `deny_frequencia_baseline!` **não discrimina em check por classe**. Sua única função efetiva é a **regra por instância** — confirmado por mutação (M1 mata 2 testes). O benefício de manter o `deny` é semântico/documental (fail-safe se um `accessible_by` surgir). Aceito.

### Item 4 — Fuga de autorização (adversarial) ✅ NENHUMA ENCONTRADA
Varredura de todas as superfícies de acesso a frequência:
- **Rotas:** `resources :time_records, only: [:index]`, `frequencia`/`parcial`/`frequencia_por_orgao`/`relatorio_terceirizados` são só `index` GET. **Não existe `show`/`create`/`update`/`destroy`/`deferir`/`indeferir` para nenhum recurso de frequência.** Os únicos `find`/`params[:id]` são em `frequentadores#reimportar_dados_pessoa` (gated `authorize! :manage, User` = admin only) e em `users#edit`. ✅
- **Não há `load_and_authorize_resource` sobre recurso de frequência** (só `estacao`/`regime`/`versao`/`user`), então não há carregamento por id → `authorize!` por instância que pudesse vazar. ✅
- **`frequencia#index`:** `@registros` restringido **antes** dos filtros `data`/`frequentador`/`estacao`; os filtros são `.merge`/`.joins` sobre a relação já restrita → restrição persistente. ✅
- **`time_records#index`:** restrição + `where(user_id: current_user.id)` para não-admin; o ramo de busca por nome (`params[:usuario]`, `cpfs_por_nome`) só é alcançado por **admin** (passo 2, vê tudo por D1) — sem vazamento. ✅
- **`frequencia_por_orgao#index`:** `cpfs` do órgão sofre `&= frequentadores_visiveis_cpfs` para não-global; `presencas`, `trabalhado` (`CalculoDiario`) e `ausencias` (`AfastamentoCache`) derivam todos de `cpfs`/`user_ids` já restritos. ✅
- **`frequentadores#index`:** `incluir_cpfs_com_cascata` faz a **interseção** `exigidos & visiveis` (não substituição) — correto; `excluir_cpfs` é refinamento (restrição ⊆). ✅
- **Views:** único uso de `can?` em views é o filtro da sidebar (`shared/_sidebar.html.erb`) por **classe** — não decide dados. Sem `accessible_by` em view. ✅
- **Fail-closed:** `visivel_user_id?` com `user_id` nulo → `false`; scope sem insumos → `"1 = 0"`; `pode_ver?` com alvo nulo → `:negado`. ✅

### Item 5 — Shadow não nega; `reorder(nil)`/`distinct` corretos ✅
- `log_shadow` retorna cedo se `!shadow?`; nível `info`; não altera a resposta. Mutação M7 (loga sempre) mata 1 teste. ✅
- `observar_cascata_frequencia` usa `.reorder(nil).distinct.limit(200).pluck(:user_id)` — o `reorder(nil)` remove o `ORDER BY punched_at` herdado, evitando o `PG::InvalidColumnReference` do `SELECT DISTINCT`. Correto. ✅
- **Contrato de alvo do shadow:** `registrar_shadow` passa um `User` a `AutorizacaoFrequencia#motivo` — **suportado** pelo PORO (`alvo_user_id` detecta `User`; `alvo_pessoa` resolve via `resolver_pessoa_por_user`). Sem `TypeError`. ✅

### Item 6 — `Presenca::*` intocados ✅
Nenhum arquivo em `app/controllers/presenca/`, `app/views/presenca/` ou `config/routes.rb` (rotas `Presenca::*`) foi alterado. Mudança aditiva; `Ability` não mudou com `:off`. ✅

### Item 7 — Testes degenerados ✅ (os 2 corrigidos validados)
- Reproduzi **8 mutações**, todas **mortas** (detalhe em §5). Em particular, a anti-degeneração do stub de `frequentadores_ativos` (que **honra `incluir_cpfs`**) é discriminadora: M8 (substituição em vez de interseção) mata o teste, provando que o teste não passaria "por outro filtro".
- O teste de `frequencia_por_orgao` possui **CONTROLE explícito** (sem flag = 1 presença; com flag = 0) — não degenera.
- 🟡 Apontamento leve: o teste "time_records: sob a flag, a busca do admin continua resolvendo qualquer frequentador" assere presença de um heading que seria exibido **mesmo sem a flag** — o nome sugere que discrimina `:on`, mas não isola a variável. É doc/integração, não crítica; ver S1.

### Item 8 — Qualidade (RuboCop / Zeitwerk / arquitetura)
- **Zeitwerk:** OK.
- **Arquitetura preservada:** POROs de consulta (`FrequenciaAutorizacaoCascata` = leitura de flag + log; concern = cola de controller), **nenhuma migration**, **nenhum auth/Devise** tocado, `Ability` mantém a estrutura. Aditivo. ✅
- **RuboCop:** ver §6 (🟠).

---

## 4. Blockers (🔴)

**Nenhum.** Não foi encontrada fuga de autorização, quebra de baseline com `:off`, nem regressão na suíte existente.

---

## 5. Mutações que EU reproduzi (backup + restauração verificada)

Todas aplicadas no worktree com backup em `/tmp/rev_backup/` e **restauração confirmada por `diff` (5/5 arquivos idênticos, zero `MUTATED` residual, `git diff --stat` inalterado)**.

| # | Mutação | Arquivo | Teste | Resultado |
|---|---|---|---|---|
| M1 | remover `deny_frequencia_baseline! if ligada?` | `ability.rb` | `ability_cascata_test` | **2 failures** ☠️ |
| M2 | gestor com escopo → gerência irrestrita (`if false`) | `ability.rb` | `ability_cascata_test` | **1 failure** ☠️ |
| M3 | `visivel_user_id?` blank → `true` (fail-open) | `ability.rb` | `ability_cascata_test` | **1 failure** ☠️ |
| M4 | `restringir_frequencia` → no-op | concern | `frequencia_cascata_controller_test` | **1 failure** ☠️ |
| M5 | `ligada?` sempre `false` | `frequencia_autorizacao_cascata.rb` | ability + controller | **7 failures** ☠️ |
| M6 | `frequencia_por_orgao` ignora a flag | `frequencia_por_orgao_controller.rb` | controller | **1 failure** ☠️ |
| M7 | `log_shadow` loga sempre | `frequencia_autorizacao_cascata.rb` | flag | **1 failure** ☠️ |
| M8 | `incluir_cpfs_com_cascata` substitui em vez de intersectar | `frequentadores_controller.rb` | controller | **1 failure** ☠️ |

**Mutações não executadas (declaro):** as do agente "shadow loga sempre", "incluir_cpfs ignora visíveis", "frequencia_por_orgao ignora flag", "visao_global? sempre true" — reproduzi as equivalentes M6/M7/M8; a de `visao_global?` não foi reproduzida isoladamente (custaria tocar o concern; coberta indiretamente por M4).

---

## 6. Sugestões

### 🟡 S1 — Teste `time_records` (admin) não isola a variável
`test/controllers/admin/frequencia_cascata_controller_test.rb:132-159` assere que o heading "Registro Mensal" aparece, mas esse heading seria exibido **com ou sem** a flag (não depende de `:on`). O nome do teste sugere cobertura da flag. Sugestão: renomear para refletir "admin preserva visão global" (documentação de comportamento) ou adicionar asserção que distinga `:on` de `:off` para o alvo oculto.

### 🟠 S2 — RuboCop: 4 offenses em LINHAS NOVAS de `ability.rb`
`ability.rb:163` e `:167` (`Layout/SpaceInsideArrayLiteralBrackets`) — **linhas adicionadas** por esta PR (hunk `@@ -77,0 +113,80 @@`). O HEAD tinha **0 offenses** nesse arquivo (verificado via `git show HEAD:...ability.rb` → `no offenses detected`).
A alegação do relatório do Code Specialist ("RuboCop 0 offenses nos arquivos novos") é **imprecisa para `ability.rb`**: os arquivos **novos** (untracked) têm 0, mas o **modificado** introduz 4. Correção trivial (espaço dentro dos colchetes de `can [ ... ]`). Não é blocker (a dívida de 77 offenses é rastreada em `chore/limpeza-rubocop-77`), mas o registro deve ser corrigido para não subestimar a dívida.

### 🟠 S3 — Usuário não-admin SEM CPF vê zero registros sob `:on`
Com `:on`, para um `User` autenticado **sem CPF** (não-admin), o scope devolve `"1 = 0"` → `frequentadores_visiveis_user_ids = []` → `restringir_frequencia` = `where(user_id: [])` → **nada**. No `time_records`, isso também apaga os **próprios** registros (o `where(user_id: current_user.id)` subsequente não os recupera). É *fail-closed* (não vaza), mas é regressão funcional para o caso "conta local sem CPF". População provável: admins (curto-circuitados) e contas locais legadas — e o próprio teste da PR documenta que o login com CPF passa pelo Pessoas. Recomenda-se cobrir esse cenário na **matriz da 29.8** (usuário sem vínculo/CPF → 403) e decidir explicitamente se o comportamento é o desejado. Hoje a suíte não o cobre.

### 🟠 S4 — Observabilidade do `:on` ausente (só o shadow loga)
No modo `:on` (negação real), não há log da negação no controller (o `CanCan::AccessDenied` só gera redirect). O critério da 29.7 só exige log no shadow (cumprido). Fica registrado como débito para a 29.8/observabilidade, alinhado ao 🟠2 do review da 29.6.

---

## 7. Elogios (🟢)

- 🟢 **G1 — Isolamento bem desenhado:** a flag é lida a cada chamada (não memoizada no boot), permitindo exercitar `:off`/`:shadow`/`:on` nos testes sem reiniciar o processo.
- 🟢 **G2 — Restauração de estado nos testes:** `com_flag`/`with_logger` usam `ensure` e restauram o valor anterior — exatamente a lição registrada sobre contaminação de estado global entre arquivos do mesmo worker.
- 🟢 **G3 — Honestidade documental:** os comentários registram o limite medido do `accessible_by` e o contrato de fuso/cross-database (29.6), sem esconder a dívida. A lição nova (`Proc`/`define_singleton_method` rebindando `self`) foi registrada em `lessons.md` com evidência.

---

## 8. Ações corretivas

- [ ] (Opcional, não-bloqueante) Corrigir o registro de RuboCop no `iteration_29.md` para `4 offenses novas em ability.rb` (🟠 S2) — ou aplicar o autocorrect.
- [ ] (Opcional, não-bloqueante) Renomear/ajustar o teste de `time_records` (🟡 S1).
- [ ] (Recomendado p/ 29.8) Incluir o cenário de usuário sem CPF na matriz de aceite (🟠 S3).

Nenhuma ação corretiva é pré-requisito para o commit.

---

## 9. Recomendação de commit

**Aprovado para commit** (`COMMIT_MODE=manual`), com **stage seletivo**:

```
git add api-ponto/app/models/frequencia_autorizacao_cascata.rb \
        api-ponto/app/controllers/concerns/frequencia_authorization.rb \
        api-ponto/app/models/ability.rb \
        api-ponto/app/models/pessoas/vinculo.rb \
        api-ponto/app/controllers/admin/frequencia_controller.rb \
        api-ponto/app/controllers/admin/frequencia_por_orgao_controller.rb \
        api-ponto/app/controllers/admin/frequentadores_controller.rb \
        api-ponto/app/controllers/admin/parcial_controller.rb \
        api-ponto/app/controllers/admin/relatorio_terceirizados_controller.rb \
        api-ponto/app/controllers/admin/time_records_controller.rb \
        api-ponto/test/models/frequencia_autorizacao_cascata_test.rb \
        api-ponto/test/models/ability_cascata_test.rb \
        api-ponto/test/controllers/admin/frequencia_cascata_controller_test.rb \
        docs/governance/lessons.md docs/progress/iteration_29.md
```
**Excluir:** `api-ponto/log/test.log`, `api-ponto/tmp/cache/bootsnap/load-path-cache`.
Sugestão semântica: `feat: integra cascata de autorizacao de frequencia na Ability e controllers (Sprint 29, task 29.7)`.
