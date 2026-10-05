# iteration chore: fork do CI no GitLab (.gitlab-ci.yml) + RR-S1 + RR-S2

> **Modo:** AGILE | **Branch:** `chore/gitlab-ci-fork` | **Data:** 2026-09-29
> **Rastreabilidade:** `iteration_29.md` §Ruling do CTO — M2 e §Triagem do CTO — Fase 2 §2;
> `docs/quality/review_report_29_pipeline.md` §RR-S1 / §RR-S2 / §RE-D1.
> **Tipo:** chore (infra de CI). **COMMIT_MODE=manual** (sem commit/push nesta etapa).

## Descrição

Criar o fork do CI para o runner **GitLab** (remote de produção `gitlab.tjpi.jus.br`),
que hoje **não existe** — só há `.github/workflows/ci.yml` (GitHub Actions), que **não roda
em produção** (`ruby-version: .ruby-version` → `ruby-4.0.0` inexistente). Este é o único
item que **travava a "definição de pronto" em produção da Sprint 29** (`iteration_29.md:559`):
sem ele, o passo do banco espelho e o spec da M2 não rodam no ambiente real. Na mesma
passada, resolver os dois apontamentos 🟡 não-bloqueantes do re-review de pipeline (RR-S1,
RR-S2).

## Escopo

- [x] `.gitlab-ci.yml` com stages `security` / `quality` / `test` (modelo `pessoas2`,
      passos provados do `ci.yml`), service `postgres`, banco espelho criado + `test:pessoas_schema:load`
      + prova de existência (`grep -q 1`, sem `|| true` no `createdb`)
- [x] **RR-S1** — dar sinal aos exits 8/9 das flags anti-drift mesmo com o `EOLRails` vivo
- [x] **RR-S2** — `PESSOAS_DB_DATABASE` deixa de ser decorativo (bloco `pessoas` de test passa a ler a ENV)
- [x] **Blocker do fail-fast** — `allow_failure: true` em security/quality p/ o `test` executar + débito dono/prazo/critério
- [x] **Blocker do MONOREPO** — arquivo movido para a raiz do repo + `cd api-ponto` no `before_script` (GitLab só lê a raiz)
- [x] Decisão sobre o `.github/workflows/ci.yml` (manter/de-brittle — ver §Decisão)
- [x] Dívida registrada: divergência de versão do Ruby (não alterar `.ruby-version`/`.tool-versions`)

## 🔴 Correção pós-review — arquivo estava na SUBPASTA (monorepo); GitLab só lê a raiz

**Causa (anterior a todos os achados anteriores):** o repositório é um **MONOREPO** — a raiz
git é `Frequencia/` e contém `api-ponto/` (app Rails), `docs/`, `PRD-*.md`, `SPRINT-PLAN.md`,
`opencode.json`. O `.gitlab-ci.yml` foi criado em **`api-ponto/.gitlab-ci.yml`**, mas o
**GitLab só lê o `.gitlab-ci.yml` na raiz do repositório** — **não há descoberta automática
em subpasta**. Logo o pipeline **nunca foi criado**: o stage `test` não "falhou", ele **não
existia**. Todos os achados anteriores (fail-fast, B1/B2/B3) continuam válidos, mas nenhum
se aplicava porque o arquivo não era lido.

**O modelo `pessoas2` não se aplicava:** `pessoas2` é um app Rails **único na raiz** (não é
monorepo), com `.gitlab-ci.yml` na raiz e sem `cd` nenhum. Seguimos um modelo for de contexto.

**Correção:**
1. `api-ponto/.gitlab-ci.yml` → **`Frequencia/.gitlab-ci.yml`** (raiz do git).
2. **`cd api-ponto` no `before_script` global.** Escolhido em vez de `BUNDLE_GEMFILE` +
   prefixar cada `bin/`: o `before_script` e o `script` rodam no **mesmo shell**, então o
   `cd` **persiste** e **todo o resto do arquivo continua válido sem alteração** (menor
   superfície, menos pontos de erro). Prefixar `api-ponto/bin/*` exigiria mexer em 6 comandos
   e não resolveria o `bundle install` (que depende do cwd do `Gemfile`). Os `services:` não
   dependem do cwd (confirmado — resolvem por alias).
3. **Comentário no topo** explicando monorepo + por que o `cd` existe (para o próximo dev não
   "limpar" o `cd` e quebrar em silêncio).

**Prova (a partir da RAIZ do monorepo):**

| Cenário | Resultado |
|---|---|
| **Controle negativo — SEM `cd`** (`bin/brakeman`/`bin/rubocop`/`bin/rails` da raiz) | **EXIT=127** (não encontrado); `Gemfile`/`bin/` não existem na raiz |
| **Positivo — COM `cd api-ponto`** (um shell, como o GitLab) | `cwd` passa a `.../Frequencia/api-ponto`; `db:test:prepare` **EXIT=0**; `test:pessoas_schema:load` **EXIT=0**; espelho **19/68/0/0/0** |
| `bin/brakeman` (RR-S1) de dentro do `cd` | base **3** / nota vazia **8** / obsoleta **9** |
| `bin/rubocop` de dentro do `cd` | `bin/brakeman` = 0 offenses |
| Schema GitLab na raiz | `json schema validated` (security/quality `allow_failure=true`, test `false`) |

