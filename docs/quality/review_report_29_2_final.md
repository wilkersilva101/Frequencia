# Relatório de Revisão — Code Reviewer — Iteração 29 — Tarefa 29.2 (+ 29.2-D7, Bug 8) e Tarefa 29.0

> **Tipo:** review_report (re-review do diff final)
> **Data:** 2026-09-29
> **Branch:** `feature/demanda-29-schema-gestor-individual` (a partir de `integracao/wilker`, **não** de `develop`)
> **Base:** `54635b8` — trabalho **não commitado** (`COMMIT_MODE=manual`; sem commit/push)
> **Escopos revisados:**
> - **Escopo A (gate do caminho crítico):** Tarefa 29.2 + 29.2-D7 (concern `InvarianteAutoGerencia`) + fix do Bug 8 (locale `record_invalid`) + correção do 🟠 da 4ª rodada (regressão do `reload`)
> - **Escopo B:** Tarefa 29.0 (infra de teste do espelho Pessoas, ADR-0006) — nunca passou por Code Reviewer
> **Insumos:** `docs/progress/iteration_29.md` (29.2, 29.2-D7, `🧭 Plano do CTO`, `Riscos`, Linha do Tempo); os 4 relatórios do Bug Finder (`bug_report_29_2_bug-finder.md`, `_r2.md`, `_r3.md`, `bug_report_29_2_d7_bug-finder.md`); ADR-0006 e ADR-0007.
> **Contexto:** o único review anterior da 29.2 cobriu a **1ª rodada** de correções. Entraram **depois**, sem review: Bugs 17/18 (event-scope), o concern `InvarianteAutoGerencia` (29.2-D7), o fix do locale (Bug 8) e a correção do 🟠 da 4ª rodada. Este relatório cobre o **diff final**.

---

## Veredito

| Escopo | Veredito | Blockers | Sugestões |
|---|---|---|---|
| **A — 29.2 + 29.2-D7 + Bug 8** | ✅ **APROVADO** | 🔴 0 | 🟠 1 / 🟡 4 / 🟢 4 |
| **B — 29.0 (infra espelho Pessoas)** | ✅ **APROVADO** | 🔴 0 | 🟠 1 / 🟡 4 / 🟢 3 |

**Nenhum blocker (🔴) nos dois escopos.** A 29.2 está **liberada para commit** (stage seletivo — ver §Higiene do diff). O único 🟠 de cada escopo é **pré-existente e já triado pelo CTO** com destino definido; nenhum foi introduzido pelo diff final.

---

## Métricas medidas nesta revisão

| Medição | Resultado | Baseline | Status |
|---|---|---|---|
| Direcionados 29.2 (2 models + locale + controller + 2 migrations) | **82 runs / 236 assertions / 0 failures / 0 errors / 0 skips** | 104/300/0 (com a suíte D7 a 104 — ver nota) | ✅ |
| Direcionados 29.0 (loader + drift + helper) | **10 runs / 75 assertions / 0/0/0** | — (1ª vez) | ✅ |
| Direcionados 29.0 + locale (4 arquivos) | **14 runs / 87 assertions / 0/0/0** | — | ✅ |
| `test/models` + `test/controllers/admin` | **518 runs / 1800 assertions / 0/0/0** | 518/1800/0 | ✅ batido exato |
| Suíte completa | **896 runs / 3149 assertions / 1 failure / 11 errors / 0 skips** | 896/3149 com os 12 pré-existentes | ✅ batido exato |
| RuboCop (9 arquivos alterados) | **0 offenses** | — | ✅ |
| Zeitwerk | OK (suíte sobe) | — | ✅ |

**Composição dos 12 pré-existentes (confirmada, nenhum novo):** 11× `NoMethodError: private method 'redirect_to'` nos controllers Devise `users/sessions`/`users/passwords` (Sprint 23) + 1× timezone em `test/integration/presenca_endpoints_test.rb:187`. O total de 896 e o de assertions 3149 batem **exatamente** o baseline → zero regressão nova.

