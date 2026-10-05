# Relatório de Revisão — Bloco de Esteira (CI/pipeline), Sprint 29

> **Revisor:** Code Reviewer | **Data:** 2026-09-29
> **Branch:** `feature/demanda-29-schema-gestor-individual` (não commitado)
> **Origem → Destino:** working tree → stage seletivo (commit manual)
> **Veredito:** ❌ **COM BLOCKERS** — 1 Blocker 🔴 (CI quebrado como escrito) + 2 Sugestões de melhoria 🟡

---

## 1. Metadados

| Item | Valor |
|------|-------|
| Arquivos no escopo | `api-ponto/bin/brakeman`, `api-ponto/.github/workflows/ci.yml`, `api-ponto/config/database.yml` (bloco `pessoas` de test), `api-ponto/test/support/pessoas_espelho_helper.rb`, 3 arquivos de teste (`setup { skip_sem_espelho! }`), `docs/governance/lessons.md`, `docs/progress/iteration_29.md` |
| Fora do escopo (não entram no stage) | `config/credentials.yml.enc`, `log/*.log`, `tmp/cache/*` — ruído de working tree (higiene OK, já rastreada) |
| Ambiente de repro | Postgres `17`/`16-alpine` oficial em container Docker (idêntico ao `services: postgres` do CI) |
| Métodos | Inspeção do `railties`/`activerecord` 8.0.5 do bundle; execução do workflow passo a passo contra o container; execução dos testes do espelho no ambiente do dev |

## 2. Achados por Severidade

### 🔴 Blocker B1 — O CI **não consegue preparar o espelho como escrito** (falha no próprio passo de setup)

**Arquivo:** `api-ponto/.github/workflows/ci.yml:86-120` (passo "Create the Pessoas mirror test database" + `Run tests`) combinado com `api-ponto/config/database.yml:80-83`.

**Cenário reproduzido (container oficial `postgres:17`, mesma config do CI):**
1. As credenciais `pessoas_db` do `~/.credentials` do dev não existem no CI. A `ENV.fetch("PESSOAS_DB_USERNAME", credentials)` resolve para o valor de `PESSOAS_DB_USERNAME: app.frequencia` (`ci.yml:113`).
2. `PESSOAS_DB_PASSWORD: ""` (`ci.yml:114`) e `PESSOAS_DB_HOST: localhost` (`ci.yml:111`).
3. A imagem oficial do Postgres define `POSTGRES_HOST_AUTH_METHOD=scram-sha-256` por default. O `pg_hba.conf` **efetivo** no runner é:
   ```
   ... linhas de initdb (trust, loopback) — SUBSTITUÍDAS pelo entrypoint ...
   host all all all scram-sha-256
   ```
   O entrypoint da imagem official **remove** as linhas `trust` de loopback e escreve `host all all all scram-sha-256`. Conexões de `localhost` a partir do runner chegam com `inet_client_addr() = 172.17.0.1` (bridge), atingindo a linha **scram**.
4. A role `app.frequencia` é criada **sem senha** (`CREATE ROLE ... LOGIN`, `ci.yml:92` — `CREATE ROLE` sem `PASSWORD` cria `rolpassword = NULL`).
5. Resultado executado:
   ```
   $ psql -h localhost -U app.frequencia -d frequencia_pessoas_espelho_test   (PGPASSWORD="")
   fe_sendauth: no password supplied
   $ PGPASSWORD="wrongpw" ...  →  FATAL: password authentication failed for user "app.frequencia"
   ```
   A mensagem **"no password supplied"** (e não "empty password") prova que o Postgres **exige senha** nesta rota — não é trust.

**Fluxo do `Run tests`** (`ci.yml:117-120`):
- `bin/rails db:test:prepare` → **passa** (só toca `primary`).
- `bin/rails test:pessoas_schema:load` → **ABORTA** com
  `ActiveRecord::ConnectionNotEstablished: connection to server at "127.0.0.1", port 5432 failed: fe_sendauth: no password supplied` (**EXIT=1**, reproduzido).
- `set -e` do shell `bash` padrão do GitHub Actions faz o passo falhar → job `test` **vermelho**.

**Ponto de atenção conjunta:** o `PESSOAS_DB_PASSWORD: ""` parece ter sido **copiado da máquina do dev**, onde o `.pg_hba.conf` local tem regra `trust` no loopback (por isso o dev conecta com `app.frequencia` sem senha). O CI **não tem** essa regra `trust` no caminho de rede usado. O herdado "app connecta sem senha" **não se transfere** para o CI.

**Impacto / interpretação do veredito:** este blocker **não é um falso-verde** — o `skip_sem_espelho!` existe justamente para que, quando a conexão falha, os testes do espelho sejam **pulados** em vez de explodir. Só que aqui o `test:pessoas_schema:load` **quebra antes**, no passo de setup, então o job falha **duro** (não fica verde com 19 skips). Ou seja: a correção do falso-verde está **logicamente correta** (a checagem `grep -q 1` sem `|| true` propaga o exit code), mas o CI **não chega ao fim** — falha por um motivo de autenticação que o autor não previu. Entre "verde falso" e "vermelho por setup quebrado", este é **vermelho por setup quebrado**.

**Sugestões de correção (não implementadas — aguardam o dev):**
- (a) Dar senha à role e usá-la: `CREATE ROLE "app.frequencia" LOGIN PASSWORD 'app'` no `ci.yml` e `PESSOAS_DB_PASSWORD: app`; **ou**
- (b) `services.postgres.options` com `--health-cmd` já existe — adicionar `POSTGRES_HOST_AUTH_METHOD: trust` ao `services.postgres.env` (aceitável em runner efêmero; a imagem passa a usar `host all all all trust`); **ou**
- (c) Trocar `host: localhost` por um caminho que caia na regra `trust` do loopback — **não** é viável no CI (o runner não compartilha o namespace de rede do container); a opção (b) é a mais simples.
- Recomendo re-validar o passo contra um container após a correção: **a atual "correção do falso-verde" nunca foi executada num runner** — foi raciocinada.

### 🟡 Melhoria M1 — `docker exec`/loopback não testado; a validação do dev usou o pg_hba local, não o do CI