## Entregável 1 — `.gitlab-ci.yml`

- **Imagem:** `ruby:3.3.8-slim` — a versão REAL medida (`ruby -v` = 3.3.8;
  `Gemfile.lock` rails = 8.0.5). A imagem do registry institucional para 3.3.8 ainda
  não existe e o registry `.tjpi.jus.br` **não resolve fora da rede da instituição**
  (medido: `Could not resolve host`). A versão fica fixada **aqui**, não no
  `.ruby-version`/`.tool-versions` (ver §Dívida).
- **stages:** `security` (brakeman) → `quality` (rubocop) → `test`.
- **Comandos idênticos** ao `ci.yml` (paridade dev/prod — ruling M2 §6.4):
  `bin/brakeman --no-pager` e `bin/rubocop -f github`.
- **`PESSOAS_DB_*` via variável** (bloco `variables:` com defaults + overridável por
  variável de projeto do GitLab, que tem precedência — confirmado na doc oficial).
  A senha fica em `variables:` como default do runner efêmero, override recomendado por
  variável de projeto `PESSOAS_DB_PASSWORD`. **Não** há `|| true` que mascare falha real.

### Estado conhecido dos stages (medido — não mascarado)

| Stage | Comando | Resultado medido | Situação |
|---|---|---|---|
| security | `bin/brakeman --no-pager` | **EXIT=3** | 🔴 conhecido e rastreado — `Medium` EOLRails (bump Rails ≥ 8.1.x). O exit 3 **prova** que o scan roda. |
| quality | `bin/rubocop -f github` | **EXIT=1**, 77 offenses em 17 arquivos | 🔴 **pré-existente**, nunca rodou (o lint do GitHub nunca executou por `ruby-4.0.0`). Nenhuma offense nos arquivos desta chore (`bin/brakeman` = 0). |
| test | suíte + espelho | 896 runs / 12 erros + 1 falha baseline | 🟡 12 = baseline pré-existente; +1 flaky documentado que passa isolado. |

**Nenhum dos três é mascarado com `|| true`.** Este é o mesmo anti-padrão que a sprint
inteira combateu (gate que passa sem executar). Os dois stages vermelhos são **débito
pré-existente visível** — o objetivo do fork é justamente torná-lo visível no runner real.

### 🚦 `allow_failure: true` em security/quality — válvula temporária, com gatilho de remoção

**Por quê (blocker apontado pela coordenação, confirmado na doc do GitLab):** por default o
GitLab é **fail-fast** — "if any job fails, the pipeline is marked as failed and jobs in
later stages do not start". Como `security` sai 3 e `quality` sai 1, o stage **`test` NUNCA
executaria** — e `test` é exatamente o OBJETIVO desta chore (criar o banco espelho + rodar
a suíte em produção). Sem correção, o pipeline ficava vermelho e o test nem rodava: o mesmo
modo de falha "gate que parece existir e não executa".

**O que foi feito:** `allow_failure: true` em `security` e `quality`. O job **RODA**, a
saída/relatório ficam no log (marcação laranja WARN), e a esteira segue para o `test`.
Não é silêncio: é o job rodando e não bloqueando enquanto o débito pré-existente existe.

**Prova medida nos dois sentidos** (`gitlab-ci-local@4.75.1`, engine que implementa a
semântica de stages/fail-fast do GitLab; container `ruby:3.3.8-slim`; repro mínimo
`security exit 3` / `quality exit 1` / `test echo MARKER`):
- **Com `allow_failure: true`** → `security finished … WARN 3`, `quality finished … WARN 1`,
  **`test` EXECUTOU** (`TEST_EXECUTOU_MARKER` presente), pipeline EXIT=0.
- **Sem `allow_failure` (controle)** → `security finished … FAIL 3`, **`test` NÃO executou**,
  pipeline EXIT=1.
- O `.gitlab-ci.yml` **real** também foi validado contra o schema do GitLab:
  `gitlab-ci-local --list` → **json schema validated**, `security/quality allow_failure=true`,
  `test allow_failure=false`.

**Suposto (não verificável daqui):** o runner self-hosted do TJPI. `gitlab-ci-local` é uma
reimplementação; se o GitLab do TJPI tiver `allow_failure` desabilitado/alterado por
configuração de instância (não é o default), a prova não se transfere. Recomenda-se **1
run real** na branch de teste do GitLab para fechar.

### 📋 Débito → dono → prazo → critério objetivo de remoção do `allow_failure`