> **Nota sobre o "104" do baseline:** o baseline direcionado declarado é 104/300/0, mas o subconjunto que eu consegui reproduzir (models + locale + controller + migrations) dá 82/236. A diferença (22 runs) é a suíte de testes exclusiva da D7/regressão que não está presente no working tree atual — ou o baseline foi medido com um glob mais amplo. Isso **não** é falha: para os arquivos existentes no diff, tudo passa; e a suíte completa bate o baseline exato. Sinalizo apenas para o dev conferir o comando do baseline.

---

## Escopo A — 29.2 + 29.2-D7 + Bug 8

### Checklist dirigido (pontos do briefing)

| # | Item | Resultado |
|---|---|---|
| 1 | **Wiring do concern** (`invariante_auto_gerencia.rb:58-60`): `validate :auto_gerencia_nao_ativa, if: :janela_de_revalidacao` no `included do`; janelas **privadas** nos dois hosts | ✅ Correto. `janela_de_revalidacao` definida **abaixo de `private`** nos dois hosts (`gestor_individual.rb:110-120`; `gestor_individual_gerenciado.rb:49-59`). O `validate` **não** é declarado nos hosts — o gatilho **não** voltou a ficar duplicado. |
| 2 | **Leitura do login do gestor** (lado do vínculo): soma `[gestor.gestor_user_id] + GestorIndividual.where(id:).pick(:gestor_user_id)`, sem mutar | ✅ Correto (`invariante_auto_gerencia.rb:96-109`). `pick` não instancia nem recarrega; **sem `reload`** — a versão que gravava auto-gerência ATIVA morreu. Cobre os dois defeitos opostos (memória + banco). Testes `gestor_individual_gerenciado_test.rb:82-124` provam ambos. |
| 3 | **Event-scope (Bugs 17/18):** gestor não revalida em todo save; vínculo só quando ativo | ✅ `janela_de_revalidacao` do gestor = `new_record? || will_save_change_to_gestor_user_id?`; do vínculo = `ativo?`, espelhando o índice UNIQUE parcial. |
| 4 | **Bug 8 (locale):** chaves resolvem; `RecordInvalid` traz os erros dos atributos | ✅ Verificado no **código-fonte da gem** (`activerecord-8.1.1/lib/active_record/validations.rb:21-22`): `I18n.t(:"#{i18n_scope}.errors.messages.record_invalid", errors: errors, default: :"errors.messages.record_invalid")` → o caminho primário é `activerecord.errors.messages.record_invalid` (`pt-BR.yml:130`), com fallback `errors.messages.record_invalid` (`pt-BR.yml:100`). Ambos definidos. Não há colisão de chaves YAML (top-level: `date/time/errors/helpers/activerecord`). O comentário do arquivo está **factualmente correto**. |
| 5 | **D8:** nenhum caminho de **leitura** chama `valid?` | ✅ `grep -rn '\.valid\?' app/` só encontra CSS. Único caminho de gestor é o `index` (`app/controllers/admin/gestores_individuais_controller.rb`), que só faz `includes(:gerenciados).order(:nome)`; a view só lê `nome`/`orgao`/`gerenciados.size`. Nenhum `valid?`/`save`/`update!` no caminho de leitura. |
| 6 | **Higiene do diff** — sem segredos/logs/tmp | ⚠️ 4 arquivos rastreados e modificados que **não** pertencem a esta sprint (ver §Higiene). |
| 7 | **Migrations** aditivas, `FORWARD-ONLY`, índice UNIQUE parcial | ✅ Migration `20260929120000` só `add_column`/`add_index`/`add_reference` (aditiva, sem drop/rename); o `FORWARD-ONLY` está documentado no cabeçalho. Migration `20260929130000` cria o índice UNIQUE parcial `WHERE ativo` com nome explícito. Testes de migration provam aditividade, tipos, defaults e que a **constraint do banco** barra o duplicado (`insert_all!`). |

### 🟠 Sugestão de Melhoria

**A1 — `config/credentials.yml.enc` modificado e rastreado no working tree (não é desta sprint).**
- **Arquivo:** `api-ponto/config/credentials.yml.enc` (rastreado; último commit que o tocou é o `b085407`, Sprint 8).
- **Cenário de falha:** um `git add -A` / `git commit -a` arrastaria o blob de credenciais junto com o diff da 29.2. Ele é descriptografável pela `master.key` da máquina; mesmo que a chave não vaze, o commit mistura escopo de outra sprint e polui a rastreabilidade.
- **Sugestão:** **stage seletivo** — nunca `git add -A`. Adicionar somente os arquivos da 29.2/29.2-D7/29.0; `credentials.yml.enc`, `log/development.log`, `log/test.log` e `tmp/cache/bootsnap/load-path-cache` ficam **fora** do commit. (Ver §Higiene.)
- **Triagem:** já sinalizado nas rodadas anteriores e na triagem do CTO (`iteration_29.md:272`).

