# Relatório de Revisão — chore `chore/gitlab-ci-fork` (.gitlab-ci.yml + RR-S1 + RR-S2)

> **Branch:** `chore/gitlab-ci-fork` (base `73726e1`, HEAD da `feature/demanda-29-schema-gestor-individual`)
> **Merge target:** `feature/demanda-29-schema-gestor-individual` (NÃO `develop`) — desvio justificado
> **Data:** 2026-09-29
> **Modo:** AGILE (TASK_MODE=AGILE) — foco em Blockers; sugestões como notas
> **Propósito:** revisar o fork do CI para o runner GitLab + os dois apontamentos 🟡 (RR-S1/RR-S2)
> **Arquivos no escopo:** `api-ponto/.gitlab-ci.yml` (novo), `api-ponto/bin/brakeman`, `api-ponto/config/database.yml` (bloco `pessoas` de test), `api-ponto/.github/workflows/ci.yml`, `docs/governance/lessons.md`, `docs/progress/iteration_chore_gitlab-ci.md` (novo)
> **Fora do escopo (ruído de working tree, corretamente excluído do stage):** `api-ponto/config/credentials.yml.enc`, `api-ponto/log/*.log`, `api-ponto/tmp/cache/bootsnap/load-path-cache`

---

## 🔁 RE-REVIEW (2026-09-29) — Veredito: ✅ APROVADO — sem blockers