| Stage | Débito | Dono | Prazo | Critério de remoção (objetivo) |
|---|---|---|---|---|
| security | `Medium` EOLRails (Rails 8.0.5 EOL) | dev da stack / dono da chore de bump Rails | **2026-10-07** (EOL do Rails) | `bin/brakeman --no-pager` = **EXIT=0** após bump Rails ≥ 8.1.x → **remover `allow_failure: true`** (gate volta a ser DURO) |
| quality | 77 offenses RuboCop (17 arquivos, pré-existentes) | **dev — chore `chore/limpeza-rubocop-77`** (decisão do dev, 2026-09-29) | **2026-10-13** | `bin/rubocop -f github` = **EXIT=0** → **remover `allow_failure: true`** |
| test | (nenhum) — 12 erros + 1 falha baseline pré-existentes | — | — | `allow_failure` **nunca** entra no `test` (é o gate que importa) |

> **Rastreio obrigatório:** o `allow_failure` só é legítimo enquanto os débitos acima
> existirem. O critério de remoção é **binário e executável** (exit code), não "avaliar
> depois". Se o prazo estourar sem a remoção, isto vira papel de parede — o risco nomeado
> pela coordenação. O gatilho ideal seria um teste de CI que falhe quando `allow_failure`
> continuar presente além do prazo (chore opcional).

## 🔴 Correção pós-review — 3 blockers no job `test` (B1/B2/B3)

Causa-raiz: o `.gitlab-ci.yml` foi **adaptado do `ci.yml` de GitHub**, mas perdeu duas
coisas e manteve uma suposição que só valia lá. Todos corrigidos e **provados com Docker
real** (rede própria, `--network-alias postgres`, **SEM publicar porta** — reproduz o
executor docker do GitLab; o `gitlab-ci-local` anteriormente usado publica portas em
`localhost` e **não expõe** este bug, por isso não serve de prova).

| # | Bug | Correção | Prova |
|---|---|---|---|
| B1 | `localhost` não alcança `services:` no executor docker (services resolvem por alias; sem forwarding de porta). O `until pg_isready` pendurava o job. | Todas as chamadas do `test` (e `PESSOAS_DB_HOST`) passam a usar o **alias `postgres`** | Container `ruby:3.3.8-slim` na mesma rede: `localhost:5432` → **recusado** (`pg_isready` EXIT=2); `postgres:5432` → **ok** (`pg_isready` EXIT=0, `inet_server_addr()` = IP do container) |
| B2 | Faltava `DATABASE_URL`: `test.primary` (`api_ponto_test`) não tem host/usuário no `database.yml`; sem a URL o primário nunca é criado e `db:test:prepare` falha | `DATABASE_URL: postgres://postgres:postgres@postgres:5432` (alias) | Sem `DATABASE_URL` → **EXIT=1**; com → **EXIT=0**; `api_ponto_test` criado (confirmado por `psql`) |
| B3 | Faltava `PGPASSWORD`: contra `postgres:17` (scram) `createdb` trava no prompt e `psql` nega | `PGPASSWORD: postgres` | Sem → prompt `Password:` + `fe_sendauth: no password supplied` (EXIT=2); com → EXIT=0 |

**Comentário falso corrigido:** o antigo comentário afirmava que o `|| true` do `CREATE ROLE`
cobria a falha de auth — **falso**: o `CREATE ROLE` usa o **mesmo caminho de autenticação**
(`psql` contra o alias com `PGPASSWORD`) e falharia pelo mesmo motivo; o `|| true` só absorve
o erro idempotente "role already exists". A cobertura real é o `PGPASSWORD`, o `until
pg_isready` e o `createdb -O` em cascata. O texto foi reescrito.

**Quarto achado (efeito colateral da prova em container limpo):** o `before_script` não
instalava `default-libmysqlclient-dev`, exigido pela gem `mysql2` (`Gemfile:12`) — o
`bundle install` **abortava** (`An error occurred while installing mysql2 (0.5.7)`). O
`ci.yml` de GitHub não a lista porque aquele job **nunca executou** (morria no `ruby-4.0.0`).
Adicionada ao `before_script` e verificada (bundle completo em `ruby:3.3.8-slim` limpo).

### Prova da sequência completa do job `test` (container `ruby:3.3.8-slim`, rede própria, alias)

| Passo | Resultado |
|---|---|
| `until pg_isready -h postgres` | `postgres:5432 - accepting connections` (EXIT=0) |
| `CREATE ROLE ... PASSWORD` (`\|\| true`) | `CREATE ROLE` |
| `createdb -h postgres -O ...` (sem `\|\| true`) | **EXIT=0** |
| `psql ... \| grep -q 1` | **EXIT=0** |
| `bin/rails db:test:prepare` | **EXIT=0** |
| `bin/rails test:pessoas_schema:load` | `Pessoas mirror test schema loaded…`, **EXIT=0** |
| espelho (3 arquivos) | **19 runs / 68 assertions / 0 failures / 0 errors / 0 skips** |

## Entregável 2 — RR-S1 (sinal aos exits 8/9)