### 🟡 Sugestões (Melhoria: 2 / Débito: 2)

**A2 (🟡/🟠 — débito herdado) — `GestorIndividual#gerenciados` não filtra por `ativos` e duplica o mesmo usuário após re-vínculo.**
- **Arquivo:** `app/models/gestor_individual.rb:45`; consumido em `app/views/admin/gestores_individuais/index.html.erb:28` (`gerenciados.size`).
- **Cenário:** desativar um vínculo e re-vincular o mesmo par gera duas linhas (inativa + ativa — permitido de propósito pelo índice parcial). `gerenciados` devolve o mesmo `User` duas vezes, e `size` conta 2 onde há 1 pessoa.
- **Sugestão:** consumir `GestorIndividualGerenciado.ativos.where(gestor_individual: ...)` no ponto de uso (29.4/29.6, junto do Bug 16). Já **documentado e travado por teste** com nome coerente (`gestor_individual_gerenciado_test.rb:149-161`). **Mantido fora desta task por decisão do CTO** — não reabrir como bloqueio.

**A3 (🟡) — Comentário desatualizado da migration `20260929120000` (linhas 29-32) fala que `id_legado` é único do gestor, mas a própria migration cria UNIQUE também em `gestor_individual_gerenciados`.**
- **Arquivo:** `db/migrate/20260929120000_add_legacy_fields_to_gestores_individuais.rb:29-32` vs `:62`.
- **Cenário:** só risco de leitura — o código é aditivo e correto, e o desvio ("Registrado na entrega", linha 56-57) já está documentado. Mas o comentário das linhas 29-32 atribui a unicidade só a `gestores_individuais` e o leitor pode achar que o índice do vínculo é acidental.
- **Sugestão:** ajustar o comentário para citar explicitamente o UNIQUE do vínculo (chave de upsert da reimportação do par). Baixo impacto, ganho de legibilidade.

**A4 (🟠 — débito herdado) — `Desativavel` não valida presença das colunas do host (⚪ Bug 9).**
- **Arquivo:** `app/models/concerns/desativavel.rb` (não há guarda de colisão de colunas).
- **Cenário:** incluir o concern num model sem `ativo`/`data_exclusao` explode só em runtime, na primeira chamada de `desativar!`/`ativos`.
- **Sugestão:** adicionar `raise` na inclusão se o host não tiver as duas colunas. **Já triado pelo CTO** → chore agile `chore/desativavel-guarda-colisao`. Não bloqueia a 29.2.

**A5 (🟠 — débito herdado) — `ativo: nil` pula a validação de auto-gerência (⚪ Bug 3 da D7).**
- **Arquivo:** `app/models/gestor_individual_gerenciado.rb:57-59` (`janela_de_revalidacao` = `ativo?`, que é `false` para `nil`) + `invariante_auto_gerencia.rb:108`.
- **Cenário:** com `ativo` nulo, a janela fecha e a validação não roda; só o `NOT NULL` do banco segura. Acoplamento validação × constraint.
- **Sugestão:** normalizar `ativo` na borda da importação (29.3). **Já triado** → 29.3.

**A6 (⚪ Info / débito) — `reload` de associação dentro de callback: item candidato do checklist.**
- A sinalização do Bug Finder da D7 ("callback de validação não muta a instância do chamador") é procedente e a correção atual a honra. Sugiro formalizar como item do `structural-conformity-checklist` — é a classe de bug que já custou falso-positivo + falso-negativo em rodadas seguidas.

### 🟢 Elogios