**Arquivos:** `ci.yml:92` (`CREATE ROLE ... LOGIN` sem senha) e `ci.yml:114` (`PESSOAS_DB_PASSWORD: ""`).
**Cenário:** a validação relatada em `iteration_29.md` ("sem ENV conecta como `davi.araujo`; com ENV o usuário passou a ser o da variável") foi feita **na máquina do dev**, onde o `.pg_hba.conf` local é `trust` no loopback. Isso **não exercita** a rota de rede nem a auth do runner.
**Sugestão:** adicionar ao protocolo de validação de esteira o passo "rodar a sequência `createdb` + `test:pessoas_schema:load` dentro de um container `postgres` oficial", que é o que este relatório fez. Sem isso, mudanças de auth do Postgres passam despercebidas até o primeiro push.

### 🟡 Melhoria M2 — `bin/brakeman` agora falha o CI por **3 warnings `Weak` legítimos** (`scan_ruby` fica vermelho)

**Arquivo:** `api-ponto/bin/brakeman:5` (remoção do `--ensure-latest`).
**Verificação executada:** `bin/brakeman --no-pager` → **EXIT=3**:
- `app/controllers/admin/frequencia_por_orgao_controller.rb:71` e `:72` — SQL com `#{coluna}` interpolado (interpolação de método privado controlado, não de `params`; risco baixo mas real).
- `app/helpers/application_helper.rb:33` — `eval(code)` (Weak).

**Impacto:** não há `.brakeman.ignore` nem `config/brakeman.yml` no repo, então **nenhum** warning é suprimido. Com o binstub corrigido, o job `scan_ruby` (`ci.yml:22-23`) passa de verde-por-omissão para **vermelho** — em CI *e* em push para `main`. A correção do no-op está tecnicamente correta ("exit 0 sozinho não prova execução"), mas o efeito imediato é **o CI quebrar no job de segurança**, por 3 achados que o autor registra como **pré-existentes e não-da-29.2**.
**Sugestão:** decidir de forma explícita (default de decisão, não de código): ou (i) `.brakeman.ignore` com os 3 fingerprints + justificativa classificando-os como aceitos/pré-existentes; ou (ii) `bin/brakeman --no-exit-on-warn` mantendo o relatório visível sem quebrar o gate; ou (iii) corrigir o `#{coluna}` com uma allowlist explícita de colunas. **Nota:** o `--no-exit-on-warn` reintroduz o risco de "gate que passa sem escanear" — se escolhido, precisa vir acompanhado de um assert de que o scan rodou (ex.: `--ensure-no-warnings` não existe; avaliar `--compare`/saída não-vazia).

### 🟢 Elogio E1 — A correção do falso-verde está **logicamente correta**

O `ci.yml:96-97` (`psql -tAc "SELECT 1 WHERE datname..." | grep -q 1`) **propaga o exit code** e **falha o passo** quando o banco não existe — confirmado: `grep` retorna 0 com o banco presente, e o `set -e` do GH Actions quebra o passo em exit≠0. O único `|| true` restante está na idempotência da role (`ci.yml:92`, legítimo: role pré-existente) e no `createdb` (`ci.yml:93` — tolerável **se** a checagem seguinte ficar); **não há `continue-on-error`** em nenhum job. A intenção declarada no comentário ("SEM `|| true`... o CI tem de FALHAR") **é o que o código faz**.

### 🟢 Elogio E2 — `skip_sem_espelho!` é honesto (skip, não pass; não engole falha de teste)

`pessoas_espelho_helper.rb:73-85`: `espelho_disponivel?` rescata `ActiveRecord::ActiveRecordError, PG::Error` e retorna `false` → `skip "espelho Pessoas indisponível — ..."`. É um `skip` legítimo (aparece como `S` no relatório, não como `.`), com motivo acionável. (Detalhe: `PG::Error < StandardError`, **não** é subclasse de `ActiveRecord::ActiveRecordError`; listar ambos é redundante mas inofensivo.) Executado no dev com o banco presente: **19 runs, 68 assertions, 0 failures, 0 errors, 0 skips** — o caminho de skip **não** dispara quando o banco existe, ou seja, não mascara execução.

### 🟢 Elogio E3 — Precedência ENV × credentials verificada nos dois sentidos

`config/database.yml:80-83`: com `include_hidden: true`, a config `pessoas` de test resolveu para `user="davi.araujo"` (credentials) na máquina do dev, **sem** as ENV; e no ambiente com `PESSOAS_DB_USERNAME=app.frequencia` o usuário resolvido passou a ser o da variável. A sobreposição funciona. O bloco de **development** (`:37-49`) e o de **production** (`:136-148`) **não foram tocados** — a mudança ficou restrita ao bloco de test, o que é **intencional e coerente**: em dev/prod o `master.key` existe e as credentials são a fonte; em CI o override é necessário. `git diff` confirma escopo restrito.

### 🟢 Elogio E4 — Higiene e consistência com a doc

- Nenhum segredo/log/tmp no bloco de esteira; `bin/brakeman` e `database.yml` são os únicos arquivos de config alterados, ambos legítimos.
- `ci.yml` segue os passos do `README.md:20-33` (`createdb -O app.frequencia` → `test:pessoas_schema:load` → `bin/rails test`).
- `lessons.md` (2 lições novas) descreve com precisão o que o código faz — **ressalva:** a lição "verificado nos dois sentidos" foi verificada **no pg_hba local (trust)**, não no do CI (é a mesma lacuna da M1).
- YAML do `ci.yml` válido.

## 3. Falsos Positivos Refutados (suspeita → execução provou não ser problema)

| Suspeita inicial | Resultado da execução |
|---|---|
| **FP1** — "`createdb || true` engole falha e o CI fica verde com 19 skips" | **Refutado.** A checagem `psql ... | grep -q 1` sem `|| true` propaga o exit code; o passo falha se o banco não existir. O `skip_sem_espelho!` só entra depois; com o banco presente, 0 skips. O falso-verde original **está fechado**. |
| **FP2** — "`credentials.dig` na máquina do dev devolve `nil` (blob 832B × master.key 32B)" | **Refutado.** `Rails.application.credentials` funciona no dev: a config `pessoas` resolve `user="davi.araujo"`. No CI (sem `master.key`) `Rails.env` não é `production` e `config.require_master_key` é `false` (default), então `credentials.dig` → `nil` **sem** levantar exceção — o fallback para ENV é seguro. O raciocínio do autor procede. |
| **FP3** — "`db:test:prepare` apaga/carrega o banco do espelho" | **Refutado.** `db:test:prepare` invoca `DatabaseTasks.prepare_all`; `initialize_database` retorna cedo quando `db_config.database_tasks` é `false` (a config do espelho tem `database_tasks: false`). O `db:test:prepare` **não** toca o espelho — execução no container confirmou (exit 0, sem erro). |
| **FP4** — "`skip_sem_espelho!` mascara falha legítima de teste" | **Refutado.** Com o banco presente o skip **não** dispara (19/68/0, 0 skips). Só pula quando a conexão falha ou a tabela `pessoas` não existe. |
| **FP5** — "`espelho_disponivel?` rescata exceção ampla demais e esconde bug" | **Refutado parcialmente.** O rescue só cobre **abertura de conexão / existência de tabela**; um erro dentro de um teste genuíno não passa por esse caminho (é exceção de teste, não do helper). Listar `PG::Error` junto de `ActiveRecordError` é redundante, não perigoso. |