**Problema medido:** no Brakeman 8.0.5 o `exit_on_warn` (exit 3) é avaliado **antes** das
checagens anti-drift (`commandline.rb:150` vs `:158`/`:163`). Enquanto o `Medium` EOLRails
existir, o processo sai **3** e os exits **8/9** ficam mascarados (mensagem impressa, código
não). Medido: nota vazia → 3 (esperado 8); entrada obsoleta → 3 (esperado 9). Control (com
o EOLRails coberto no ledger): 8 / 9 / 0.

**Solução:** `bin/brakeman` passa a **capturar** a saída, **reemití-la verbatim** (nada é
escondido) e, se o padrão de falha de política aparecer, promover o exit ao código
**prescrito pelo ruling** (8/9). Não remove o EOLRails do scan, não usa `-x EOLRails` nem
`--no-exit-on-warn`. Um ledger íntegro preserva o exit real (hoje 3; após o bump, 0).
Detecção por **linha-âncora** determinística. Fail-safe: crash inesperado preserva exit
não-zero (cobre o RE-M2.1 — `note` ausente → `NoMethodError`).

## Entregável 3 — RR-S2 (`PESSOAS_DB_DATABASE` decorativo)

O bloco `pessoas` de **test** do `database.yml` passa a ler
`ENV.fetch("PESSOAS_DB_DATABASE", "frequencia_pessoas_espelho_test")`. Preserva o fix do B1
(ENV > credentials nos 4 campos; bloco `development`/`production` intocados). Destrava o
isolamento de banco por trilha que a Fase 2 vai precisar.

## Decisão — `.github/workflows/ci.yml`

**Fica, mas de-brittled.** Justificativa (custo de dois arquivos divergindo):
- O `ci.yml` de GitHub **não roda em produção** hoje, mas serve ao dev/PR no GitHub
  (`origin`/`upstream`) — removê-lo não é escopo desta chore (decisão de dono) e apagaria
  o único CI que o dev consegue rodar fora da rede da instituição.
- O custo real de divergência é o `ruby-version: .ruby-version` → **`ruby-4.0.0` inexistente**,
  que trava o job antes de rodar. Correção **cirúrgica** (não é fork, é conserto): fixar a
  versão real `3.3.8` nos 3 jobs. Assim os dois arquivos voltam a ter a **mesma spec
  executável** (paridade determinística) e o `ci.yml` deixa de ser um terceiro estado morto.
- Mudança restrita a `.github/workflows/ci.yml` (fora do caminho de produção). Se o dono
  preferir remover depois, a decisão é de 1 linha.

## Dívida registrada — versão do Ruby

Três fontes conflitantes, **nenhuma** igual ao ambiente medido:

| Fonte | Diz | Realidade |
|---|---|---|
| `AGENTS.md` | Rails 8.0.4 / Ruby 4.0.0 | rails 8.0.5 / ruby 3.3.8 (medido) |
| `.ruby-version` / `.tool-versions` | `ruby-4.0.0` | **não existe** |
| `governance/_context.md` | Ruby 3.4.2 | defasado |
| **medido** | — | `ruby -v` = **3.3.8**; `Gemfile.lock` rails = **8.0.5** |

**Não alterados nesta chore** (blast radius: toolchain local mise/asdf de todo mundo).
Fixada na imagem do `.gitlab-ci.yml`. **Débito:** unificar as 3 fontes e decidir a versão
alvo (dono diferente). Registrado também aqui para rastreio.

## 📋 Relatório de Revisão — Code Reviewer

**Veredito: ❌ REJEITADO — com blockers (B1, B2, B3).** Relatório completo em
[`docs/quality/review_report_chore_gitlab_ci.md`](../quality/review_report_chore_gitlab_ci.md).

**O núcleo está correto** (RR-S1 provado 8/9/3; RR-S2 provado nos 2 sentidos; `ci.yml`
de-brittle mínimo; `allow_failure` do `security` ancorado; rastreabilidade exemplar).
Os 3 blockers são todos do **job `test` nunca ter rodado num GitLab real** — o `gitlab-ci-local`
publica as portas dos services em `localhost`, semântica que **diverge** do GitLab:

| ID | O que | Onde |
|---|---|---|
| 🔴 B1 | `test` usa `localhost` para o service; o executor docker do GitLab só expõe services por **hostname/alias** (`postgres` declarado e não usado) → `pg_isready`/`psql`/`createdb` não acham o Postgres | `.gitlab-ci.yml:143,149,153,171,175,181,60` |
| 🔴 B2 | `test` **não define `DATABASE_URL`**; `test.primary` (`api_ponto_test`) não tem host/usuário e não é criado (o `ci.yml` de GitHub tem, linha 123) | `.gitlab-ci.yml:151-192` |
| 🔴 B3 | `test` **não define `PGPASSWORD`**; contra o `postgres:17` (scram-sha-256) o `createdb` **trava** e o `psql` nega — o `2>/dev/null \|\| true` da role não cobre | `.gitlab-ci.yml:151-183` |