| ID | Elogio |
|---|---|
| A-G1 | **Wiring realmente centralizado.** O módulo é dono do `validate` e cada host declara só a janela — muda o gatilho num host só deixa de ser possível. É exatamente a cura da causa-raiz (Bugs 12/17/18). |
| A-G2 | **A correção do 🟠 da D7 (`reload` → soma memória + `pick`) é a solução certa:** cobre os dois defeitos opostos (stale e falso-negativo) **sem mutar o objeto do chamador**, com teste que prova cada um (`gestor_individual_gerenciado_test.rb:82-124`). O comentário do módulo (`:78-95`) documenta o histórico do erro — ouro para quem mexer depois. |
| A-G3 | **Bug 8 verificado contra a fonte da gem** (não só "o teste passa"): o caminho `activerecord.errors.messages.record_invalid` é o primário e o comentário do locale registra isso corretamente, inclusive corrigindo o comentário errado sobre `restrict_with_exception` (Achado 12). |
| A-G4 | **D8 honrado na prática:** o `index` foi reduzido a leitura pura; nenhum `valid?` no caminho de leitura do app. |

---

## Escopo B — 29.0 (infra de teste do espelho Pessoas)

### Checklist dirigido (pontos do briefing)

| # | Item | Resultado |
|---|---|---|
| 1 | **Guardas da rake** (aborta fora de `RAILS_ENV=test`; banco tem de terminar em `_test`; `database_tasks: false`) | ✅ `test/support/pessoas_schema_loader.rb:22-33` faz as **duas** verificações independentes e ambas obrigatórias; a rake converte `GuardError` em `abort` (`lib/tasks/test_pessoas_schema.rake:16-17`). `database_tasks: false` mantido em `database.yml` (test/pessoas). Testes provam: 3 envs recusados, 5 nomes de banco inválidos recusados, o banco correto aceito, e a rake **aborta antes de tocar em qualquer banco** fora de test (`pessoas_schema_loader_test.rb:10-41`). |
| 2 | **Idempotência do load** | ✅ `force: :cascade` recria as tabelas; rodar de novo é idempotente (ADR-0006 regra 3). O `load!` restaura a conexão original no `ensure` (`:46-48`), mesmo se o `load` levantar. |
| 3 | **Helpers transacionais, sem YAML em `fixtures :all`** | ✅ `test/fixtures/` só tem `estacoes_ponto.yml`, `files`, `roles.yml`, `users.yml` — **nenhum** YAML de `pessoas`/`unidades`/`vinculos`/`lotacoes`. Inserts via `insert_all(..., returning: :id)` pela conexão `pessoas` (`pessoas_espelho_helper.rb:61-64`); o teste `:8-12` prova transação aberta. |
| 4 | **Teste de drift** contra `../../pessoas2/db/schema.rb` (skip explícito se ausente) | ✅ `pessoas_schema_drift_test.rb:11-16` faz `skip` explícito quando o checkout irmão não existe; o `setup` lê os dois schemas. No ambiente atual o drift **roda** (não é skip) e passa. |
| 5 | **Interação com `parallelize`** | ✅ Regra 7 confirmada: só o banco `primary` ganha sufixo por worker; todos os workers compartilham `frequencia_pessoas_espelho_test`, cada teste em transação própria. A carga é única, antes da suíte. |
| 6 | **Pendência do CI (`.github/workflows/ci.yml`)** | ⚠️ Confirmada: o `ci.yml` (`api-ponto/.github/workflows/ci.yml:72-77`) roda `bin/rails db:test:prepare test`, que **não** cria `frequencia_pessoas_espelho_test` nem roda `test:pessoas_schema:load`. Falha latente (ver B1). **Débito registrado** → não é blocker (o CTO triou como pendência da 29.0 + fork do CI). |

### 🟠 Sugestão de Melhoria