## 4. Ações Corretivas (checklist para desbloquear a entrega)

- [ ] **B1 (blocker):** corrigir a autenticação do banco do espelho em CI — opção (a) role com senha + `PESSOAS_DB_PASSWORD`, ou (b) `POSTGRES_HOST_AUTH_METHOD: trust` no `services.postgres.env`. **Re-validar contra um container oficial antes do commit.**
- [ ] **M2:** decidir o veredito dos 3 warnings `Weak` do Brakeman (`.brakeman.ignore` justificado, ou `--no-exit-on-warn` com assert de execução, ou fix do `#{coluna}`); documentar em `iteration_29.md`.
- [ ] **M1:** registrar em `lessons.md` que validação de esteira tem de ser feita **no container**, não na máquina do dev (o `pg_hba` local engana).

## 5. O que (não) impede o commit do bloco

- **Impede:** B1 — o CI, como está, **vermelho** no job `test` (o passo `test:pessoas_schema:load` aborta com `ConnectionNotEstablished`). Commitar assim entrega uma esteira quebrada.
- **Atenção (não impede commit, mas quebra o CI no push):** M2 — `scan_ruby` fica vermelho com os 3 warnings `Weak`.
- **Não impede:** higiene do stage, `skip_sem_espelho!`, precedência ENV, escopo do `database.yml`, consistência com o README.

## 6. Métricas Medidas

| Métrica | Valor |
|---|---|
| Testes do espelho/test-lib (dev, banco presente) | **19 runs, 68 assertions, 0 failures, 0 errors, 0 skips** |
| `bin/brakeman --no-pager` | **EXIT=3**, 3 warnings `Weak` (SQL 71/72, eval application_helper:33) |
| `test:pessoas_schema:load` em container CI (env exato do CI) | **EXIT=1** — `ConnectionNotEstablished: fe_sendauth: no password supplied` |
| `db:test:prepare` em container CI | EXIT=0 (não toca o espelho — `database_tasks: false`) |
| `psql ... | grep -q 1` (checagem do banco) | exit 0 com o banco presente (propaga corretamente) |
| YAML do `ci.yml` | válido |
| `continue-on-error` / `|| true` que engolem falha | nenhum (`|| true` só na idempotência da role/reuso do `createdb`) |

---
---

# 🔁 RE-REVIEW — Bloco de Esteira (CI/pipeline), Sprint 29

> **Revisor:** Code Reviewer | **Data do re-review:** 2026-09-29
> **Branch:** `feature/demanda-29-schema-gestor-individual` (não commitado)
> **Origem → Destino:** working tree → stage seletivo (commit manual, `COMMIT_MODE=manual`)
> **Escopo do re-review:** fechamento de **B1** (blocker) e **M2** (ruled pelo CTO); M1 atendida; higiene de stage.
> **Veredito do re-review:** ✅ **SEM BLOCKERS** — B1 fechado (provado por execução); M2 correto e honesto; 2 apontamentos não-bloqueantes (1 🟡 melhoria, 1 🟠 débito).
> **Commit do bloco de esteira: 🔓 LIBERADO** (stage seletivo — ver §RE-4).

## RE-1. Método

Tudo revalidado **por execução**, não por leitura do relato do Code Specialist:

- **B1:** container oficial `postgres:17` (imagem idêntica ao `services: postgres` do `ci.yml`), com o env exato do CI, lido pelo caminho de rede do runner (porta publicada → bridge).
- **M2:** `bin/brakeman --no-pager` no bundle real (Brakeman 8.0.5 / Rails 8.0.5); flags anti-drift provadas por **mutação** do ledger em cópias temporárias (`-i /tmp/...`), sem tocar o artefato revisado.
- **Higiene:** `git diff --stat`, `git ls-files --error-unmatch`, `git check-ignore`.

## RE-2. B1 — ✅ FECHADO (provado por execução)

**Correção aplicada** (`ci.yml:101-113` / `ci.yml:121-128`): role criada com senha → `CREATE ROLE "app.frequencia" LOGIN PASSWORD 'app'`; `Run tests` usa `PESSOAS_DB_USERNAME: app.frequencia` + `PESSOAS_DB_PASSWORD: app`.

**Provas executadas (container `postgres:17`, env do CI):**

| Passo | Comando | Resultado |
|---|---|---|
| `pg_hba` efetivo (não-comentado) | `grep -vE '^\s*#' /var/lib/postgresql/data/pg_hba.conf` | termina em `host all all all scram-sha-256` — as linhas `trust` de loopback do initdb **permanecem**; a linha `scram` cobre a rota de rede. Confirma a mecânica da B1. |
| rota usada pelo runner | `psql -h localhost -p <porta> -U postgres -tAc "SELECT inet_client_addr()"` | **`172.17.0.1`** → cai na linha `scram`, **não** no loopback `trust`. |
| `CREATE ROLE ... PASSWORD 'app'` | idêntico ao `ci.yml` | `CREATE ROLE`; `pg_authid.rolpassword IS NOT NULL = t`. |
| auth **com** senha (`PESSOAS_DB_PASSWORD=app`) | `PGPASSWORD=app psql -h localhost -U app.frequencia -d frequencia_pessoas_espelho_test` | `current_user = app.frequencia`, **exit 0** — o fix funciona. |
| auth com senha **vazia** (estado antigo) | `PGPASSWORD="" psql ...` | `fe_sendauth: no password supplied`, exit 2 — reprodução da falha original. |
| `db:test:prepare` (app real, env do CI) | `bin/rails db:test:prepare` | **EXIT=0**. |
| `test:pessoas_schema:load` (app real, env do CI) | `bin/rails test:pessoas_schema:load` | `Pessoas mirror test schema loaded into frequencia_pessoas_espelho_test`, **EXIT=0**. |
| testes do espelho (app real, mesmo env) | `bin/rails test test/lib/pessoas_espelho_helper_test.rb test/models/pessoas_pessoa_test.rb test/models/pessoas_unidade_test.rb` | **19 runs, 68 assertions, 0 failures, 0 errors, 0 skips** (exit 0). |