Sugestões (6) e débitos (3) no relatório. **Nada impede o commit/push** (COMMIT_MODE=manual);
o que impede o **merge** é o `test` não rodar em produção.

**Status do bloco (1ª passada):** ✅ Implementado, ❌ **Rejeitado (B1, B2, B3)** — histórico.

---

## 📋 Re-Review — Code Reviewer (2026-09-29)

**Veredito: ✅ APROVADO — sem blockers.** Relatório completo em
[`docs/quality/review_report_chore_gitlab_ci.md`](../quality/review_report_chore_gitlab_ci.md) (§RE-REVIEW).

**B1, B2 e B3 FECHADOS** — reproduzidos de forma independente com **Docker real** (rede própria,
`--network-alias postgres`, **sem `-p`**; job em `ruby:3.3.8-slim` na mesma rede, sem publicar porta):

| # | Status | Evidência independente desta re-review |
|---|---|---|
| 🔴 B1 | ✅ **Fechado** | `localhost` → `no response`/`Connection refused` (EXIT=2); alias `postgres` → `accepting connections`/`inet_server_addr()=172.23.0.2` (EXIT=0). Zero `localhost` em linha executável. |
| 🔴 B2 | ✅ **Fechado** | `DATABASE_URL` com o alias (`:168`); sintaxe canônica do `ActiveRecord`; controle negativo (sem) já dera EXIT=1. |
| 🔴 B3 | ✅ **Fechado** | Sem `PGPASSWORD` → `fe_sendauth: no password supplied` (EXIT=2); com → EXIT=0. `pg_hba.conf` = `host all all all scram-sha-256`. |
| Achado extra | ✅ **Correto** | `bundle install` completo em `ruby:3.3.8-slim` limpo → **129 gems, EXIT=0**; `default-libmysqlclient-dev` é o pacote certo para `mysql2` 0.5.7. |
| Comentário `\|\| true` | ✅ **Exato** | Reescrita confere; cascata do `createdb -O` provada (EXIT=1). S2 (dono do lint) resolvido (`chore/limpeza-rubocop-77`). |

**A prova por Docker do autor se sustenta como método:** preserva a propriedade sob teste (services
por alias, sem forwarding para `localhost`) e o controle negativo é legítimo (falha por ausência de
listener, não por auth). A propagação de variável de nível de job ao container do service foi
confirmada na doc oficial ("automatically passed down to the Postgres container"). Único resíduo
não-reproduzível fora do TJPI: o runner self-hosted (S6).

**O que ainda impede o merge:** nada de código. Resta apenas a validação ambiental recomendada
(**1 run real** do job `test` no GitLab do TJPI). Notas não-bloqueantes: S1 (`pg_isready` sem
timeout) e S4 (`POSTGRES_HOST`/`POSTGRES_PORT` decorativos).

**Status do bloco:** ✅ Implementado, ✅ **Aprovado** (re-review) — 0 blockers. Merge para
`feature/demanda-29-schema-gestor-individual` liberado do ponto de vista de código, pendente da
validação ambiental do runner.

## 🏭 CI/CD Pipeline Local

**Branch:** `chore/gitlab-ci-fork` | **Data:** `2026-09-29` | **Resultado:** ✅ **Aprovado (liberado para push)**

Comandos executados **exatamente** como no `.gitlab-ci.yml` (fonte de verdade; a esteira mapeia minitest, não rspec). Binstubs `bin/*` (nunca `bundle exec`). Ruby medido: 3.3.8.

| Step | Status | Resultado medido | Interpretação |
|------|--------|------------------|---------------|
| Security | ⚠️ Bypass (pré-existente) | `bin/brakeman --no-pager` → **EXIT=3**; 1 warning (Medium EOLRails, `Gemfile.lock:245`) | Pré-existente rastreado (bump Rails ≥ 8.1.x, prazo 2026-10-07). Exit 3 prova que o scan roda. Não é blocker. |
| Quality | ⚠️ Bypass (pré-existente) | `bin/rubocop -f github` → **EXIT=1**; **77 offenses em 17 arquivos** | Pré-existente (débito `chore/limpeza-rubocop-77`). 0 offenses nos arquivos do bloco (`bin/brakeman` = 0 isolado). Não é blocker. |
| Test | ✅ Passou | 896 runs / 3149 assertions / **1 failure + 11 errors** (12 total) | Subconjunto do baseline de 13 (11× `redirect_to` Devise + 1 timezone). **Zero falha nova.** |

### Prova do RR-S1 (wrapper `bin/brakeman`) — 3 sentidos

| Cenário | Ledger | Medido | Esperado |
|---|---|---|---|
| Íntegro (o versionado) | `config/brakeman.ignore` | **3** | 3 ✅ |
| Nota vazia | `/tmp/brakeman_nota_vazia.json` (temporário, **já removido**) | **8** | 8 ✅ |
| Entrada obsoleta | `/tmp/brakeman_obsoleta.json` (fingerprint falso; **já removido**) | **9** | 9 ✅ |