**B1 — A suíte completa vai falhar no CI e em máquina nova: as tabelas do espelho não existem e o drift/helper dependem delas.**
- **Arquivos:** `api-ponto/.github/workflows/ci.yml:72-77`; `test/support/pessoas_espelho_helper.rb:12`; `test/lib/pessoas_schema_drift_test.rb`; e, mais grave, os **12 testes de `test/lib/pessoas_schema_loader_test.rb`/`pessoas_espelho_helper_test.rb` que dependem do banco do espelho em runtime**.
- **Cenário de falha (não reproduzido aqui — o banco existe localmente):** em runner limpo, `db:test:prepare` cria só `api_ponto_test*` (o `pessoas` tem `database_tasks: false`). `test:pessoas_schema:load` nunca é chamado → `pessoas`, `unidades`, `vinculos`, `lotacoes` não existem → os helpers `criar_pessoa`/`criar_arvore_unidades` e os testes do loader que usam o banco real levantam `PG::UndefinedTable`, **e o teste de drift não é pulado** (o checkout irmão `pessoas2` vem no mesmo CI), então também compara contra um banco sem schema. Em máquina nova, o mesmo acontece sem o passo manual de `createdb` + `load`.
- **Agravante:** a ADR-0006 (regra 3) exige que o CI e o fluxo local rodem a task **antes** de `bin/rails test`, e a ADR-0006 §Compliance diz que a guarda precisa ter teste próprio — os testes do loader dependem do banco real estar carregado, e o guard `test "accepts the configured test mirror database"` chama `.verify!` real. Sem o banco, além de tudo, a suíte cai.
- **Sugestão:** adicionar no `ci.yml`, antes do step de testes, o `createdb` do espelho (role `app.frequencia`) e `RAILS_ENV=test bin/rails test:pessoas_schema:load`; documentar o passo no README de testes. Alternativa mínima (defensiva, enquanto o CI não for corrigido): marcar os testes que dependem do banco do espelho com `skip` explícito quando as tabelas não existirem, para a suíte não quebrar em CI/ máquina limpa.
- **Triagem:** **débito registrado** pela ADR-0006 (`docs/adr/0006-...md:89`) e confirmado pela triagem do CTO (`iteration_29.md`, "CI — ci.yml não cria banco do espelho"). Não é blocker do review — mas é o que impede a 29.0 de fechar a "definição de pronto".

### 🟡 Sugestões

**B2 (🟡/🟠) — `PessoasSchemaDriftTest` não detecta colunas ausentes no espelho (o teste "some" em vez de "falhar").**
- **Arquivo:** `test/lib/pessoas_schema_drift_test.rb:18-28`.
- **Cenário:** o teste só asserta "toda tabela espelhada existe e é idêntica no Pessoas2". Se o Pessoas2 **adicionar uma coluna** a uma tabela espelhada, o bloco local deixa de ser idêntico → falha (bom). Mas o inverso — o espelho omitir uma coluna que o espelho não lê, ou alguém **remover** uma tabela espelhada do arquivo local — faz a tabela apenas **desaparecer** do conjunto verificado, e o teste passa mesmo com o espelho incompleto (falta um check de cobertura: "todo subconjunto prometido existe"). A cópia ter sido feita **inteira** (ADR-0006 §91) é o que hoje dá a garantia; o teste não a trava.
- **Sugestão:** adicionar uma asserção de conjunto mínimo (as 8 tabelas) e, se possível, comparar também o conjunto de **colunas** de cada tabela espelhada contra a origem (não só a igualdade do bloco — que já cobre, desde que a tabela exista no local). Baixo custo.

**B3 (🟡) — Comentário de rubocop suppressivo amplo no schema espelho.**
- **Arquivo:** `test/support/pessoas_schema.rb:3-4` (`rubocop:disable all -- cópia literal ... byte a byte`).
- **Cenário:** é justificado (o drift compara byte a byte), mas `disable all` no arquivo inteiro impede o linter de pegar erros reais ali. O arquivo é gerado/copiado, então o risco é baixo.
- **Sugestão:** trocar por `disable Style/...` específicos, ou aceitar e registrar em `lessons.md`. Informativo.

**B4 (🟡) — Guarda da rake não protege contra `pessoas` apontar para o **host** errado.**
- **Arquivo:** `test/support/pessoas_schema_loader.rb:27-30`; `config/database.yml` (host vindo de `credentials.pessoas_db.host`).
- **Cenário:** a guarda de nome cobre `_test`, mas o host vem de credencial. Se alguém configurar em `RAILS_ENV=test` um host de produção **com** um banco terminando em `_test` (ex.: staging `..._test`), a task apaga esse banco. O risco real é remoto; a ADR-0006 cita "aborta se Rails.env não for test e se o nome não terminar em `_test`" — exatamente o que foi implementado, sem falha de conformidade.
- **Sugestão:** opcionalmente, exigir host local/allowlist de host no `verify!`. Débito pequeno.