**Gate anti-falso-verde preservado:** a checagem `psql ... -tAc "SELECT 1 FROM pg_database WHERE datname=..." | grep -q 1` **sem** `|| true` continua na linha `ci.yml:107`. Provado nos dois sentidos: banco presente → `grep` exit 0 (passo segue); banco inexistente → `grep` exit 1 (com `set -e` do GH Actions, o passo **quebra**). Os únicos `|| true` do arquivo são os dois legítimos de idempotência (`CREATE ROLE`, linha 101; `createdb`, linha 102) e **não** engolem falha real — a checagem seguinte cobre a inexistência do banco. Nenhum `continue-on-error`/`allow_failure` no workflow.

> **Nota factual (correção de imprecisão do relatório original):** o relatório anterior afirmava que o entrypoint da imagem oficial "remove as linhas `trust` de loopback". A leitura do `pg_hba` efetivo **refuta** isso — as linhas `trust` de loopback permanecem; a linha `host all all all scram-sha-256` é **acrescentada** ao final. A conclusão da B1 segue correta (a conexão do runner chega como `172.17.0.1` e cai no `scram`), mas a justificativa mecânica precisa era essa.

## RE-3. M2 — ✅ CORRETO E HONESTO (provado por execução)

- **Ledger só com `Weak`:** `config/brakeman.ignore` contém exatamente **3** entradas, todas `Weak` (SQL `frequencia_por_orgao_controller.rb:71` e `:72`; `Dangerous Eval` `application_helper.rb:33`). O `Medium` `EOLRails`/`Unmaintained Dependency` (`Gemfile.lock:245`) **não** está no ledger — conforme o ruling. `brakeman_version: 8.0.5`.
- **`note` obrigatória e presente:** as 3 entradas têm `note` não-vazia (citando motivo, origem/caller, veredito "pré-existente/aceito", data e débito).
- **Flags anti-drift funcionam (provas por execução):**
  - `--ensure-no-obsolete-ignore-entries` → entrada com fingerprint inexistente → **EXIT=9** (`[Error] Obsolete ignore entries were found, exiting with an error code.`). Provado de forma isolada (ledger com todos os warnings cobertos, incluindo o `EOLRails` temporário → control `EXIT=0`).
  - `--ensure-ignore-notes` → nota **vazia** → **EXIT=8** (`[Error] Notes required for all ignored warnings when --ensure-ignore-notes is set.`), também isolado (control `EXIT=0`).
- **Sem regressão de flags proibidas:** `bin/brakeman` (linhas de código, não comentário) injeta **apenas** `--ensure-ignore-notes` e `--ensure-no-obsolete-ignore-entries`. **Não** há `--ensure-latest`, `--no-exit-on-warn` nem `-x EOLRails`. Não existe `config/brakeman.yml`.
- **Estado final do gate:** `bin/brakeman --no-pager` → **EXIT=3**, `Security Warnings: 1` (EOLRails Medium) / `Ignored Warnings: 3`. Bate exatamente com o previsto pelo ruling.

**🟡 RE-M2.1 (melhoria, não-bloqueante) — o exit 8 é frágil para `note` *ausente* (só dispara para *vazia*).**
Provado: com a chave `note` **removida** do JSON, o Brakeman 8.0.5 quebra em `NoMethodError: undefined method 'strip' for nil` (`lib/brakeman/report/ignore/config.rb:98`) e sai **EXIT=1**, não 8. Com `note: ""` ou `"   "` sai **EXIT=8** corretamente. Efeito prático: **o gate continua falhando** (fail-safe, nunca verde-por-engano), mas com código errado e stack trace em vez da mensagem prescrita pelo ruling — o que dificulta o diagnóstico. O ledger atual tem as 3 notas como string não-vazia, então o defeito é **latente** (manifesta-se só se alguém editar o ledger removendo a chave em vez de esvaziá-la). Sugestão: registrar em `lessons.md` ("`--ensure-ignore-notes` cobre nota vazia; nota **ausente** crash-a o Brakeman 8.0.5 com exit 1 — manter a chave sempre presente") ou validar o JSON do ledger no binstub.

## RE-4. Ponto crítico independente — o `scan_ruby` entregue ainda fica vermelho

**Avaliação pedida:** o commit do bloco de esteira entrega um `scan_ruby` que ainda sai vermelho no push (EXIT=3 pelo `Medium` `EOLRails`)? Isso é aceitável?

**Veredito: SIM, o commit está liberado, e a posição do CTO se sustenta.** Justificativa medida:

1. **O gate de hoje já não roda no ambiente de produção.** O `ci.yml` é GitHub Actions com `ruby-version: .ruby-version` → **`ruby-4.0.0` (inexistente)**; o job `scan_ruby` (e o `test`/`lint`) **não executa** sequer no GitHub. E não existe `.gitlab-ci.yml` (verificado), apesar de a produção ser GitLab. Ou seja: o vermelho do `Medium` é **teórico** — nenhum runner real o produz hoje. Não faz sentido bloquear o commit por um vermelho que não ocorre até a chore do fork do CI existir.
2. **Atualizar o Rails para ≥ 8.1.x é pré-condição, não parte deste bloco.** O `Medium` é um *time bomb* (EOL 2026-10-07) deliberadamente **fora** do ledger; bump de framework é chore de stack com risco próprio, corretamente separada. Misturá-lo aqui seria mudança de escopo e de risco.
3. **O bloco entrega uma melhoria líquida e verificada, independentemente do `Medium`:** sai de "gate que **passa sem escanear**" (`--ensure-latest` com exit 0 sem saída) para "scan real + ledger auditável com anti-drift". O `EXIT=3` **é a prova de que o scan roda** (antes era `EXIT=0` com saída vazia). Trocar um falso-verde silencioso por um scan honesto que reporta 1 débito real de dependência é uma troca **desejável**.
4. **O débito está registrado e acoplado ao fork:** `iteration_29.md` (Riscos, §Ruling M2 §5/§7) registra "bump Rails ≥ 8.1.x" e amarra a definição de verde à paridade no `.gitlab-ci.yml`. Ressalva: a rastreabilidade do débito depende de o `iteration_29.md` (ainda **não commitado**) entrar no mesmo stage — ver RE-5.