`config/brakeman.ignore` **não foi alterado** (`git diff` vazio). Ledgers temporários criados via `-i` e removidos.

### Prova do job `test` (sequência completa)

| Passo | Medido |
|---|---|
| `RAILS_ENV=test bin/rails db:test:prepare` | **EXIT=0** |
| `RAILS_ENV=test bin/rails test:pessoas_schema:load` | `Pessoas mirror test schema loaded into frequencia_pessoas_espelho_test`, **EXIT=0** |
| Espelho (3 arquivos: `pessoas_unidade_test`, `pessoas_pessoa_test`, `pessoas_espelho_helper_test`) | **19 runs / 68 assertions / 0 failures / 0 errors / 0 skips** (baseline exato) |
| Suíte completa (`bin/rails test`, paralelização 12 workers) 2× | **896 runs / 1 failure + 11 errors** (idêntico nas 2 rodadas) |
| Isolado dos arquivos Devise+timezone, 2× | 65 runs / 1 failure + 11 errors (**determinístico**, não flaky) |

**Isolamento da flakiness:** o esperado era 13 (12 baseline + 1 flaky `configuracoes_sistema`). Observado: **12** nas duas rodadas — o flaky **não disparou** desta vez (sua natureza é justamente intermitente). Os 12 observados = 11× `NoMethodError: private method 'redirect_to'` nos controllers Devise + 1× timezone (`presenca_endpoints_test.rb:187`, `15/07/2026 11:30:45` vs `14:30:45`). Nenhuma fora do baseline — **nenhuma regressão introduzida por este bloco**.

### Validação estrutural do `.gitlab-ci.yml` (YAML + executabilidade)

- **YAML parseia** (Psych): OK. `stages: [security, quality, test]`; `image: ruby:3.3.8-slim`.
- `security`/`quality` → `allow_failure: true`; `test` → `allow_failure` ausente (= `false`, gate DURO). ✅
- **Comandos existem:** `bin/brakeman`, `bin/rubocop`, `bin/rails` executáveis; rake task `test:pessoas_schema:load` existe (`bin/rails -T`).
- **Variáveis referenciadas nos scripts** (`PESSOAS_DB_DATABASE`, `PESSOAS_DB_PASSWORD`, `PESSOAS_DB_USERNAME`) **todas definidas** em `variables:` — **0 indefinidas**. Demais (`DATABASE_URL`, `PGPASSWORD`, `POSTGRES_*`, `RAILS_ENV`) definidas no job `test`.
- **Único `|| true`** do arquivo está no `CREATE ROLE` (linha 203) — absorve só o erro idempotente "role already exists"; o `createdb -O` **sem `|| true`** (linha 205) e o `grep -q 1` (linha 213) quebram o step em falha real. Anti-padrão "gate verde sem executar" ausente. ✅
- **Não medido por mim:** semântica de rede do runner GitLab (services por alias) — já provada por Docker real no re-review; `gitlab-ci-local` não está instalado nesta máquina (npx exigiria download; não justificado). O runner self-hosted do TJPI segue como validação ambiental pendente (residual já registrado pelo reviewer).

**Observações:** nenhum arquivo de produção da app foi alterado no bloco (`app/`, `lib/` intocados); a esteira não teve blockers de código. `config/credentials.yml.enc`, `log/*`, `tmp/cache/*` são ruído fora do escopo e não foram tocados. Os 2 vermelhos (security/quality) são débito pré-existente com dono/prazo/gatilho — não blockers deste bloco.

**Decisão:** ✅ **Liberado para push** (para a branch de TESTE no GitLab — o push é do coordenador). O único resíduo não verificável daqui continua sendo o **1 run real do job `test` no runner do TJPI**.

## Linha do Tempo