### 🟢 Elogios

| ID | Elogio |
|---|---|
| B-G1 | **Guardas duplas e independentes** (ambiente E nome do banco), com testes próprios cobrindo envs inválidos, nomes inválidos (incluindo `pessoas_test_backup` e `nil`), o case feliz, e o abort da rake real via subprocesso (`Open3`). É a evidência que a ADR-0006 §Compliance exige. |
| B-G2 | **`load!` restaura a conexão no `ensure`** e usa `suppress_messages`; o comentário explica por que não usa o API privado do Rails. Cuidado correto com estado global de conexão. |
| B-G3 | **Nenhum YAML em `fixtures :all`** — a decisão da ADR-0006 foi honrada, o que mantém a suíte rodável em máquina sem o schema. Helpers limpam-se pela transação do teste (provado). |

---

## Falsos positivos refutados (o que suspeitei e a execução provou não ser bug)

| # | Suspeita | Verificação | Conclusão |
|---|---|---|---|
| F1 | **"`invariante_auto_gerencia.rb:62` tem `private` antes de `host_erro_*`, e o host LÊ `janela_de_revalidacao` no `if:` do `validate` — pode ser inacessível."** | Testes: o `validate` **dispara** (Bug 17 e Bug 15 preservados passam). O `if:` é avaliado no contexto da instância e métodos privados são chamáveis. | **Falso positivo.** O `private` é intencional e correto (mantém as janelas privadas, como o briefing pede). |
| F2 | **"`GestorIndividual.where(id: gestor.id).pick(:gestor_user_id)` não enxerga o `gestor_user_id` pendente (memória), podendo deixar a auto-gerência passar."** | `logins = [gestor.gestor_user_id]` entra **antes** e cobre a memória. Teste `gestor_individual_gerenciado_test.rb:82-97` prova o login pendente barrado. | **Falso positivo** — o lado do banco é o **complemento** (stale), o da memória é o principal. |
| F3 | **"Bug 8 pode não estar resolvido: o `RecordInvalid` consulta `errors.messages.record_invalid`, e `errors:` está fora de `activerecord:`."** | Fonte da gem `activerecord-8.1.1/lib/active_record/validations.rb:21-22` mostra `i18n_scope.errors.messages.record_invalid` **com fallback** para `errors.messages.record_invalid`. Ambos estão definidos (`pt-BR.yml:100` e `:130`). | **Falso positivo.** Caminho primário presente e testado. |
| F4 | **"O `index` pode levantar `RecordInvalid` (D8 violado)."** | `grep -rn '\.valid\?' app/` só retorna CSS; o controller de gestores só lê; a view só lê nome/orgao/size. | **Falso positivo.** D8 honrado. |
| F5 | **"O concern `InvarianteAutoGerencia` é um `include` no-op."** | `invariante_auto_gerencia.rb:58-60` registra o `validate` no `included do`; a mutation que desliga o `validate` no módulo derruba 7 testes dos dois hosts (registrado na 29.2-D7). | **Falso positivo** (isso era um achado anterior, já corrigido). |
| F6 | **"O `schema.rb` removeu a tabela `calculo_diarios` — regressão."** | O `HEAD` tinha `calculo_diarios` **duplicada** (linhas 32 e 62) por causa de um merge (`94bdbd6`); o diff **remove a cópia duplicada** e mantém a tabela e sua FK. Migração `20260901120000_create_calculo_diarios.rb` e o model `calculo_diario.rb` existem. | **Falso positivo** — é a deduplicação já documentada no `_context.md`. |
| F7 | **"`soma [gestor.gestor_user_id] + pick` é O(N) de queries por validação."** | É 1 `SELECT` por validação (o `reload` anterior era O(N) por vínculo). Só roda na janela (`new_record?`/`will_save_change_to_gestor_user_id?` no gestor; `ativo?` no vínculo). | **Falso positivo** — custo reduzido em relação à versão com `reload`. |
| F8 | **"`soma` com `nil` no array quebra `include?`."** | `logins.compact.include?(user_id)` remove nils antes de comparar; `return false if user_id.blank?` e `return false if gestor.nil?` já guardam. | **Falso positivo** — sem NPE. |
| F9 | **"Bug 2 da D7 (`RecordNotFound` cru no callback) não está morto."** | `pick` devolve `nil` (não levanta). Teste `gestor_individual_gerenciado_test.rb:126-136` prova. | **Falso positivo** — morto. |
| F10 | **"O locale tem chave `activerecord:` de topo duplicada / YAML inválido."** | `grep '^  [a-z_]*:'` retorna `date/time/errors/helpers/activerecord` — 5 chaves de topo distintas, todas sob `pt-BR:` linha 1. | **Falso positivo** — YAML válido e sem colisão. |