**Blocante para produção (não para o commit):** enquanto o `.gitlab-ci.yml` não existir, a 29.0/29.4/29.6 **não fecha a definição de pronto em produção** — já registrado explicitamente em `iteration_29.md`. Isso é chore do CTO, não bloqueia o commit do bloco.

## RE-5. Higiene de stage — ✅ conferida

**Escopo mínimo correto a commitar (8 arquivos, 2 repos):**
- `api-ponto/.github/workflows/ci.yml` (B1)
- `api-ponto/bin/brakeman` (M2)
- `api-ponto/config/brakeman.ignore` (M2 — **untracked; precisa de `git add` explícito**, `check-ignore` confirma que não é ignorado)
- `api-ponto/config/database.yml` (B1, `ENV.fetch` do bloco `pessoas` de test)
- `api-ponto/test/support/pessoas_espelho_helper.rb` + `api-ponto/test/lib/pessoas_espelho_helper_test.rb` + `api-ponto/test/models/pessoas_pessoa_test.rb` + `api-ponto/test/models/pessoas_unidade_test.rb` (guardas `setup { skip_sem_espelho! }`)
- `docs/governance/lessons.md` (M1 + 2 lições) e `docs/progress/iteration_29.md` (ruling M2 + registro do review)

**Deve ficar FORA (ruído de working tree, todos TRACKED mas sem relação com a esteira):** `config/credentials.yml.enc` (blob re-cifrado localmente — **não commitar**; `master.key` não é versionado, o blob do CI é o do repo), `log/development.log` (~2k linhas), `log/test.log` (~295k linhas), `tmp/cache/bootsnap/load-path-cache` (binário). Estão **modificados mas não staged**; um `git add -A` os commitaria — a diretriz "stage seletivo, nunca `git add -A`" continua valendo.

**Sem efeitos colaterais das edições paralelas:** nenhum arquivo não relacionado à esteira foi alterado (o diff bate com o escopo do bloco + docs). `git check-ignore -v config/brakeman.ignore` → não ignorado (entra no stage).

## RE-6. Ações corretivas

- [x] **B1** — fechado; provado end-to-end em `postgres:17` (EXIT 1 → 0).
- [x] **M1** — lição registrada em `lessons.md` (validação de esteira no container, não no `pg_hba` local).
- [x] **M2** — ledger + flags implementados conforme o ruling; exit 8/9 provados; `Medium` fora do ledger.
- [ ] **(não-bloqueante) 🟡 RE-M2.1** — documentar/tratar o crash do exit 8 para `note` ausente (`lessons.md` ou validação no binstub).
- [ ] **(não-bloqueante) 🟠 RE-D1** — chore do **fork do CI**: criar `.gitlab-ci.yml` (security/quality/test) **com o passo do banco do espelho** (senão o B1 não vale em produção) + bump do Rails ≥ 8.1.x.

## RE-7. Falsos positivos refutados no re-review

| Suspeita | Resultado |
|---|---|
| "O ledger contém o `Medium` ou o gate ficou verde por decreto" | **Refutado.** 3 entradas, todas `Weak`; `bin/brakeman` retorna **EXIT=3** — o `Medium` segue vermelho. |
| "As flags anti-drift são decorativas" | **Refutado.** Mutação de ledger provou **EXIT=9** (entrada obsoleta) e **EXIT=8** (nota vazia). |
| "Reintroduziram `--ensure-latest`/`--no-exit-on-warn`/`-x EOLRails`" | **Refutado.** Só as 2 flags anti-drift no ARGV; nenhum `config/brakeman.yml`. |
| "Algum `|| true` novo engole falha real" | **Refutado.** Só os 2 da idempotência; a checagem `grep -q 1` sem `|| true` cobre a inexistência do banco. |
| "`credentials.yml.enc`/`log`/`tmp` entraram no stage" | **Refutado.** Modificados mas não staged; precisam ser deliberadamente deixados de fora. |

## RE-8. Métricas medidas no re-review

| Métrica | Valor |
|---|---|
| `test:pessoas_schema:load` (app real, container, env do CI) | **EXIT=0** |
| `db:test:prepare` (container) | **EXIT=0** |
| Testes do espelho (app real, container) | **19 runs / 68 assertions / 0 failures / 0 errors / 0 skips** |
| `bin/brakeman --no-pager` (estado final) | **EXIT=3** — 1 warning (EOLRails Medium) / 3 ignorados (Weak) |
| Anti-drift: nota vazia / entrada obsoleta | **EXIT=8** / **EXIT=9** (control EXIT=0) |
| Anti-drift: nota **ausente** | EXIT=1 (`NoMethodError` no Brakeman 8.0.5) — 🟡 RE-M2.1 |
| `inet_client_addr()` do runner → container | `172.17.0.1` (rota `scram`) |
| YAML do `ci.yml` | válido (jobs `scan_ruby`/`lint`/`test`; `on: [pull_request, push]`) |
| `continue-on-error`/`allow_failure` | nenhum |
| `.gitlab-ci.yml` | **ausente** (chore pendente) |

---
---

# 🔁 RE-REVIEW (3ª rodada / validação independente) — Bloco de Esteira, Sprint 29

> **Revisor:** Code Reviewer | **Data do re-review:** 2026-09-29 (independente, por execução)
> **Branch:** `feature/demanda-29-schema-gestor-individual` (não commitado)
> **Alvo:** confirmar/refutar **com execução própria** (não lendo o relato do autor) os 3 pontos pedidos: (1) B1 fechado; (2) ledger honesto; (3) **achado dos exits 8/9** (não observáveis hoje por precedência do `EOLRails`).
> **Veredito:** ✅ **APROVADO (sem blockers)** — B1 fechado; ledger honesto; **o achado dos exits 8/9 CONFIRMA-SE**; 2 sugestões não-bloqueantes (uma delas o próprio achado 8/9, agora com mitigação barata).

## RR-1. Método