| Horário | O que foi feito | Resultado |
|---------|-----------------|-----------|
| 2026-09-29 | Leitura dos insumos (iteration_29, review_29_pipeline, pessoas2/.gitlab-ci.yml, ci.yml, database.yml, bin/brakeman, ledger) | contexto |
| 2026-09-29 | Medição do mascaramento 8/9 (mutação de ledger) | confirmado: nota vazia→3, obsoleta→3; control→8/9/0 |
| 2026-09-29 | Branch `chore/gitlab-ci-fork` a partir do HEAD da 29 (ver Notas) | criada |
| 2026-09-29 | RR-S2: `database.yml` lê `PESSOAS_DB_DATABASE` | provado nos 2 sentidos |
| 2026-09-29 | RR-S1: wrapper no `bin/brakeman` | provado: 3/8/9/0/8/1 |
| 2026-09-29 | `.gitlab-ci.yml` criado | YAML parse OK |
| 2026-09-29 | `ci.yml`: `ruby-version` fixado em `3.3.8` (de-brittle) | YAML parse OK |
| 2026-09-29 | Provas: schema load EXIT=0, espelho 19/68/0/0/0, skips 19/0 errors | OK |
| 2026-09-29 | Suíte completa | 896 runs / 1 failure + 12 errors = **13** (12 baseline + 1 flaky `configuracoes_sistema`, confirmado isolado: 9/0/0 nas 2 rodadas) — nenhuma regressão |
| 2026-09-29 | **Blocker da coordenação:** fail-fast impede `test` de rodar | `allow_failure: true` em security/quality + débito dono/prazo/critério |
| 2026-09-29 | Prova do fail-fast com `gitlab-ci-local@4.75.1` (repro + arquivo real) | com allow: test roda (pipeline 0); sem: test não roda (pipeline 1); schema validado |
| 2026-09-29 | **Review rejeitou: 3 blockers no job `test` (B1/B2/B3)** | corrigidos: alias `postgres`, `DATABASE_URL`, `PGPASSWORD` + comentário falso + `default-libmysqlclient-dev` |
| 2026-09-29 | Prova de rede **real** (docker network própria, sem publicar porta) | `localhost` recusado (EXIT=2); alias `postgres` ok (EXIT=0); sequência completa verde |
| 2026-09-29 | Débito `quality` ganha dono: `chore/limpeza-rubocop-77`, prazo 2026-10-13 | S2 do reviewer fechado |
| 2026-09-30 | **Blocker do MONOREPO:** arquivo estava em `api-ponto/`; GitLab só lê a raiz | movido p/ `Frequencia/.gitlab-ci.yml` + `cd api-ponto`; provado positivo/negativo |
| 2026-09-29 | **Re-review do Code Reviewer** (repro Docker independente) | ✅ **Aprovado** — B1/B2/B3 fechados, 0 blockers |

## Commits

Branch `chore/gitlab-ci-fork` (base = `73726e1`, HEAD da
`feature/demanda-29-schema-gestor-individual`). Três commits, stage seletivo,
nunca `git add -A`. A ordem é `fix:` → `ci:` → `docs:` de propósito: o
`.gitlab-ci.yml` referencia o RR-S1 e o RR-S2, então o commit que os introduz vem
antes.

| Commit | Assunto | Arquivos |
|---|---|---|
| `3ae995d` | `fix:` devolve sinal aos exits 8/9 do Brakeman e torna o database do espelho parametrizável | `bin/brakeman`, `config/database.yml` |
| `ccba59f` | `ci:` cria o fork do CI no GitLab e destrava o workflow do GitHub | `.gitlab-ci.yml` (novo), `.github/workflows/ci.yml` |
| `6382de6` | `docs:` rastreabilidade da chore de CI e lições de método | `lessons.md`, `iteration_chore_gitlab-ci.md`, `review_report_chore_gitlab_ci.md` (novo) |

**Push: FEITO.** `git push -u gitlab chore/gitlab-ci-fork` — branch de **teste**
criada no repo institucional (`gitlab.tjpi.jus.br/administrativo/frequencia`),
**nunca `main`**. Objetivo: disparar o pipeline e validar o job `test` no runner
real do TJPI — o único resíduo que nenhuma validação local fecha.

> **Correção de registro:** a versão anterior desta seção afirmava "NADA foi
> commitado/pushado", com os comandos apenas "preparados". O texto ficou obsoleto
> **dentro do próprio commit que o continha** (`6382de6`) — a commit tornou falsa
> a afirmação que ela mesma carregava. O git é a fonte: os 3 commits acima e o
> push existem.

> Ficaram **FORA** de todo stage (preservados, não revertidos):
> `api-ponto/config/credentials.yml.enc` (alteração do dev, fora do sprint),
> `api-ponto/log/*.log`, `api-ponto/tmp/cache/bootsnap/load-path-cache`.

## Notas

- **Branch base — desvio do protocolo.** O `agile-task-protocol` diz para criar de `develop`.
  Não foi possível: as flags anti-drift, o ledger `config/brakeman.ignore`, o passo do banco
  espelho no `ci.yml` e o `ENV.fetch` do bloco `pessoas` existem **apenas** na
  `feature/demanda-29-schema-gestor-individual` (19 commits à frente de `develop`; `develop`
  não tem nenhum). Criar de `develop` produziria um `.gitlab-ci.yml` que referencia flags e
  passos inexistentes. A branch foi criada **do HEAD da 29** para preservar a base da qual o
  fork depende. **Merge target: `feature/demanda-29-schema-gestor-individual`**, não `develop`.
- **COMMIT_MODE=manual:** os 3 commits e o push da branch de teste foram
  executados com aprovação explícita do dev, após o Code Reviewer (aprovado, 0
  blockers) e a esteira local (liberada, zero falha nova). **Sem push para
  `main`** — o merge target é `feature/demanda-29-schema-gestor-individual`.
- **Higiene:** `config/credentials.yml.enc`, `log/*.log`, `tmp/cache/*` ficam FORA do stage
  (ruído de working tree). `.gitlab-ci.yml` é untracked → exige `git add` explícito.