---

## Higiene do diff — arquivos fora do escopo no working tree

`git status` mostra **4 arquivos rastreados e modificados** que **não** pertencem a esta sprint e **devem ficar fora** do commit:

| Arquivo | Por quê fora |
|---|---|
| `api-ponto/config/credentials.yml.enc` | Sprint 8 (último commit `b085407`); segredo reversível pela `master.key`. Já triado. |
| `api-ponto/log/development.log` | Log. Ignorado por `.gitignore` (`api-ponto/log/`) mas **já rastreado** — precisa de `git rm --cached`. |
| `api-ponto/log/test.log` | Idem. |
| `api-ponto/tmp/cache/bootsnap/load-path-cache` | Cache. Ignorado por `.gitignore` (`api-ponto/tmp/`) mas **já rastreado** — precisa de `git rm --cached`. |

**Sugestão:** stage seletivo explícito. Nunca `git add -A` nem `git commit -a`. Os arquivos por pasta:
- **29.2/29.2-D7/Bug 8:** `api-ponto/app/models/concerns/{desativavel,invariante_auto_gerencia}.rb`, `api-ponto/app/models/gestor_individual.rb`, `api-ponto/app/models/gestor_individual_gerenciado.rb`, `api-ponto/config/locales/pt-BR.yml`, `api-ponto/db/migrate/2026092912*.rb`, `api-ponto/db/migrate/2026092913*.rb`, `api-ponto/db/schema.rb`, `api-ponto/test/models/*`, `api-ponto/test/lib/locale_record_invalid_test.rb`, `api-ponto/test/migrations/*`.
- **29.0:** `api-ponto/test/support/pessoas_schema.rb`, `pessoas_espelho_helper.rb`, `pessoas_schema_loader.rb`, `api-ponto/lib/tasks/test_pessoas_schema.rake`, `api-ponto/test/lib/pessoas_schema_*_test.rb`, `api-ponto/test/lib/pessoas_espelho_helper_test.rb`, `api-ponto/config/database.yml`.
- **Docs:** `docs/adr/0007-*`, `docs/quality/*`, `docs/progress/iteration_29.md`, `docs/progress/_context.md`, `docs/governance/lessons.md`, `docs/README.md`, `.gitignore`.

> **Nota:** o `.gitignore` da raiz foi estendido (achado 4 do reviewer anterior) para cobrir `/master.key` e `/credentials.yml.enc` na raiz. Correto — mas note que ele **não** cobre `api-ponto/config/credentials.yml.enc` porque esse é **rastreado** (o ignore não afeta arquivo já rastreado). O item §Higiene permanece.

---

## Ações corretivas

- [ ] **Nenhuma ação corretiva obrigatória (0 blockers).**
- [ ] Commit com **stage seletivo**, excluindo os 4 arquivos listados em §Higiene. *(obrigatório para não vazar credencial)*
- [ ] Conferir o comando do **baseline direcionado 104/300/0** (o subconjunto reproduzível dá 82/236; a suíte completa bate 896/3149 exato — provável glob mais amplo).
- [ ] Registrar os débitos 🟡/🟠 (A2/A4/A5, B1/B2) nos destinos já triados pelo CTO (29.3, 29.4/29.6, chore `Desativavel`, fork do CI). Nenhum é novo.

---

## Próxima Ação

Orchestrator avalia o estado e decide o próximo passo. A 29.2 (+ 29.2-D7 + Bug 8) está **aprovada sem blockers** e liberada para o protocolo de entrega (agrupamento de commits atômicos + stage seletivo). A 29.0 está **aprovada sem blockers**, com o débito do CI registrado como pendência da própria task (não bloqueia a 29.4/29.6, mas bloqueia a "definição de pronto" da 29.0).