Tudo reexecutado por mim, em ambiente próprio, contra o **artefato real de cada arquivo** (nunca contra a cópia `-i`, exceto nas mutações, em cópias temporárias em `/tmp` sem tocar o ledger revisado):

- **B1:** container oficial **`postgres:17`** próprio (`cr_pg17`, porta 5455), env exato do CI, verificando a rota de rede (`inet_client_addr()`).
- **Exits 8/9:** `bin/brakeman -i <ledger-mutado>` (o `-i` lê só o ledger apontado; os outros defeitos permanecem os reais) — mutações construídas em `/tmp`.

## RR-2. B1 — ✅ FECHADO (confirmado por execução independente)

| Verificação | Comando | Resultado |
|---|---|---|
| `pg_hba` efetivo | `grep -vE '^\s*#' .../pg_hba.conf` | termina em `host all all all scram-sha-256`; os `trust` de loopback permanecem |
| rota do runner | `SELECT inet_client_addr()` pela porta publicada | **`172.17.0.1`** → cai na linha `scram` (reproduz a mecânica da B1) |
| **estado antigo** (`CREATE ROLE ... LOGIN` sem senha) | `CREATE ROLE "app.frequencia" LOGIN` + `PGPASSWORD="" psql ...` | `fe_sendauth: no password supplied` (**reproduz o bug original**) |
| **estado novo** (passo verbatim do `ci.yml:101-106`) | `CREATE ROLE ... LOGIN PASSWORD 'app'` + `createdb -O` + `grep -q 1` | `rolpassword IS NOT NULL = t`; `PGPASSWORD=app psql ...` → `app.frequencia\|frequencia_pessoas_espelho_test`, **exit 0** |
| idempotência (re-rodar o passo) | repetir as 2 linhas com `|| true` | `CREATE ROLE: role already exists` / `createdb: already exists` são **absorvidos**; o gate `grep -q 1` segue **exit 0** → idempotência legítima confirmada |
| `db:test:prepare` (app real, mesmo env) | `bin/rails db:test:prepare` | **EXIT=0** |
| `test:pessoas_schema:load` (app real) | `bin/rails test:pessoas_schema:load` | `Pessoas mirror test schema loaded...`, **EXIT=0** |
| testes do espelho (app real) | `bin/rails test test/lib/... test/models/pessoas_pessoa_test.rb test/models/pessoas_unidade_test.rb` | **19 runs / 68 assertions / 0 failures / 0 errors / 0 skips** |

**Ponto de atenção 1 — ✅ CORRETO E COMPLETO.** A senha da role (`PASSWORD 'app'`) casa exatamente com `PESSOAS_DB_PASSWORD: app` (`ci.yml:126`); o usuário `PESSOAS_DB_USERNAME: app.frequencia` (`ci.yml:122`) casa com o nome da role. O `database.yml` do bloco `pessoas` usa `ENV.fetch("PESSOAS_DB_USERNAME"/"PESSOAS_DB_PASSWORD", credentials)` — mesmas chaves. Não sobra caminho de auth: o `test:pessoas_schema:load` conectou (EXIT 0) provado pelo ambiente real.

**`|| true` remanescente (linhas 101-102):** legítimo, **não** esconde falha real de criação. Provado nos dois sentidos: (a) quando a role/banco já existem, os dois comandos falham e são absorvidos pelo `|| true` — só que o **estado alvo já está satisfeito** (role com senha existe; banco existe) e o gate seguinte cobre; (b) quando **não** existem, a criação é bem-sucedida. O **único** caso em que o `|| true` mascararia uma falha real seria "role existe **sem senha**" (estado do bug original) — cenário que precisa de ação humana prévia (o runner do GitHub é efêmero, o banco nasce sem a role; e o dev local configurado pelo README não teria a role). O gate `grep -q 1` (linha 106) de fato **propaga o exit code** e **não tem `|| true`** → se o `createdb` falhar por motivo real, o passo quebra. **Sem blocker.**

## RR-3. Ledger `config/brakeman.ignore` — ✅ REGISTRO DE ACEITAÇÃO HONESTO

- **3 entradas, todas `Weak`** (`SQL` `:72`/`:71`; `Dangerous Eval` `application_helper.rb:33`); o **`Medium` `EOLRails` está FORA** (`brakeman_version: 8.0.5` casa com a gem do `Gemfile.lock:85` e com o report: `Brakeman Version: 8.0.5`).
- **Cada `note` justifica de fato**, e a substância foi conferida no código real:
  - `frequencia_por_orgao_controller.rb:70-72` → `def filtrar_por_periodo(relation, coluna)`, **privado**, com **3 callers internos** passando símbolo literal (`:data` L52, `:punched_at` L60, `:momento_inicial` L66); `params[:mes]/[:ano]` entram como **bind** (`?`). O `user_input: "coluna"` do Brakeman é o **nome da variável**, não uma fonte externa real. **Aceitação correta** — `coluna` não é alcançável por input.
  - `application_helper.rb:33` → `eval(code)` em `eval_with_rescue(code)`, alimentado por `menu_item.dig(:active_test)` de `@static_menu`; a nota cita que a string **nunca** vem de input/params/request e que a fonte é a gem `zutils`/projeto `basic8` (port fiel, confirmado pelo comentário no próprio arquivo e pela decisão do usuário em 2026-09-14). **Aceitação correta.**
- **Nenhuma entrada "esconde" warning explorável:** a única exploração teórica é o futuro dev importar `filtrar_por_periodo` num concern/público passando `params` como `coluna` — hipótese **não materializada** e já registrada como chore opcional (whitelist/`Arel.sql`) na triagem do CTO. **Honesto.**
- **Higiene do binstub:** `bin/brakeman:34-36` injeta **apenas** `--ensure-ignore-notes` e `--ensure-no-obsolete-ignore-entries`; `grep` confirmou que `--ensure-latest`/`--no-exit-on-warn`/`-x EOLRails` aparecem **só em comentário**, nunca em código. Sem `config/brakeman.yml`. YAML do `ci.yml` válido; JSON do ledger válido.

## RR-4. Achado dos exits 8/9 — ✅ **CONFIRMADO** (com execução própria)

**Tese do autor:** com o `EOLRails` (Medium) presente, o exit é **sempre 3** — os códigos 8/9 ficam **mascarados** (precedência do exit 3) e por isso **não são observáveis hoje**.