> **Escopo desta segunda passada:** **apenas** os 3 blockers (B1/B2/B3) do job `test`, o comentário falso do `|| true` e o achado novo (`default-libmysqlclient-dev`). O que já foi aprovado (RR-S1, RR-S2, decisão do `ci.yml`, `allow_failure`, rastreabilidade) **não foi reverificado** — o veredito original abaixo permanece como histórico.
>
> **Resultado:** **B1, B2 e B3 FECHADOS.** Reproduzidos de forma independente com Docker real (rede própria, `--network-alias postgres`, **sem `-p`**); `bundle install` limpo passa. A prova por Docker do autor **se sustenta como método**. Detalhes na seção [RE-REVIEW — seção detalhada](#re-review--seção-detalhada) ao final.
>
> - **Blockers remanescentes:** 0
> - **Notas (🟡) remanescentes:** S1 (`pg_isready` sem timeout) e S4 (`POSTGRES_HOST/PORT` decorativos) — seguem abertas, não bloqueiam
> - **Impede o merge:** **nada de código.** Resta apenas a validação ambiental que só o runner do TJPI pode dar (**1 run real** do job `test`) — recomendação, não blocker.

---

## Veredito original (1ª passada): ❌ REJEITADO — com blockers

> ⚠️ **Histórico — superado pelo RE-REVIEW acima.** Mantido para rastreabilidade.

**O núcleo da entrega (RR-S1, RR-S2, decisão do `.github/workflows/ci.yml`, o *design* anti-masking e a rastreabilidade do `allow_failure`) está correto e foi verificado de forma independente.** Mas o **job `test` do `.gitlab-ci.yml` não é executável no runner GitLab real** — o objetivo declarado da chore (criar o banco espelho + rodar a suíte em produção) não é atingido pelo arquivo como escrito. Três blockers de conexão/setup no `test`, todos decorrentes de o job **nunca ter sido rodado contra um GitLab real** (a validação usou `gitlab-ci-local`, cuja semântica de rede de *services* diverge do GitLab).

- **Blockers:** 3
- **Sugestões (🟡):** 6
- **Débitos (🟠):** 3
- **Elogios (🟢):** 6

**Nada impede o commit/push em si** (COMMIT_MODE=manual; nenhum commit/push deve ser feito nesta etapa). O que impede o **merge** é o job `test` não rodar em produção — ver Blockers.

---

## Blockers (🔴)

### 🔴 B1 — `test` acessa o Postgres do `services:` em `localhost`, mas o executor docker do GitLab só expõe services por hostname/alias

- **Arquivo:linha:** `.gitlab-ci.yml:143` (`alias: postgres` — declarado e **nunca usado**), `:149` (`POSTGRES_HOST: localhost`), `:153` (`until pg_isready -h localhost ...`), `:171` (`psql -h localhost`), `:175` (`createdb -h localhost`), `:181` (`psql -h localhost`), `:60` (`PESSOAS_DB_HOST: "localhost"`).
- **Cenário:** no executor docker do GitLab, o job e os services ficam em containers distintos, resolvidos por **hostname/alias** ("The container running the job and the containers running the service resolve each other's hostnames and aliases"; o runner deriva o alias do nome da imagem — aqui `postgres`, declarado explicitamente). **Não há forwarding automático da porta do service para o `localhost` do job.** Logo `pg_isready -h localhost` não encontra o Postgres do service.
- **Impacto:** o `until pg_isready ...; do sleep 1; done` **não tem timeout** → o job fica em loop até o timeout de job do GitLab (default ~1h) e falha por timeout; mesmo que o `pg_isready` retornasse de imediato, `createdb`/`psql -h localhost` falhariam. O stage `test` — o OBJETIVO da chore — não executa. É o mesmo anti-padrão "gate que parece existir e não executa", agora no próprio stage que a chore existe para entregar.
- **Por que a validação local não pegou:** `gitlab-ci-local` **publica as portas dos services em `localhost`**, semântica diferente do GitLab real. O `POSTGRES_HOST: localhost` e o comentário de `:147-148` ("A senha é local ao runner efêmero", "O alias `postgres` fica disponível para quem preferir usar `POSTGRES_HOST`") partem dessa premissa — mas `localhost` **não** é o alias.
- **Sugestão:** usar o alias em todos os pontos — `pg_isready -h postgres`, `psql/createdb -h postgres`, `POSTGRES_HOST: postgres`, `PESSOAS_DB_HOST: postgres` (ou `POSTGRES_SERVICE_HOST`, injetado pelo GitLab). Confirmar com **1 run real** na branch de teste do GitLab (a própria `iteration_chore` já admite que o runner do TJPI não foi verificado).

### 🔴 B2 — O `test` não define `DATABASE_URL`; o banco **primário** de test (`api_ponto_test`) não tem host/usuário e não é criado

- **Arquivo:linha:** `.gitlab-ci.yml:151-192` (script do `test` — nenhuma menção a `DATABASE_URL` nem `createdb api_ponto_test`); contraste com `.github/workflows/ci.yml:123` (`DATABASE_URL: postgres://postgres:postgres@localhost:5432`).
- **Cenário:** em `config/database.yml:63-66`, o bloco `test.primary` é `{database: api_ponto_test}` **sem host/username/password**. Ele só alcança o service via `DATABASE_URL` (que o Rails mescla por cima) — exatamente o que o `ci.yml` de GitHub faz e o `.gitlab-ci.yml` **omitiu**. Sem `DATABASE_URL`, o `pg` cai no socket Unix local (inexistente no container do job) e o usuário é `$USER` (irrelevante, pois o socket não existe).
- **Impacto:** medido nesta revisão em container-like (`PGHOST` inválido, sem local socket): `bin/rails db:test:prepare` → **EXIT=1**. Com `DATABASE_URL` apontando ao service → **EXIT=0**. Além disso, `createdb` do `.gitlab-ci.yml` cria **apenas** o espelho (`frequencia_pessoas_espelho_test`); o primário `api_ponto_test` **nunca é criado** — o `db:test:prepare` deveria criá-lo, mas depende de `DATABASE_URL`.
- **Sugestão:** adicionar ao `test` (paridade com o `ci.yml`): `DATABASE_URL: postgres://postgres:postgres@postgres:5432` (host = alias do service, ver B1).

### 🔴 B3 — O `test` não define `PGPASSWORD`; `createdb`/`psql` travam/negam contra o auth `scram-sha-256` do `postgres:17`

- **Arquivo:linha:** `.gitlab-ci.yml:151-183` (script sem `PGPASSWORD`); contraste com `.github/workflows/ci.yml:99-100` (`env: PGPASSWORD: postgres` no passo de criação do banco).
- **Cenário:** a imagem oficial `postgres:17` (usada no `services:`) aplica `host all all all scram-sha-256` (as linhas `trust` de loopback do initdb **não** cobrem a conexão vinda do bridge). Medido nesta revisão contra `postgres:17` real (`pg_hba.conf` confirmado com `scram-sha-256` para `all all all`):
  - `createdb -h localhost -U postgres` **sem** `PGPASSWORD` → imprime `Password:` em loop e **trava** (nunca retorna; job pendura);
  - `psql -h localhost -U postgres ...` sem `PGPASSWORD` → **`fe_sendauth: no password supplied`**;
  - com `PGPASSWORD=postgres` → **EXIT=0**.
- **Impacto:** como o `createdb` foi deliberadamente deixado **sem `|| true`** (decisão elogiada, ver 🟢), o passo **quebra/pendura** o job. O `CREATE ROLE ... 2>/dev/null || true` **não** é a saída: ele usa o mesmo caminho de auth e também trava/nega — não "cobre" o `createdb` falho como afirma o comentário `.gitlab-ci.yml:164-169`.
- **Sugestão:** adicionar `PGPASSWORD: postgres` ao job `test` (o valor é o mesmo do `POSTGRES_PASSWORD`), como faz o `ci.yml`.

> **Raiz comum dos três:** o `test` do GitLab foi validado por partes (schema load, espelho, skips, brakeman) na **máquina local** (que tem Postgres em `localhost:5432` — confirmado aberto) e via `gitlab-ci-local` (que faz forwarding de portas), mas **não end-to-end num GitLab real**. A `iteration_chore` já registra "Suposto (não verificável daqui)" para o runner do TJPI; os três blockers são a materialização desse risco. Recomendação: rodar o job `test` real numa branch de teste antes do merge.

---

## Sugestões de Melhoria (🟡)

| ID | Descrição | Arquivo:linha |
|----|-----------|---------------|
| S1 | `until pg_isready ...; do sleep 1; done` **sem limite de tentativas** → loop infinito até o timeout do job se o Postgres não subir. Usar `--retries`/`timeout` ou o `POSTGRES_SERVICE_HOST`. | `.gitlab-ci.yml:153` |
| S2 | **Dono do `allow_failure` de `quality` está órfão** ("a ratificar pelo coordenador"): prazo (`2026-10-13`) e gatilho binário existem, mas **sem dono nomeado**. O de `security` tem dono + prazo + gatilho. Nomear o dono do débito de lint para não virar papel de parede. | `.gitlab-ci.yml:123`; `iteration_chore_gitlab-ci.md:90` |
| S3 | Detecção por substring (`output.include?(echo)`) além da linha-âncora: se a frase literal ("Notes required for all ignored warnings" / "Obsolete ignore entries were found") aparecer como **dado** no scan (ex.: num comentário do código varrido), o exit é promovido por engano. Risco baixo, mas a âncora `^...` sozinha é estritamente mais segura. | `bin/brakeman:76` |
| S4 | `POSTGRES_HOST`/`POSTGRES_PORT` no job `test` são **decorativos** (não são variáveis libpq; o Rails não os consome). Só confundem — manter o `DATABASE_URL` (B2) e/ou `PGHOST`. | `.gitlab-ci.yml:149-150` |
| S5 | `PESSOAS_DB_DATABASE: ""` (variável de projeto vazia) faz `ENV.fetch` devolver `""` → `database: nil` no ERB (medido). Idempotência recomendada: usar `ENV["..."] || default` ou validar não-vazio. | `config/database.yml:79` |
| S6 | `image: ruby:3.3.8-slim` + `apt-get` exige **root** no executor; o autor **supôs** executor docker como root. Não verificado contra o runner do TJPI (executor shell / usuário não-root quebraria o `before_script`). Confirmar no run real. | `.gitlab-ci.yml:32,71-79` |

## Débitos Técnicos (🟠)

| ID | Descrição | Arquivo:linha |
|----|-----------|---------------|
| D1 | `PESSOAS_DB_PASSWORD: "app"` versionado. Aceitável para runner efêmero; a recomendação de mover para variável de projeto `PESSOAS_DB_PASSWORD` **está registrada** (comentário + `iteration_chore` §Pendências). Não é blocker, é débito com mitigação documentada. | `.gitlab-ci.yml:64` |
| D2 | `bin/rubocop -f github` roda o **mesmo scanner** em `security` e `quality`; os dois são `allow_failure: true` hoje → nenhum bloqueia. Custo de duplicação de `bundle install` por job (sem cache). | `.gitlab-ci.yml:71-79` |
| D3 | Drift de versão do Ruby: `ci.yml`/`.gitlab-ci.yml` pinam `3.3.8` (literal), enquanto `.ruby-version`/`.tool-versions` ainda dizem `ruby-4.0.0`. Registrado como dívida (não alterar `.ruby-version`); o pin literal pode divergir de novo. | `.ruby-version`; `.gitlab-ci.yml:32` |

## Elogios (🟢)

| ID | Elogio | Arquivo:linha |
|----|--------|---------------|
| E1 | **RR-S1 é honesto, não um gate heurístico frágil.** Verificado de forma independente: nota vazia → **EXIT=8**; entrada obsoleta → **EXIT=9**; ledger íntegro → **EXIT=3** preservado. A saída é reemitida verbatim (só se acrescenta 1 linha em stderr); a ordem de avaliação do Brakeman (`exit_on_warn` em `commandline.rb:71/150` antes de `:158`/`:163`) foi confirmada no **source da gem 8.0.5** — o diagnóstico do wrapper está correto. Ledger restaurado com hash idêntico após os testes. | `bin/brakeman:63-123` |
| E2 | **Fail-safe correto:** `rescue StandardError → 1` garante exit **não-zero** (não vira verde-por-engano), preservando o diagnóstico e o backtrace. | `bin/brakeman:97-103` |
| E3 | **`createdb` sem `|| true` + `grep -q 1` de prova de existência** — design anti-masking exemplar; o `allow_failure` nunca entra no `test`. | `.gitlab-ci.yml:164-169,177-183` |
| E4 | **RR-S2 correto:** `ENV.fetch("PESSOAS_DB_DATABASE", "frequencia_pessoas_espelho_test")` — renderizado sob stub (sem `master.key`): ENV ausente → default; ENV setado → redireciona. Blocos `development`/`production` intocados. | `config/database.yml:79` |
| E5 | **`.github/workflows/ci.yml` ajustado com o mínimo necessário** (`ruby-version: .ruby-version` → `'3.3.8'` nos 3 jobs), sem introduzir divergência nova. Pin correto e citado. | `.github/workflows/ci.yml:23,42,81` |
| E6 | **Rastreabilidade excelente:** `iteration_chore_gitlab-ci.md` com dono/prazo/critério binário por stage, prova do fail-fast nos dois sentidos (`gitlab-ci-local`), disclosure explícito do que **não** foi verificado, e distinção correta do que fica fora do stage (credentials/logs/tmp). `lessons.md` com 3 lições concretas. | `dump`, `iteration_chore_gitlab-ci.md`, `lessons.md` |

---

## Falsos positivos refutados (verificados e NÃO são problemas)

1. **"`allow_failure: true` virou papel de parede."** Parcialmente — `security` tem dono + prazo + gatilho binário; `quality` tem prazo + gatilho mas **dono órfão** (S2). A decisão de fundo (fail-fast do GitLab impede `test` de rodar) está **confirmada** pela doc oficial e é a escolha certa; a "ancoragem" é suficiente para `security`, incompleta para `quality`.
2. **"`test` deveria ser duro mesmo (12 erros + 1 falha baseline derrubam o pipeline)."** **Refutado como blocker:** `test` tem `allow_failure` ausente (= `false`, duro) — correto. Os 12 erros + 1 falha são **pré-existentes/baseline** (1 flaky isolado), não regressão desta chore. O job ser duro é desejável; o problema não é a dureza, é que ele **não chega a rodar** (B1–B3).
3. **"A detecção por string pode promover um exit indevidamente (falso 8/9) ou deixar de promover (falso vermelho)."** **Não-promoção: refutada** — provado 8/9 (a ordem real é `exit_on_warn` 71/150 → `ensure_ignore_notes` 163 → obsolete 158; `run_brakeman` precede tudo). Promoção indevida: risco teórico baixo via substring (S3), não observado.
4. **"`rescue StandardError → 1` pode engolir um crash real como 'só' exit 1."** **Refutado:** exit 1 é **não-zero** → quebra o gate; o crash fica visível com classe/mensagem/backtrace. Não gera verde falso.
5. **"`config/credentials.yml.enc` / logs / tmp no bloco."** Confirmado ruído de working tree; `iteration_chore` os exclui do stage, e `master.key` está **untracked** (não versionado) — higiene OK.
6. **"Branch base deveria ser `develop`."** **Refutado:** `develop` não tem as flags anti-drift, o ledger, o passo do espelho nem o `ENV.fetch` (todos só na `feature/demanda-29-...`). Criar de `develop` geraria CI chamando artefatos inexistentes. Desvio correto e registrado.
7. **"Brakeman mudou o `--ensure-latest`."** Confirmado removido e **documentado**; sem ele o exit 3 prova que o scan roda (verificado: relatório presente, 1 warning não-ignorado `EOLRails` + 3 ignorados). Correto.

---

## Métricas medidas de forma independente nesta revisão

| Métrica | Comando | Resultado |
|---|---|---|
| Ruby local / `.ruby-version` | `ruby -v` / `cat .ruby-version` | `3.3.8` / `ruby-4.0.0` (divergem — D3) |
| Brakeman baseline | `bin/brakeman --no-pager` | **EXIT=3** (EOLRails, 1 não-ignorado, 3 ignorados) |
| RR-S1 nota vazia | mutação do ledger | **EXIT=8** ✔ |
| RR-S1 entrada obsoleta | mutação do ledger | **EXIT=9** ✔ |
| RR-S1 ledger íntegro | `bin/brakeman --no-pager` | **EXIT=3** ✔ (hash SHA256 do ledger preservado) |
| RuboCop | `bin/rubocop -f github` | **EXIT=1 / 77 offenses** ✔ |
| RuboCop no binstub | `bin/rubocop bin/brakeman` | **0 offenses** ✔ |
| `db:test:prepare` **sem** `DATABASE_URL` (container-like) | `PGHOST=/nonexistent` | **EXIT=1** (confirma B2) |
| `db:test:prepare` **com** `DATABASE_URL` | `@localhost:5455` (service docker) | **EXIT=0** |
| `createdb` sem `PGPASSWORD` contra `postgres:17` (scram) | `postgres:17` real | **trava** em `Password:` |
| `psql` sem `PGPASSWORD` contra `postgres:17` (scram) | `postgres:17` real | `fe_sendauth: no password supplied` |
| `createdb` com `PGPASSWORD=postgres` | `postgres:17` real | **EXIT=0** |
| YAML do `.gitlab-ci.yml` | `YAML.load_file` | OK; `stages=[security,quality,test]`; `allow_failure` security/quality=`true`, test=`nil` |

**Ambiente:** container `postgres:17` criado por esta revisão e **removido** ao final; ledger `config/brakeman.ignore` restaurado (hash idêntico); nenhum commit/push.

---

## Ações Corretivas (checklist para desbloquear — NÃO implementadas por este revisor)

- [ ] **B1** — Trocar `localhost` pelo alias `postgres` (`pg_isready`, `psql`, `createdb`) e `PESSOAS_DB_HOST`/`POSTGRES_HOST`; confirmar em run real.
- [ ] **B2** — Adicionar `DATABASE_URL: postgres://postgres:postgres@postgres:5432` ao job `test`.
- [ ] **B3** — Adicionar `PGPASSWORD: postgres` ao job `test`.
- [ ] **S1** — Limitar o `until pg_isready` (timeout/retries).
- [ ] **S2** — Nomear o dono do débito de lint (remove a órfandade do `allow_failure` de `quality`).
- [ ] Registrar no `iteration_chore_gitlab-ci.md` a pendência de **1 run real** do job `test` no GitLab do TJPI.

---

<a id="re-review--seção-detalhada"></a>
# 🔁 RE-REVIEW — seção detalhada (2026-09-29)

> **Branch:** `chore/gitlab-ci-fork` (HEAD `73726e1`) · **Merge target:** `feature/demanda-29-schema-gestor-individual`
> **Método:** reprodução independente com **Docker real** (network própria `cr_net`; `postgres:17` com `--network-alias postgres` e **sem `-p`**; job em `ruby:3.3.8-slim` na **mesma rede, sem publicar porta**). Containers e rede **removidos** ao final.

## Veredito do re-review: ✅ APROVADO — B1/B2/B3 fechados, 0 blockers

## 1. Status dos blockers

| ID | Status | Evidência independente desta revisão |
|----|--------|--------------------------------------|
| 🔴 B1 (`localhost` → alias) | ✅ **FECHADO** | Negativo: `pg_isready -h localhost` → `no response`, EXIT=2; `psql -h localhost` → `Connection refused`, EXIT=2. Positivo: `pg_isready -h postgres` → `accepting connections`, EXIT=0; `psql -h postgres` → `inet_server_addr()=172.23.0.2`, EXIT=0. Grep confirma **zero `localhost` em linha executável** (`:67`, `:161`, `:178`, `:201`, `:205`, `:211` usam o alias). |
| 🔴 B2 (`DATABASE_URL`) | ✅ **FECHADO** | `.gitlab-ci.yml:168` = `postgres://postgres:postgres@postgres:5432` (alias — o `ci.yml:123` do GitHub tem a mesma URL, em `localhost`). A sintaxe é a canônica aceita pelo `ActiveRecord::DatabaseConfigurations`; o controle negativo (sem a variável) já dera EXIT=1 na 1ª passada. |
| 🔴 B3 (`PGPASSWORD`) | ✅ **FECHADO** | Sem `PGPASSWORD`: `psql -h postgres` → prompt `Password:` + `fe_sendauth: no password supplied`, EXIT=2. Com `PGPASSWORD=postgres`: EXIT=0. `pg_hba.conf` do `postgres:17` confirmado: `host all all all scram-sha-256`. |

**Achado colateral (B1 estendido ao bloco `pessoas`):** correto. `database.yml:89` lê `ENV.fetch("PESSOAS_DB_HOST", ...)` e `.gitlab-ci.yml:67` = `PESSOAS_DB_HOST: "postgres"`. O autor identificou (e fechou) a mesma falha no bloco `pessoas`, não só no job `test`.

## 2. Comentário falso (`:194-199`) — reescrita verificada, agora EXATA

O texto novo diz que o `|| true` **não** cobre auth/conexão, que ele usa o mesmo caminho (`psql` + `PGPASSWORD`) e que "só absorve o erro idempotente *role already exists*"; a cobertura real é `PGPASSWORD` + `pg_isready` + `createdb -O` em cascata.

- "Só absorve role already exists" — **confirmado** (com `PGPASSWORD` correto, o único erro tolerável do `CREATE ROLE` é a role pré-existente).
- A cascata via `createdb -O` — **confirmada**: `createdb -O nao_existe_role` → `role "nao_existe_role" does not exist`, **EXIT=1** (quebra o step, sem `|| true`).
- **Não afirma nenhuma cobertura inexistente.** ✅

## 3. Achado novo — `default-libmysqlclient-dev` (`:88`)

- **Versão correta para a gem:** `Gemfile.lock` fixa **`mysql2 (0.5.7)`**; o pacote Debian/Ubuntu que fornece os headers do libmysqlclient é `default-libmysqlclient-dev` — **correto** para `mysql2` 0.5.x (não `libmysqlclient-dev`, que no Debian é virtual, nem `mysql-client`).
- **Reproduzido de forma independente:** container `ruby:3.3.8-slim` **limpo**, com exatamente as libs do `before_script`, `bundle install` → **`Bundle complete! 29 Gemfile dependencies, 129 gems now installed`**, **EXIT=0**. As demais gems com extensão nativa (`pg`, `nokogiri`, `bcrypt`, `bootsnap`, `debug`, `msgpack`) têm `precompiled`/extensão coberta por `build-essential`/`libpq-dev`/`libyaml-dev`/`pkg-config`. **Não falta nenhuma dependência de build observável.**
- **A afirmação de que o `ci.yml` de GitHub nunca executou por essa razão é plausível** (o job morria no `ruby-4.0.0` inexistente antes do `bundle install`); a lacuna existia nos **dois** arquivos — o fork a fechou.

## 4. A prova por Docker do autor se sustenta como método? **Sim — com 1 ressalva residual nomeada**

**O método preserva a propriedade sob teste.** O eixo do B1 é: no executor docker do GitLab o job e o service são containers irmãos ligados por uma **rede do Docker** (alias DNS), **sem forwarding de porta** para o `localhost` do job. A prova montada reproduz exatamente isso e, por isso, **expõe** a falha que o `gitlab-ci-local` mascarava (ele publica portas em `localhost` — semântica divergente).

- **Controle negativo legítimo:** `localhost` falhou por **ausência de listener na interface loopback do container do job** (`Connection refused`), **não** por auth — é precisamente a falha prevista pelo B1. O `pg_isready` retornou `no response`/EXIT=2, e não travou: a falha foi reproduzida pelo motivo certo.
- **Controle de B3 (auth) é independente do B1:** `psql -h postgres` sem senha → `fe_sendauth: no password supplied` — a mesma falha de auth ocorreria em `localhost` com o forwarding do `gitlab-ci-local`, ou seja, o B3 é ortogonal ao B1.
- **Varredura de diferenças residuais** (DNS do runner, `FF_NETWORK_PER_BUILD`, irmão-vs-mesmo-container):
  - Serviços por alias: idêntico ("The container running the job and the containers running the service resolve each other's hostnames and aliases").
  - Sem forwarding para `localhost`: idêntico (a doc recomenda explicitamente "connect to the host named `mysql` instead of a socket or `localhost`").
  - `FF_NETWORK_PER_BUILD` só muda a **rede** (uma por job / por build), não a **semântica de alias nem o não-forwarding** → não afeta a conclusão.
  - Propagação de variável do job ao container do serviço: **confirmada na doc oficial** — "The following variables are automatically passed down to the Postgres container" (fonte GitLab, `doc/ci/services/_index.md:251-261`). Logo o `POSTGRES_PASSWORD: postgres` de **nível de job** (`:158`) chega ao container do serviço e a role `postgres` nasce de fato — a premissa da prova é a do GitLab real, **não um artefato do docker run**.

**Ressalva residual (não invalida; registrada para honestidade):** a própria doc diz que `FF_NETWORK_PER_BUILD` é necessário para rede **inter-service**; para o caso *job → service* basta o alias, então o teste com rede compartilhada é fiel. O único ponto **não reproduzível fora do TJPI** permanece o runner self-hosted (executor, registry, políticas de instância) — **hipótese S6** da 1ª passada, novamente não-falsificável localmente.

## 5. Métricas medidas nesta re-review (reprodução independente)

| Métrica | Comando (container do job `ruby:3.3.8-slim`, rede `cr_net`, sem `-p`) | Resultado |
|---|---|---|
| B1 negativo | `pg_isready -h localhost -p 5432 -U postgres` | `no response`, **EXIT=2** ✔ |
| B1 negativo | `psql -h localhost -U postgres ...` | `Connection refused`, **EXIT=2** ✔ |
| B1 positivo | `pg_isready -h postgres -p 5432 -U postgres` | `accepting connections`, **EXIT=0** ✔ |
| B1 positivo | `psql -h postgres ... "select inet_server_addr()"` | `172.23.0.2`, **EXIT=0** ✔ |
| B3 controle | `psql -h postgres ...` sem `PGPASSWORD` | `fe_sendauth: no password supplied`, **EXIT=2** ✔ |
| B3 positivo | `psql -h postgres ...` com `PGPASSWORD=postgres` | **EXIT=0** ✔ |
| `pg_hba.conf` | `postgres:17` | `host all all all scram-sha-256` ✔ |
| Sequência do job `test` | `pg_isready` → `CREATE ROLE` → `createdb` → `grep -q 1` | **EXIT=0 / 0 / 0 / 0** ✔ |
| Cascata do `|| true` | `createdb -O nao_existe_role` | `role does not exist`, **EXIT=1** ✔ (quebra o step) |
| `bundle install` limpo | `ruby:3.3.8-slim` + libs do `before_script` | **Bundle complete! 129 gems**, **EXIT=0** ✔ |
| `localhost` executável | `grep -n localhost .gitlab-ci.yml` (fora de comentário) | **nenhum** ✔ |
| YAML | `YAML.load_file` | `stages=[security,quality,test]`; `allow_failure` security/quality=`true`, test=`nil` ✔ |

**Ambiente/limpeza:** containers `cr_pg`/`cr_ruby`/`cr_build` e rede `cr_net` **removidos**; `/tmp/crbuild` limpo; ledger `config/brakeman.ignore` intocado; **nenhum commit/push**.

- **Blockers:** 0 · **Sugestões novas:** 0 · **Achados adversariais novos:** 0 (a bisseção de gem provou o `mysql2` como **única** falha de build — por isso o `bundle install` tinha de abortar, e com o pacote passa).

## 6. Falsos positivos refutados (re-review)

1. **"A prova por Docker é um artefato de `docker run`, não do GitLab (a senha não chega ao service)."** **Refutado:** a doc oficial do GitLab ("Passing CI/CD variables to services") afirma literalmente que as variáveis de nível de job são *"automatically passed down to the Postgres container"* — o `POSTGRES_PASSWORD: postgres` de `:158` chega ao serviço. A prova do autor preserva a propriedade.
2. **"O controle negativo do B1 falhou por auth (senha), não por ausência de host — logo não prova o B1."** **Refutado:** `localhost` falhou com `Connection refused`/`no response` (nada escutando no loopback) **antes** de qualquer auth; a falha de auth só aparece no controle **B3**, deliberadamente separado.
3. **"`default-libmysqlclient-dev` é pacote errado / falta outra lib."** **Refutado:** `bundle install` completo em `ruby:3.3.8-slim` limpo → EXIT=0, pode a lista de libs do `before_script`, contra `mysql2 (0.5.7)` travado no lock.
4. **"`allow_failure` do `test` foi enfraquecido."** **Refutado:** `test` segue `allow_failure: nil` (= duro); só `security`/`quality` seguem `true`, com dono+prazo+gatilho (a órfandade do dono de `quality` foi fechada — `chore/limpeza-rubocop-77`, S2 resolvido).
5. **"O comentário novo do `|| true` ainda superestima a cobertura."** **Refutado:** o texto é exato (seção 2 acima); não atribui ao `|| true` nenhuma cobertura de auth/conexão e nomeia as três coberturas reais em cascata.

## 7. O que ainda impede o merge

**Nada de código.** B1/B2/B3 fechados; S2 resolvido; as sugestões S1 (`pg_isready` sem timeout — `:178`) e S4 (`POSTGRES_HOST`/`POSTGRES_PORT` decorativos — `:161-162`) permanecem como **notas não-bloqueantes** (modo AGILE).

**Único item em aberto (ambiental, recomendado antes do merge):** o **1 run real** do job `test` no runner do TJPI — o ambiente self-hosted não é reproduzível fora da rede da instituição (hipótese S6). A cadeia docker foi reproduzida de ponta a ponta e valida o *conteúdo* do job; resta confirmar o *executor* (root para `apt-get`, política de `allow_failure` da instância, registry). Como o `test` é atualmente frágil (12 erros + 1 falha baseline), o primeiro run real **falhará** até o baseline ser tratado — **esperado e não-regressão desta chore**.

## 8. Ações pendentes (re-review)

- [x] B1 — `localhost` → alias `postgres` — **fechado**
- [x] B2 — `DATABASE_URL` com o alias — **fechado**
- [x] B3 — `PGPASSWORD: postgres` — **fechado**
- [x] Comentário falso do `|| true` — reescrito e exato
- [x] `default-libmysqlclient-dev` no `before_script` — correto e verificado
- [x] S2 — dono do débito de lint nomeado (`chore/limpeza-rubocop-77`)
- [ ] (recomendado, não bloqueante) **1 run real** do job `test` no GitLab do TJPI
- [ ] (nota S1, não bloqueante) limitar o `until pg_isready` com timeout/retries
- [ ] (nota S4, não bloqueante) remover/redirecionar `POSTGRES_HOST`/`POSTGRES_PORT` decorativos

> **Status do bloco:** ✅ Implementado, ✅ **Aprovado** (re-review). 0 blockers. Merge para `feature/demanda-29-schema-gestor-individual` liberado do ponto de vista de código, pendente da validação ambiental do runner.
