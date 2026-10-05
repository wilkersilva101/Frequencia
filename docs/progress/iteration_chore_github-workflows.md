# iteration chore: workflow do GitHub Actions na raiz do monorepo

> **Modo:** AGILE | **Branch:** `chore/github-workflows-root` (base `integration/sprint-29` @ `0a56c84`)
> **Data:** 2026-09-30 | **Tipo:** chore (infra de CI) | **COMMIT_MODE=manual** (sem commit/push nesta etapa).
> **Rastreabilidade:** débito aberto no fim de `iteration_chore_gitlab-ci.md` (tabela *Pendências*:
> "Mover `.github/workflows/ci.yml` para a raiz do repo (mesmo defeito do monorepo)");
> mesma classe de defeito corrigida no GitLab em `7db515c`.

## Descrição

Mover o workflow do **GitHub Actions** para a **raiz do repositório**, corrigindo o mesmo
defeito de monorepo já corrigido no `.gitlab-ci.yml`. O repo `Frequencia` é um **MONOREPO**
(raiz git = `Frequencia/`, app Rails em `api-ponto/`) e o **GitHub Actions só descobre
workflows em `.github/workflows/` na RAIZ** — o arquivo vivia em `api-ponto/.github/workflows/ci.yml`,
logo **nunca foi executado** (não falhava: não existia). A `ruby-version: '3.3.8'` já estava
correta nos 3 jobs (não alterada).

## Escopo

- [x] Mover `api-ponto/.github/workflows/ci.yml` → `<raiz>/.github/workflows/ci.yml`
- [x] `defaults.run.working-directory: api-ponto` para os steps `run:` (espelha o `cd api-ponto` do GitLab)
- [x] **Achado crítico:** `defaults.run` NÃO cobre steps `uses:` → `working-directory: api-ponto`
      adicionado ao input do `ruby/setup-ruby` (senão o `bundler-cache` busca o `Gemfile.lock` na raiz)
- [x] **Achado crítico:** step "Install packages" do job `test` roda ANTES do checkout →
      `working-directory: .` explícito (senão o runner falha, `api-ponto/` não existe ainda)
- [x] **Mesmo defeito colateral:** `api-ponto/.github/dependabot.yml` movido para a raiz
      (GitHub só lê da raiz) + `directory: "/api-ponto"` no ecossistema `bundler`
- [x] Comentário no topo justificando a localização e o `working-directory` (anti-remoção silenciosa)
- [x] Verificar dependências de cwd (`bin/brakeman`/`bin/rubocop`/`bin/rails`, `bundler-cache`)
- [x] Confirmado: `ruby-version: '3.3.8'` já correto nos 3 jobs (linhas 23/42/81 originais) — não alterado
- [x] Provas nos dois sentidos + YAML + actionlint (ver §Provas)

## Arquivos alterados

| Arquivo | Ação | O que |
|---|---|---|
| `.github/workflows/ci.yml` (raiz) | movido+editado (de `api-ponto/.github/workflows/`) | cabeçalho, `defaults.run.working-directory`, `working-directory` no `setup-ruby` ×3, `working-directory: .` no "Install packages" |
| `.github/dependabot.yml` (raiz) | movido+editado (de `api-ponto/.github/`) | cabeçalho + `directory: "/api-ponto"` no `bundler` |
| `api-ponto/.github/` | removido | diretório esvaziado (não era lido pelo GitHub) |

## Decisão de design: `defaults.run.working-directory` vs. prefixar cada `run:`

**Escolhido:** `defaults.run.working-directory: api-ponto`, espelhando o `cd api-ponto` do
`.gitlab-ci.yml` (`7db515c`). **Justificativa:** é a menor superfície — 1 chave cobre os 5
steps `run:`; prefixar `api-ponto/bin/*` exigiria editar 5 comandos e não resolveria o
`bundler-cache` nem os scripts multi-linha do job `test`. Mesma lógica já aprovada no GitLab.