**Verificação (mutando o ledger real via `-i`, sem tocar o artefato):**

| Cenário | Mutação | EXIT medido | Coincide com a tese? |
|---|---|---|---|
| base (ledger real) | nenhuma | **3** | sim |
| nota **esvaziada** (`note: ""`) | entrada real com nota vazia | **3** | **sim — o esperado seria 8** |
| **entrada obsoleta** adicionada (schema `CREATE_ROLE` válido, fingerprint inexistente) | 4ª entrada a mais | **3** | **sim — o esperado seria 9** |
| nota **ausente** (chave removida) | 4ª entrada a mais | **1** (`NoMethodError` em `report/ignore/config.rb:98`) | reproduz o `RE-M2.1` |

→ Os exits **8 e 9 não aparecem** nesses cenários: **o achado CONFIRMA-SE integralmente.** A causa relatada (o `EOLRails`, achado **não-ignorado**, tem precedência sobre os códigos de falha de política) foi reproduzida de forma independente.

**Controle isolado (a tese fica ainda mais forte do que o autor afirmou):** para provar que as flags **funcionam de fato**, cobri **também** o `EOLRails` no ledger (`Security Warnings: 0`). Aí sim:
- `note` vazia → **EXIT=8** (`[Error] Notes required for all ignored warnings...`);
- entrada obsoleta → **EXIT=9** (`== Obsolete Ignore Entries ==`);
- tudo em ordem → **EXIT=0** (control).

Ou seja: **os códigos 8/9 são reais e corretos — apenas inalcançáveis enquanto o `EOLRails` existir.** O achado do autor procede; a precisão que acrescento é que o `EOLRails` **não "sobrescreve" a mensagem** (ela é impressa: o `[Error] Notes required...` e o `== Obsolete Ignore Entries ==` aparecem no relatório), mas **mascara o código de saída** (tudo sai 3). Efeito prático: **um ledger com nota faltando ou entrada obsoleta passa despercebido hoje** — a política anti-drift fica **sem sinal** exatamente como o autor relatou. Correção de método: a medição `exit=1` que o autor descartou era de fato inválida (chave removida ≠ esvaziada, e derruba o Brakeman 8.0.5 com `NoMethodError`) — reproduzida aqui como `EXIT=1`.

## RR-5. Sugestões não-bloqueantes (novas nesta rodada)

**🟡 RR-S1 — dar sinal aos exits 8/9 hoje (mitigação barata, não-bloqueante).** Como o achado do §RR-4 está **confirmado**, a política anti-drift fica "cega" enquanto o `EOLRails` existir (é o modo de falha que o próprio CTO quis eliminar). Sugestão (escolha do CTO, sem código aqui): o binstub pode detectar que o scan ficou **sem sinal de política** e falhar explicitamente — ex.: se `bin/brakeman` sair `3` **e** o relatório contiver `Notes required` / `Obsolete Ignore Entries`, retornar **exit 8/9** (preservando o código prescrito no ruling). Alternativa mais simples: um passo de CI que grep-a a saída por essas duas strings e falha. **Impacto:** sem isso, a salvaguarda só passa a valer após o bump de Rails ≥ 8.1.x (que remove o `EOLRails`).

**🟡 RR-S2 — `PESSOAS_DB_DATABASE` é decorativo (débito de coerência).** `config/database.yml:72` fixa `database: frequencia_pessoas_espelho_test` (literal), mas o `ci.yml:127` define `PESSOAS_DB_DATABASE`. O bloco `pessoas` do `database.yml` **não lê** `ENV.fetch("PESSOAS_DB_DATABASE", ...)` (ao contrário do bloco `pessoas` de **development**, que lê as credentials). Confirmado em execução: apontar `PESSOAS_DB_DATABASE` para outro banco **não** redireciona a conexão (a suíte continuou contra `frequencia_pessoas_espelho_test`). Inócuo hoje, mas ENV que parece configurar e não configura é armadilha de diagnóstico. Sugestão: ler `ENV.fetch("PESSOAS_DB_DATABASE", "frequencia_pessoas_espelho_test")` **ou** remover a linha do CI. **Não bloqueia.**

## RR-6. Ponto de atenção 3 — o `scan_ruby` vermelho como estado do CI

**Avaliação pedida (quem garante o bump de Rails?).** Concordo com a substância da posição do CTO (§RE-4) — o commit do bloco **está liberado** e o `EXIT=3` é a prova de que o scan roda — mas **registro a lacuna de governança de forma explícita, porque ela é real**:

- O `iteration_29.md` (569 linhas) **não define um gate de saída** para o débito do bump: o bullet (L272) diz "pendência nova registrada pela Ruling M2, em chore separada" e a ordem de execução do ruling (L427) coloca o bump **antes** do ledger, mas **nenhum critério de aceite / issue rastreada / data** obriga a execução. Não há **dono** explícito nem item de backlog com critério de pronto.
- Como o remote de produção é GitLab **sem `.gitlab-ci.yml`** e o `ci.yml` é GitHub Actions com `ruby-4.0.0` inexistente, **nenhum runner real** produz o vermelho hoje — o `scan_ruby` "vermelho" é teórico. Isso **reduz o custo do débito** (não bloqueia nada no presente) mas **também** significa que o sinal só aparecerá quando o fork do CI for feito — e aí ele chega **junto** com o passo do banco do espelho, podendo ser normalizado como "mais um vermelho conhecido".
- **Risco de modo de falha:** se o fork do CI entrar com o `EOLRails` vivo, a equipe verá `scan_ruby` vermelho desde o primeiro dia; sem dono/data, a probabilidade de "aprender a ignorar" é alta — o mesmo anti-padrão que o `--ensure-latest` produzia.
- **Ação mínima sugerida (não-bloqueante para o commit):** amarrar o bump a um **critério de aceite com dono e prazo** (ex.: task `chore/rails-8.1` com DoD "`bin/brakeman --no-pager` = EXIT=0" e data ≤ imediata pós-fork), e usar o rr-S1 para que os exits 8/9 voltem a ter sinal já com o `EOLRails` vivo. Sem isso, o débito depende de memória — a mesma classe de risco que as lições da sprint tentaram eliminar.

## RR-7. Pontos 4-6 — resposta direta