- **Prova não executada:** o job `test` no GitLab real (registry `.tjpi.jus.br` inacessível
  fora da rede; runner não acessível). Validado o YAML e cada passo isoladamente na máquina
  (schema load, espelho, skips, brakeman). O `ci.yml` de GitHub tem a mesma estrutura já
  provada em container `postgres:17`.

## ⛔ BLOQUEIO — a chore NÃO fecha a "definição de pronto" em produção

**Estado: bloqueada por infraestrutura. NÃO declarar concluída.**

O pipeline **foi criado** no GitLab (evidência real do projeto, 2026-09-30 — não
inferência), com os três jobs enfileirados:

```
security  → pending
quality   → created
test      → created
```

Mas o `security` não sai de `pending`. Ao abrir o job, o GitLab responde:
**"não existem runners online atribuídos"**. O job está travado esperando um
runner que não existe — **nenhum arquivo que o projeto versiona resolve isso**.

### O que está PROVADO (evidência real do GitLab)

- O GitLab **lê** o `.gitlab-ci.yml` e **cria o pipeline** com os 3 jobs. É a
  primeira confirmação vinda do próprio GitLab nesta chore: a correção do
  monorepo (arquivo na raiz) está validada na prática. Antes, com o arquivo em
  `api-ponto/`, ele não criava pipeline nenhum.

### O que NÃO está provado (e é o que importa)

- **Que o job `test` executa.** Ninguém nunca o viu rodar num runner real. A
  razão de existir desta chore era exatamente esta verificação.

### A "definição de pronto" em produção permanece ABERTA

`iteration_29.md:559` registra que a 29.0 não fecha a DoD em produção enquanto o
`.gitlab-ci.yml` não existir **e rodar**. O primeiro critério foi atendido
(arquivo na raiz, pipeline criado); o segundo **não**. Os gates de teste das
29.0/29.4/29.6 seguem sem cobertura em produção.

### Risco residual (suposto, não medido)

A semântica de rede já foi reproduzida em Docker real; o `cd api-ponto` foi
provado a partir da raiz, com controle negativo. O que resta não verificável é o
**executor do runner**: `apt-get` exigindo root, acesso ao registry institucional,
e se ele se comporta como a nossa reprodução. "Risco pequeno" **não é**
"verificado" — e a verificação era o objetivo.

### Quinta variação do mesmo erro de método

Esta chore produziu cinco artefatos que **pareciam funcionar** e não funcionavam:

| # | Aparência | Realidade |
|---|---|---|
| 1 | Testes passam no Postgres local | `trust` no loopback ≠ `scram-sha-256` |
| 2 | Provado com `gitlab-ci-local` | A engine publica porta em `localhost` |
| 3 | `brakeman` saía 0 | Saía 0 **sem escanear** (`--ensure-latest`) |
| 4 | YAML, comandos e rede validados | O GitLab **não lia** o arquivo (estava em `api-ponto/`) |
| 5 | Pipeline criado com 3 jobs | **Nenhum runner** para executá-lo |

Nenhuma dessas provas exercitava a mesma condição do ambiente real. Regra
registrada em `lessons.md`: **antes de provar, perguntar se a prova exercita a
MESMA condição** — onde a ferramenta procura o artefato e como resolve a rede.

### Desbloqueio (ação da infra TJPI, fora do nosso alcance)

Registrar um runner no projeto (`Settings → CI/CD → Runners`). Verificar também
se ele exige **`tags:`** — o `.gitlab-ci.yml` **não declara nenhuma tag**, então
o job só roda em runner marcado para *"run untagged jobs"*. Se o runner
institucional exigir tag, a correção é uma linha, mas só dá para saber com o
runner no ar.

## Pendências / débitos abertos

| Débito | Dono | Critério de pronto |
|---|---|---|
| **Registrar um runner no projeto (destrava esta chore)** | **infra TJPI** | `security`/`quality`/`test` saem de `pending`/`created` e executam |
| Bump Rails ≥ 8.1.x (remove o `Medium` EOLRails) | a definir | `bin/brakeman --no-pager` = EXIT=0 |
| Unificar versão do Ruby (3 fontes) | a definir | `.ruby-version` = `.tool-versions` = imagem do CI = `ruby -v` |
| Publicar imagem `.../frequencia/ruby:3.3.8` no registry institucional | infra | trocar a linha `image:` do `.gitlab-ci.yml` |
| Definir `PESSOAS_DB_PASSWORD` como variável de projeto no GitLab | infra/dono | remover o default `"app"` do YAML |
| Limpar as 77 offenses do RuboCop (17 arquivos, pré-existentes) | a definir | `bin/rubocop -f github` = EXIT=0 |
| Mover `.github/workflows/ci.yml` para a raiz do repo (mesmo defeito do monorepo) | a definir | GitHub Actions encontra o workflow; `ruby-version` já corrigido |
| Registrar em `lessons.md` as duas lições desta chore | Code Specialist | — |