**Porém — e este é o achado que o `defaults` sozinho NÃO cobre:** `defaults.run` só se aplica
a steps `run:` (doc oficial: "provide default `shell` and `working-directory` options for all
`run` steps"). Logo:

1. **`ruby/setup-ruby` é `uses:`** → NÃO é afetado. Sem o input `working-directory: api-ponto`,
   o `bundler-cache` procura `Gemfile.lock`/`.ruby-version`/`.tool-versions` na RAIZ e não os acha
   (a app é em `api-ponto/`). Foi adicionado nos 3 jobs.
2. **`Install packages` (job `test`) roda ANTES do checkout** → o runner resolve o cwd ANTES de
   `api-ponto/` existir e falharia com "working directory does not exist". Sobrescrito para `.`.
3. **`actions/checkout` é `uses:`** → roda na raiz (correto: checkout é do repo inteiro).

> Sem os itens 1 e 2, o `defaults` sozinho produziria um workflow que **parece** correto e
> quebra no runner — exatamente o anti-padrão da sessão (prova que não exercita a condição real).

## Provas (nos DOIS sentidos)

### Controle negativo — comandos do workflow a partir da RAIZ, SEM `working-directory`

| Comando (cwd = raiz `Frequencia/`) | Resultado medido |
|---|---|
| `ls bin/` | `No such file or directory` |
| `bin/brakeman --no-pager` | **EXIT=127** (`Arquivo ou diretório inexistente`) |
| `bin/rubocop -f github` | **EXIT=127** |
| `bin/rails --version` | **EXIT=127** |

### Positivo — comandos a partir de `api-ponto/` (efeito de `working-directory: api-ponto`)

| Comando (cwd = `api-ponto/`) | Resultado medido |
|---|---|
| `bin/brakeman --no-pager` | **EXIT=3** — 1 warning `Medium` EOLRails (dívida pré-existente); confirma que o scan RODA |
| `bin/rubocop -f github` | **EXIT=1** — 77 offenses (baseline pré-existente idêntico) |
| `bin/rails --version` | **Rails 8.0.5**, **EXIT=0** |

### Descoberta (a condição que o caso #4 da sessão expôs: a ferramenta LÊ o arquivo?)

| Cenário (actionlint `rhysd/actionlint` em Docker) | Resultado |
|---|---|
| **RAIZ** — auto-descoberta (`actionlint -verbose`, sem args) | `Detected project: /repo`, `Linting .github/workflows/ci.yml`, **0 erros**, EXIT=0 |
| **SUBPASTA** (estado antigo: só `api-ponto/.github/workflows/`) | `no project was found…`, **EXIT=3** — o workflow é invisível (reproduz o defeito) |
| **Controle positivo do linter** (erro injetado: `${{ github.evento.inexistente }}`) | detectado (EXIT=1) — prova que o linter valida de verdade, não passa em branco |

### Estrutura

- **YAML parse (Psych)** — `ci.yml`: OK, `jobs=[scan_ruby, lint, test]`,
  `defaults.run.working-directory="api-ponto"`, `[test] Install packages WD="."`.
  `dependabot.yml`: `bundler -> /api-ponto`, `github-actions -> /`.
- **`bin/rubocop`** — **77 offenses** (baseline; o arquivo alterado é YAML, não `.rb`; 0 offenses em `.github`).
- **Dependências de cwd** — `bin/brakeman` (wrapper) não contém `Dir.chdir`/caminho hardcoded; usa
  `Brakeman::Commandline` sobre o cwd (`api-ponto/`) — OK. `bin/rails`/`bin/rubocop` são binstubs
  padrão — resolvem pelo cwd. `bundler-cache` coberto pelo input do `setup-ruby`.

## O que foi MEDIDO vs. SUPOSTO

- **Medido:** EXITs 127/3/1/0 dos comandos nos dois sentidos; YAML parse; rubocop 77; actionlint
  (descoberta na raiz vs. subpasta; controle positivo do linter); ausência de cwd-hardcode no wrapper.
- **Suposto (não verificável daqui):** o runner hospedado do GitHub Actions. Não há `act` instalado;
  não se executou o workflow num runner real. As duas suposições com maior risco — (a) que
  `defaults.run` não cobre `uses:` e (b) que o step pré-checkout falharia — foram fechadas **por
  documentação oficial** (GitHub: "for all `run` steps"; `ruby/setup-ruby`: input `working-directory`
  resolve `.ruby-version`/`.tool-versions`/`Gemfile.lock`), não por execução.

## Linha do Tempo

| Horário | O que foi feito | Resultado |
|---------|-----------------|-----------|
| 2026-09-30 | Contexto (governance/progress `_context.md`, iteration_chore_gitlab-ci, `.gitlab-ci.yml`) | contexto |
| 2026-09-30 | Branch `chore/github-workflows-root` de `integration/sprint-29` @ `0a56c84` | criada |
| 2026-09-30 | Doc oficial: `defaults.run` escopa só `run:`; input `working-directory` do `setup-ruby` | confirmado |
| 2026-09-30 | Controle negativo (raiz) / positivo (`api-ponto`) dos 3 comandos | 127 / 3·1·0 |
| 2026-09-30 | Patch: cabeçalho + `defaults` + `working-directory` no `setup-ruby` ×3 + `\.` no Install packages | aplicado |
| 2026-09-30 | Achado colateral: `dependabot.yml` também em subpasta → movido + `directory: /api-ponto` | aplicado |
| 2026-09-30 | Mover para a raiz; remover `api-ponto/.github/` | feito |
| 2026-09-30 | YAML parse + actionlint (raiz vs. subpasta vs. erro injetado) | 0 / 3 / 1 |
| 2026-09-30 | Limpeza: `/tmp` e imagem `rhysd/actionlint` removidos | feito |

## Commits

**Nada commitado/pushado (COMMIT_MODE=manual).** Stage seletivo preparado (NUNCA `git add -A`):

```bash
# a partir da raiz Frequencia/
git add .github/workflows/ci.yml .github/dependabot.yml
git add -u api-ponto/.github
# NÃO incluir: api-ponto/config/credentials.yml.enc, api-ponto/log/*.log, api-ponto/tmp/cache/*
git commit -m "ci: move o workflow do GitHub Actions para a raiz do monorepo"
```

## Notas

- **Branch base — desvio justificado (mesmo do chore GitLab):** o `agile-task-protocol` diz criar
  de `develop`; usou-se `integration/sprint-29` @ `0a56c84` conforme instrução explícita do
  coordenador (`develop` é beco morto local). Merge target: `integration/sprint-29`.
- **Arquivo próprio de rastreabilidade (decisão):** criado `iteration_chore_github-workflows.md`
  em vez de anexar a `iteration_chore_gitlab-ci.md`. Cada tarefa ágil = uma branch = um arquivo
  (`agile-task-protocol`); a chore do GitLab já está fechada/bloqueada com branch e commits
  próprios — anexar misturaria dois ciclos AGILE.
- **Higiene:** `api-ponto/config/credentials.yml.enc`, `log/*.log`, `tmp/cache/*` ficam FORA do
  stage (ruído de working tree, não revertidos). `.github/*` na raiz são untracked → exigem
  `git add` explícito; as deleções em `api-ponto/.github/` exigem `git add -u`.
- **Diferente do GitLab:** o GitHub Actions publica as portas dos `services:` em `localhost`
  (o `ci.yml` declara `ports: 5432:5432` e usa `-h localhost`), então o job `test` deste arquivo
  está correto como está — a correção de alias do GitLab NÃO se aplica aqui.

## Pendências / débitos

| Débito | Dono | Critério de pronto |
|---|---|---|
| Validar o workflow em 1 run real no GitHub Actions (runner hospedado) | a definir | jobs `scan_ruby`/`lint`/`test` executam (não "não aparecem") |
| Bump Rails ≥ 8.1.x (remove o `Medium` EOLRails) | a definir | `bin/brakeman --no-pager` = EXIT=0 |
| Limpar as 77 offenses do RuboCop | a definir | `bin/rubocop -f github` = EXIT=0 |