- **`skip_sem_espelho!` segue honesto?** ✅ **Sim.** Provado nos **dois** estados do espelho: (a) banco **presente** com schema → 19/68/0 skips (o skip **não** dispara; não mascara execução); (b) conexão **OK** mas tabelas **ausentes** (schema apagado no container) → **19 skips**, `skip` limpo com motivo acionável, **exit 0**. O cenário em que a guarda **não** protege é o do CI real: se `test:pessoas_schema:load` **falhar**, o passo aborta antes (não há skip). E se um dia o `RUN` for alterado para `bin/rails test` **sem** o load (regressão), a suíte ficaria **verde com 19 skips** — o anti-padrão que a sprint quis matar. Isso **é coberto** hoje pelo gate `grep -q 1` (linha 106, sem `|| true`), mas a proteção é **indireta**: nada no `Run tests` afirma "o espelho foi exercitado". **Sugestão leve (não-bloqueante):** um assert no fim da suíte (ex.: `test:pessoas_schema:load` como pré-condição, ou um check de que houve >0 execuções do espelho) tornaria a proteção direta. A justificativa no comentário da guarda ("no CI o setup é obrigatório") descreve a **intenção**, mas o **grep cobre a existência do banco, não o load** — sem blocker porque hoje o `Run tests` está correto.
- **`|| true` remanescente?** ✅ Legítimo (idempotência role/createdb), não esconde falha real de criação — ver §RR-2.
- **Higiene:** ✅ Nenhum segredo/log/tmp no bloco in-scope (o `grep` do diff não achou `secret/token/password` fora dos valores de teste locais `app`/`postgres`). `config/credentials.yml.enc`, `log/*.log` e `tmp/cache/*` estão **TRACKED** e modificados — devem ficar **fora** do stage (stage seletivo, nunca `git add -A`). `config/brakeman.ignore` está **untracked** (`git check-ignore` → não ignorado) → exige `git add` explícito.

## RR-8. Falsos positivos refutados nesta rodada

| Suspeita | Resultado |
|---|---|
| "O fix do B1 pode não bastar num runner real" | **Refutado.** Passo verbatim do `ci.yml` + app real contra `postgres:17`: role com senha, `db:test:prepare`/`test:pessoas_schema:load` **EXIT=0**, 19/68/0. |
| "O `|| true` do `CREATE ROLE` pode mascarar falha real" | **Refutado no caso de fluxo.** Idempotência legítima; o gate `grep -q 1` sem `|| true` cobre a existência do banco. Risco residual só com role pré-existente sem senha (não ocorre no runner efêmero). |
| "Os exits 8/9 funcionam — o autor errou ao dizer que estão mascarados" | **Refutação NÃO procede — o achado do autor se CONFirma.** Sem cobrir o `EOLRails`, os cenários de nota vazia/entrada obsoleta saem **3**, não 8/9. Só com o `EOLRails` coberto é que 8/9 aparecem (provado como control). |
| "O ledger contém o Medium / o gate ficou verde por decreto" | **Refutado.** 3 entradas `Weak`; `bin/brakeman --no-pager` = **EXIT=3**; `Medium` fora. |
| "Reintroduziram `--ensure-latest`/`--no-exit-on-warn`/`-x EOLRails`" | **Refutado.** Só comentário; flags em código são apenas as 2 anti-drift. |
| "`skip_sem_espelho!` mascara falha legítima" | **Refutado no estado atual.** Com banco presente: 0 skips; com tabela ausente: skip limpo. Único vetor (regressão do `run:` sem o load) é coberto pela checagem do banco, ainda que indiretamente. |
| "`PESSOAS_DB_DATABASE` no CI redireciona a conexão" | **Refutado.** `database.yml:72` é literal → a ENV é decorativa (achado RR-S2). |

## RR-9. Métricas medidas nesta rodada

| Métrica | Valor |
|---|---|
| `test:pessoas_schema:load` (app real, container `postgres:17`, env do CI) | **EXIT=0** |
| `db:test:prepare` (app real, container) | **EXIT=0** |
| Testes do espelho (app real, schema presente) | **19 runs / 68 assertions / 0 failures / 0 errors / 0 skips** (exit 0) |
| Testes do espelho (conexão OK, tabelas ausentes) | **19 skips / 0 errors** (exit 0) |
| Auth role com senha vs vazia (`PGPASSWORD`) | exit 0 vs `fe_sendauth: no password supplied` |
| `bin/brakeman --no-pager` (estado final) | **EXIT=3** — 1 warning (EOLRails Medium) / 3 ignorados |
| Exit com nota vazia / entrada obsoleta **+ EOLRails vivo** | **3 / 3** → **achado 8/9 CONFIRMADO** |
| Exit com nota vazia / entrada obsoleta / tudo OK **+ EOLRails coberto** (control) | **8 / 9 / 0** |
| Exit com `note` ausente (chave removida) | **1** (`NoMethodError`) |
| `inet_client_addr()` do runner → container | `172.17.0.1` (rota `scram`) |
| YAML `ci.yml` / JSON ledger | válidos; `brakeman_version: 8.0.5` = gem instalada |
| `continue-on-error`/`allow_failure` | nenhum; `.gitlab-ci.yml` ausente |

---

## RR-10. VEREDITO FINAL (3ª rodada)

> ✅ **APROVADO (sem blockers).** B1 **fechado e confirmado por execução independente** (`postgres:17`, app real: EXIT 1 → 0). Ledger **honesto** e correto (só `Weak` com `note` substanciada; `Medium` fora). **O achado dos exits 8/9 se CONFIRMA** — em todos os cenários testados com o `EOLRails` vivo o exit é **3**; os códigos 8/9 só aparecem cobrindo o `EOLRails` (provado como control).
>
> **O que ainda impede os 3 commits:** **nada de técnico no bloco de esteira.** Impede apenas a **higiene de stage**: `config/credentials.yml.enc`, `log/*.log` e `tmp/cache/*` estão tracked+modificados e **não** podem entrar; `config/brakeman.ignore` está untracked e **precisa de `git add` explícito**. Usar stage seletivo (nunca `git add -A`).
>
> **Não-bloqueantes a registrar:** 🟡 RR-S1 (dar sinal aos exits 8/9 hoje), 🟡 RR-S2 (`PESSOAS_DB_DATABASE` decorativo), 🟠 RE-D1/§RR-6 (chore do fork do CI + bump Rails ≥ 8.1.x **sem dono/prazo** — amarrar a um critério de aceite).
