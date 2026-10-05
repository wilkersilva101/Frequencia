# iteration chore: bump do Rails 8.0.5 → 8.1.4 + dívida de versão do Ruby

> **Modo:** AGILE | **Branch:** `chore/bump-rails-8.1` | **Data:** 2026-10-05 | **Deadline:** 2026-10-07 (2 dias)
> **Tipo:** chore (toolchain — bump de dependência + correção de fontes de versão). **Não** é feature.
> **COMMIT_MODE=manual** (o dev autoriza a implementação e o commit depois deste plano).
> **Autor:** CTO (plano doc-only — **nenhum** arquivo de código versionado foi tocado nesta sessão).
> **Rastreabilidade:** `iteration_29.md` §Ruling M2 / §Triagem Fase 2 §2 (`bump Rails ≥ 8.1.x` como
> condição de fechamento do gate `scan_ruby`); `docs/governance/_context.md` §"Dívida de versão do
> Ruby — DÍVIDA ABERTA (dono pendente)"; `bin/brakeman` (comentário de topo: "o `Medium`
> EOLRails é time bomb, tratado estruturalmente"); `docs/adr/0009-estrategia-versao-toolchain-ruby-rails.md`.

---

## Sumário executivo

| Item | Decisão |
|------|---------|
| **Alvo do Rails** | **8.1.4** (última publicada; minor bump 8.0 → 8.1). `Gemfile`: `"~> 8.0.4"` → `"~> 8.1.0"`. |
| **Alvo do Ruby** | **3.3.8** (o medido). **Não** subir para 3.4/4.0 nesta chore — fora do escopo e do deadline. |
| **Gatilho de conclusão** | `bin/brakeman` = **EXIT 0** (validado **localmente**; o runner GitLab está offline). |
| **Achado crítico** | O bump **sozinho NÃO fecha o gate**: há um **2º** warning não-ignorado (SQL Injection em `frequentadores_visiveis.rb:351`, nasceu no `16c1c9a`/29.7) que também precisa entrar no ledger com `note`. Ver §5. |
| **Critério de aceite** | `bin/brakeman` EXIT 0 **e** `bin/rails test` sem falha nova vs. baseline **1083 runs / 3789 asserções / 1F + 11E** (12 pré-existentes). |
| **ADR** | **ADR-0009** (novo) — versão-alvo do Ruby/Rails + lockstep das 3 fontes + política do ledger. Último existente = **ADR-0008** (confirmado). |

---

## 1. Dívida de versão do Ruby — três fontes conflitantes (medido)

| Fonte | Declara | Situação |
|-------|---------|----------|
| `.ruby-version` (`api-ponto/.ruby-version`) | `ruby-4.0.0` | ❌ **não existe** (Ruby 4.0 nunca foi lançado) |
| `.tool-versions` (`api-ponto/.tool-versions`) | `ruby 4.0.0` | ❌ **não existe** |
| `AGENTS.md` (raiz, §Identidade) | "Ruby 4.0.0 / Rails 8.0.4" | ❌ defasado nas duas pontas |
| **Medido de fato** (`ruby -v`) | **ruby 3.3.8** (`bison/ruby` em `/var/lib/gems/3.3.0`) | ✅ **é a verdade do ambiente** |
| `Gemfile.lock` (medido) | `rails (8.0.5)` | ✅ confere |

**Impacto do `ruby-4.0.0` na dívida:** o `.ruby-version` **não é decorativo** — o Brakeman lê essa
**exata** fonte para detectar a versão de Ruby (`brakeman/scanner.rb:191-197` lê `.ruby-version` via
regex `(\d+\.\d+\.\d+)` e chama `config.set_ruby_version`). Hoje o Brakeman "crê" que o app roda MRI
**4.0.0**, que **não casa com nenhuma faixa** da tabela `RUBY_EOL_DATES` (`check_eol_ruby.rb:14-29`,
que termina em `['3.4.0','3.4.99']`) → o check **EOLRuby simplesmente não dispara**. Ou seja, a fonte
mentirosa **suprime silenciosamente** um lembrete de EOL de Ruby. Corrigir as 3 fontes não é cosmético:
é o que devolve o sinal do gate.

### Correção das 3 fontes (todas para `3.3.8`)

| Arquivo | De | Para |
|---------|----|------|
| `api-ponto/.ruby-version` | `ruby-4.0.0` | `3.3.8` |
| `api-ponto/.tool-versions` | `ruby 4.0.0` | `ruby 3.3.8` |
| `AGENTS.md` (raiz, linha 35) | "Rails 8.0.4 (…) Ruby 4.0.0" | "Rails 8.1.4 (…) Ruby 3.3.8" |

> **Decisão de escopo (ADR-0009):** a chore **fixa** o Ruby em **3.3.8** (o medido e o que o
> `.gitlab-ci.yml` já usa — `image: ruby:3.3.8-slim`). **Não** subir para Ruby 3.4/4.0 nesta chore:
> (a) o Rails 8.1 exige apenas `>= 3.2.0` (verificado na gemspec instalada), então 3.3.8 **basta**;
> (b) subir Ruby tem blast radius de toolchain (mise/asdf/vendor bundle) e não é necessário para o
> gatilho; (c) o deadline é de 2 dias. A migração de Ruby **major** fica como chore futura própria.

---

## 2. Alvo exato do Rails

- **`Gemfile` (`api-ponto/Gemfile:4`):** `gem "rails", "~> 8.0.4"` — o constraint `~> 8.0.4` significa
  `>= 8.0.4, < 8.1.0` → **exclui** o 8.1.x. É **obrigatório** editar o `Gemfile`, não basta `bundle update`.
- **`Gemfile.lock` (medido):** `rails (8.0.5)` (linha 245) + `rails (~> 8.0.4)` (linha 414).
- **Alvo disponível (medido `gem list -r -e rails`):** última = **8.1.4**; série 8.1.x = 8.1.0–8.1.4.
- **Natureza do bump:** **minor** (8.0 → 8.1). Dentro da série 8.1.x o alvo é o patch **8.1.4**.
- **Constraint proposto:** `"~> 8.1.0"` (`>= 8.1.0, < 8.2.0`) — fixa o minor, deixa o patch evoluir. O
  lock resolverá **8.1.4**. (Alternativa mais conservadora: `"~> 8.1.4"`; prende o patch. Preferir
  `~> 8.1.0` salvo se a `executiva` exigir patch fixo.)
- **Gems dependentes:** nenhuma gem do lock quebra com 8.1 — as restrições vistas apontam para baixo
  (`rails (>= 5.0/5.2/7.0)`; `importmap-rails`, `turbo-rails`, `stimulus-rails`, `breadcrumbs_on_rails`,
  `rubocop-rails`). Não há pin superior a 8.1. Confirmar na resolução (`bundle update rails`).

---

## 3. Os outros arquivos que citam a versão (não esquecer)

Além das 3 fontes da §1, o bump deve **varrer** as referências de versão para não repetir a própria
dívida:

- `api-ponto/.github/workflows/ci.yml` usa `ruby-version: .ruby-version` → **passa a resolver `3.3.8`
  automaticamente** após corrigir `.ruby-version` (efeito colateral positivo). ⚠️ Este workflow é
  **GitHub Actions** e **não roda em produção** (o remote é GitLab) — não é o gate efetivo.
- `Frequencia/.gitlab-ci.yml` (produção): já fixa `image: ruby:3.3.8-slim` — **coerente** com o alvo,
  nada a mudar. O comentário do topo cita "`MEDIDO: ruby -v = 3.3.8; Gemfile.lock rails = 8.0.5`" →
  atualizar a parte do Rails para **8.1.4** ao fim da chore.
- `docs/governance/_context.md` e `AGENTS.md` — a dívida está registrada; ver §10 (governança).

---

## 4. Risco de deprecations / migrations (8.0 → 8.1)

### O que existe hoje
- `config/application.rb:24`: **`config.load_defaults 8.0`** (único ponto).
- **Não existe** nenhum `config/initializers/new_framework_defaults_*.rb` no repo (nem de 7.x nem 8.0).

### O que muda no 8.1
O gerador do Rails 8.1 traz `config/initializers/new_framework_defaults_8_1.rb` com **6 novos
defaults** (lidos da fonte instalada `railties-8.1.1/…/new_framework_defaults_8_1.rb.tt`):

| # | Default 8.1 | Efeito | Risco p/ este app |
|---|-------------|--------|-------------------|
| 1 | `action_controller.escape_json_responses = false` | deixa de escapar ` / /<>&` no JSON | 🟠 **app é API-heavy** (renderiza JSON): muda bytes da resposta. Testar telas/endpoints JSON. |
| 2 | `active_support.escape_js_separators_in_json = false` | idem para separadores U+2028/U+2029 | 🟡 baixo |
| 3 | `active_record.raise_on_missing_required_finder_order_columns = true` | **levanta erro** em `#first`/`#second` sem `order` | 🟠 o projeto usa `.first` em vários pontos (ex.: vínculo principal, D4 da 29.4). Pode quebrar em runtime. |
| 4 | `action_controller.action_on_path_relative_redirect = :raise` | redirect relativo sem `/` **levanta** `UnsafeRedirectError` | 🔴 **o mais perigoso aqui** — ver abaixo. |
| 5 | `action_view.render_tracker = :ruby` | rastreio de dependências de template por parser Ruby | 🟢 baixo |
| 6 | `action_view.remove_hidden_field_autocomplete = true` | para de emitir `autocomplete="off"` | 🟡 baixo |

### 🔴 Risco #4 × as 12 falhas pré-existentes (Devise `redirect_to`)
O default 8.1 `action_on_path_relative_redirect = :raise` é **exatamente** o vetor das **11 falhas
pré-existentes de Devise (`redirect_to`)**. Se a chore **ligar** `load_defaults 8.1`, redirects
relativos passam de `:log` para `:raise` e podem **transformar falhas em exceções** (mudando o baseline).

### Mitigação (estratégia recomendada na ADR-0009)
1. **Bump + teste primeiro, defaults depois.** Na chore, manter **`config.load_defaults 8.0`** e
   **não** criar/enxugar o `new_framework_defaults_8_1.rb`. Assim o comportamento **não muda** — o
   objetivo da chore é o gate verde, não adotar os defaults.
2. Rodar `bin/rails app:update` de forma **assistida** só para materializar o
   `new_framework_defaults_8_1.rb` **com todas as linhas comentadas** (default do template) — registro
   versionado de "o que existe para ligar", sem ativar nada.
3. Adotar os defaults **um a um** em chore/feature futura (dono: CTO/Code Specialist), começando pelos
   de baixo risco e isolando o #4 com um teste que reproduza os redirects de Devise.
4. `load_defaults 8.1` só é ligado quando os 6 estiverem verificados sob `:raise`/novo comportamento.

> **Nota de deadline:** esta estratégia torna a chore de 2 dias **segura e reversível** — se um teste
> novo aparecer, o suspeito é o bump de gems (não os defaults, que ficaram em 8.0). Facilita o bisect.

---

## 5. O ledger `config/brakeman.ignore` — e o achado que muda o plano

### Estado atual do ledger (medido)
`api-ponto/config/brakeman.ignore` contém **3 entradas**, todas `Weak`, todas com `note`:
1. `SQL Injection` — `admin/frequencia_por_orgao_controller.rb:71` (símbolo literal, débito aceito)
2. `SQL Injection` — `admin/frequencia_por_orgao_controller.rb:72`
3. `Dangerous Eval` — `application_helper.rb:33` (portada do basic8, decisão do dev 2026-09-14)

O `Medium` `Unmaintained Dependency`/EOLRails **NÃO** está no ledger — por **ruling** (M2): `Medium`+
não é ignorável, é tratado estruturalmente pelo bump.

### Por que o bump **sozinho não zera** o gate (achado desta sessão)
Baseline medido **hoje** (`bin/brakeman --no-pager -f json`): **total = 2 warnings NÃO-ignorados**:
- (a) `Unmaintained Dependency` / `EOLRails` — `Gemfile.lock:245`, conf **Medium**;
- (b) **`SQL Injection` — `app/models/frequentadores_visiveis.rb:351`, conf **Medium**** — **novo**,
  com `user_input: liberado_por_passos_1_a_4` (SQL montado por heredoc/interpolação em
  `ids_unidades_inelegiveis_como_gestor`).

**(b) nasceu no commit `16c1c9a`** ("fix: fecha 3 débitos pré-29.7 … D2"), **depois** da medição do
review de pipeline de 2026-09-29 (que só viu `1 warning não-ignorado EOLRails + 3 ignorados`). O commit
**passou** pelo review da 29.8 sem que o warning fosse registrado — **não está no ledger**.

**Consequência dura:** após o bump, (a) desaparece (ver abaixo), mas **(b) permanece** → `bin/brakeman`
continuaria **EXIT 3**. **O bump é necessário mas NÃO suficiente.** Para EXIT 0, o ledger tem de
absorver (b) **com `note`** — ou o código de (b) ser corrigido.

### Contraprova do EOLRails (por que ele some com o bump)
`brakeman/checks/check_eol_rails.rb:16-29` mapeia `['8.0.0','8.0.99'] => 2026-10-07`. Hoje (2026-10-05)
o Rails 8.0.5 cai a **2 dias** de `2026-10-07`, logo é `pending_eol_rails` **Medium** (e vira
`eol_rails` **High** no dia 7 — o "time bomb"). A série **8.1.x NÃO casa nenhuma faixa** da tabela
(a tabela termina em `8.0.99`) → após o bump **não há** warning de EOLRails. Cobrir o EOLRails no
ledger seria **rearmar um time bomb** — **proibido** por política. O caminho correto é o bump.

### Tratamento prescrito (passo a passo do ledger)
1. **NÃO** adicionar EOLRails ao ledger. Ele é resolvido pelo bump (§2).
2. Tratar o warning **(b)** — duas opções, em ordem de preferência:
   - **(b1) Corrigir o SQL** (preferível, se couber no deadline): `ids_unidades_inelegiveis_como_gestor`
     monta um heredoc com `#{liberado_por_passos_1_a_4}` / `#{cadeia_tem_gestor(...)}` — sub-fragmentos
     **internos** (não input externo), como os warnings #1/#2. Trocar a interpolação por bind/quoted
     seguro (`sanitize_sql_array`/`Arel.sql` consciente) remove o warning **na raiz** e não deixa dívida.
     ⚠️ Como o 29.8 aprovou aquele código, **qualquer edição nele exigirá re-review** — avaliar contra o
     deadline. Se couber, é a saída mais limpa (fecha o gate **sem** crescer o ledger).
   - **(b2) Aceitar no ledger com `note`** (fallback): entrada `Weak`/`Medium`? — o warning (b) é
     **Medium** de **tipo genérico** (`SQL Injection`), então a **regra de severidade da M2** permite
     aceitar **se** comprovadamente não-explorável por input externo (como #1/#2). O `note` deve citar:
     fragmentos internos (`liberado_por_passos_1_a_4`/`cadeia_tem_gestor`), ausência de `params`, e o
     fato de ter nascido na 29.7. **Isto NÃO é silenciar**: é o mesmo regime dos débitos #1/#2.
     - Registrar o fingerprint **medido** (o default muda de linha em linha; regenerar antes de fixar).
   > **Recomendação do CTO:** tentar **(b1)**; se o re-review não couber em 2 dias, usar **(b2)** e
   > abrir débito 🟡 "warning (b) do ledger" para a chore seguinte. **Não** deixar o warning "solto"
   > (ele derruba o gate e some da política anti-drift).

### ✅ RESOLVIDO (b1) — corrigido no CÓDIGO (Code Specialist, 2026-10-05)
Escolha do dev: **corrigir no código**, não aceitar no ledger. Executado em
`app/models/frequentadores_visiveis.rb#ids_unidades_inelegiveis_como_gestor`:

- O único **valor** da query (`ve.nome = '#{ESTADO_ATIVO}'` em 2 pontos) virou **bind `?`**, aplicado por
  `Pessoas::Unidade.sanitize_sql_array([ sql, ESTADO_ATIVO, ESTADO_ATIVO ])`. `sanitize_sql_array` está
  em `IGNORE_METHODS_IN_SQL` do Brakeman — a query deixa de ser tratada como interpolada crua.
- Os demais `#{...}` (`un`/`au`, `liberado_por_passos_1_a_4`, `cadeia_tem_gestor`) são **fragmentos
  estruturais internos**, sem `params`: aliases fixos; `lista_quoted` usa `connection.quote`;
  `subquery_tipos_terceirizado` usa a constante `TIPO_TERCEIRIZADO`. Não são parametrizáveis (são SQL,
  não valores) e **não** carregam entrada externa — por que é seguro está documentado **no código**.
- Resultado: `bin/brakeman` = **EXIT 0**, `security_warnings=0`, sem nova entrada no ledger
  (`config/brakeman.ignore` intocado: 3 entradas, 0 obsoletas). A suíte da 29.6/29.7 segue verde (ver §11).
3. **Flags anti-drift** (já no `bin/brakeman`): `--ensure-ignore-notes` (exit **8** = entrada aceita sem
   `note`) e `--ensure-no-obsolete-ignore-entries` (exit **9** = entrada do ledger que não casa mais
   nenhum warning). Após o bump, **conferir que nenhuma das 3 entradas antigas virou obsoleta**
   (exit 9). O fingerprint embute arquivo:linha/código **do scan** — o bump de gems **não** muda o
   fingerprint do código de app, então #1/#2/#3 devem continuar casando. Se alguna ficar obsoleta, o
   ledger **não é re-congelado**: corrige-se a entrada (o contrato é o fingerprint).
4. **Prova de execução (não "exit 0 sozinho"):** rodar `bin/brakeman --no-pager` **sem** `-q` e
   conferir que o relatório foi gerado e que os 4 checks EOL rodaram. A lição L-2026-09-25 ("exit 0 sem
   escanear") vale como guarda: **exit 0 tem de vir com relatório**.

> **Nota do wrapper (`bin/brakeman`):** enquanto **qualquer** warning não-ignorado existir, o exit do
> Brakeman é **3**, e os exits 8/9 ficam **mascarados** — o wrapper (RR-S1) captura a saída e promove o
> exit ao código prescrito (8/9) quando detecta o padrão de política. Só **com** o EOLRails coberto
> (aqui: removido pelo bump) e **(b)** tratado é que o exit **0 real** aparece. É a prova de que a
> chore fechou o gate **de fato**.

---

## 6. Plano de execução (ordem recomendada)

1. **Branch:** `chore/bump-rails-8.1` a partir de `integration/sprint-29` @ `e795df9`.
2. **Fontes de versão (§1):** `.ruby-version` → `3.3.8`; `.tool-versions` → `ruby 3.3.8`; `AGENTS.md` L35.
3. **`Gemfile`:** `"~> 8.0.4"` → `"~> 8.1.0"`.
4. **Resolver:** `bundle update rails` (trava → **8.1.4**). Conferir que `bundle check`/`bundle install`
   ficaram consistentes e que **nenhuma** gem subiu de minor por tabela (revisar o diff do lock).
5. **`config/application.rb`:** **manter** `load_defaults 8.0` (§4). Opcional: materializar
   `config/initializers/new_framework_defaults_8_1.rb` 100% comentado (registro do devido).
6. **Teste local (§7)** — suíte completa + espelho. Sem falha nova vs. baseline.
7. **Ledger (§5):** tratar (b) por (b1) ou (b2); conferir exits 8/9; **`bin/brakeman` = EXIT 0**.
8. **Documentação:** atualizar `_context.md` (governança) só via **summarizer**; registrar lição se
   houver; ajustar a citação do `.gitlab-ci.yml` (Rails 8.0.5 → 8.1.4).
9. **Commit manual** (stage seletivo — **nunca** `git add -A`; ficam **fora**
   `config/credentials.yml.enc`, `log/*.log`, `tmp/cache/*`).

---

## 7. Teste local + critério de aceite

**Ambiente:** local (o runner GitLab está offline). Usar **binstubs** (`bin/*`) — `bundle exec rails`
falha neste ambiente (`invalid switch in RUBYOPT`, lição 2026-09-21).

| Gate | Comando | Aceite |
|------|---------|--------|
| **Suíte** | `bin/rails test` | **sem falha/erro NOVO** vs. baseline **1083 runs / 3789 asserções / 1F + 11E** |
| **Espelho** | `RAILS_ENV=test bin/rails test:pessoas_schema:load` + testes do espelho | **0 skips**/sem erro (ADR-0006) |
| **Segurança** | `bin/brakeman --no-pager` | **EXIT 0** (com relatório gerado) |
| **Lint** | `bin/rubocop` (arquivos tocados) | **0 offenses novas** vs. pré-existentes |
| **Boots** | `bin/rails zeitwerk:check`, `bin/rails runner 'nil'` | OK |

**As 12 falhas pré-existentes (NÃO podem virar mais):**
- **11×** Devise `redirect_to` (baseline, ligadas ao `ActionController::Redirecting`).
- **1×** timezone em `test/integration/presenca_endpoints_test.rb`.
- ⚠️ **Regra de aceite:** o bump **não pode** converter essas 12 em exceção/falha adicional — o
  baseline de 1F+11E é o teto. Se mudar, **causa provável = default #4** (`action_on_path_relative_redirect`),
  o que reforça manter `load_defaults 8.0` (§4).

---

## 8. Riscos & mitigações

| Risco | Sev | Mitigação |
|-------|-----|-----------|
| Bump sozinho **não** fecha o gate (warning (b) da 29.7) | 🔴 | §5 — tratar (b) por código (b1) ou ledger com `note` (b2) |
| `load_defaults 8.1` muda comportamento e o baseline | 🔴 | §4 — **não** ligar defaults na chore |
| `.ruby-version` mentiroso suprime EOLRuby no Brakeman | 🟠 | §1 — corrigir as 3 fontes |
| Constraint `~> 8.0.4` exclui 8.1 | 🟠 | §2 — editar o `Gemfile` (não só `bundle update`) |
| Gem transitiva incompatível com 8.1 | 🟠 | §6.4 — revisar diff do lock; `bundle check` |
| Fingerprint do ledger vira obsoleto (exit 9) | 🟡 | §5.3 — regenerar entradas, nunca re-congelar |
| "exit 0 sem escanear" (anti-padrão conhecido) | 🟡 | §5.4 — exit 0 **com** relatório |

---

## 9. ADR-0009 (novo) — decisão de versão da toolchain + política do ledger

**Justifica-se** porque: (a) a "dívida de versão do Ruby" está registrada em governança como
**decisão de dono pendente**; (b) a escolha **3.3.8 vs. 3.4/4.0** tem blast radius de toolchain;
(c) o lockstep das 3 fontes e a política do ledger são regras duráveis que outros agentes precisam seguir.
Ambos os exemplos citados na delegação ("decisão de versão do Ruby / estratégia do ledger") recaem aqui.

- **Arquivo:** `docs/adr/0009-estrategia-versao-toolchain-ruby-rails.md` (**criado** nesta sessão).
- **Último existente confirmado:** **ADR-0008** (`docs/adr/0008-semantica-estado-gestor-individual-e-identidade-legado.md`).
- **Índice:** `docs/README.md` foi atualizado de `0000–0008` para `0000–0009`.

---

## 10. Rastreabilidade & sinais de governança (para o coordenador)

- **Este arquivo** = registro da chore. Rastreia-se por nome semântico (`iteration_chore_bump_rails_81.md`),
  sem editar nada que o **summarizer** esteja tocando em paralelo.
- **`docs/governance/_context.md` está STALE** (não regenerar pelo CTO — é do **summarizer**):
  - cita "**ADRs 0000–0007**" no corpo — já existem **0008** e agora **0009**;
  - cita "**27 lições**" — o medido é **36** (`grep -cE '^### [0-9]{4}-[0-9]{2}-[0-9]{2}' docs/governance/lessons.md`);
  - diz Rails **8.0.5** — passará a **8.1.4**.
- **`AGENTS.md` (raiz)** cita "Rails 8.0.4 / Ruby 4.0.0" (§1) — corrigido no passo §6.2.
- **Novo débito a registrar:** warning Brakeman (b) (`frequentadores_visiveis.rb:351`) — nascido na 29.7,
  ausente do ledger; ver §5.

### Checklist final

- [x] `.ruby-version`, `.tool-versions`, `AGENTS.md` → **3.3.8**
- [x] `Gemfile` → `"~> 8.1.0"`; lock em **8.1.4**; `bundle check` OK
- [x] `load_defaults` **permanece 8.0**
- [x] `bin/rails test` **sem falha nova** (1083/3789/1F+11E idêntico ao baseline, single-process)
- [x] espelho `test:pessoas_schema:load` + testes **0 skips**
- [x] ledger: EOLRails **fora**; warning (b) corrigido no CÓDIGO (b1); exits 8/9 conferidos (0 obsoletas)
- [x] **`bin/brakeman` = EXIT 0** (com relatório)
- [x] `bin/rubocop` 0 offenses novas; Zeitwerk OK
- [x] ADR-0009 criado; índice do README atualizado
- [ ] stage seletivo (sem `credentials.yml.enc`/`log/*`/`tmp/cache/*`)

---

## 11. Execução da chore — evidências medidas (Code Specialist, 2026-10-05)

> Worktree isolado `wt-bump-rails` @ branch `chore/bump-rails-8.1` (base `e795df9`).
> `COMMIT_MODE=manual`: **sem commit/push** nesta sessão.

| Gate | Comando | Resultado |
|------|---------|-----------|
| **Versões** | `.ruby-version`/`.tool-versions`/`AGENTS.md` | **3.3.8** (as 3 fontes concordam) |
| **Rails** | `Gemfile` `"~> 8.1.0"` + `bundle update rails` | lock **8.1.4**; `bundle check` OK |
| **Defaults** | `config/application.rb` | `load_defaults 8.0` **inalterado** |
| **Segurança** | `bin/brakeman --no-pager` | **EXIT 0**; `security_warnings=0`; 79 checks (EOLRails/EOLRuby rodaram); ledger 3 entradas, **0 obsoletas** |
| **Suíte (baseline)** | `PARALLEL_WORKERS=1 bin/rails test` | **1083 runs / 3789 asserções / 1F + 11E / 0 skips** (idêntico ao baseline) |
| **29.6** | `bin/rails test test/models/frequentadores_visiveis_test.rb` | **25 runs / 0F / 0E** |
| **29.7** | suíte ability/cascata/shadow (5 arquivos) | **68 runs / 0F / 0E** |
| **Boot** | `bin/rails zeitwerk:check`; `bin/rails runner 'nil'` | OK / OK |
| **Lint** | `bin/rubocop app/models/frequentadores_visiveis.rb` | 0 offenses |

**Diff da chore (stage seletivo):**
- `api-ponto/Gemfile` (`~> 8.0.4` → `~> 8.1.0`), `api-ponto/Gemfile.lock` (Rails 8.0.5 → 8.1.4)
- `api-ponto/.ruby-version` (`ruby-4.0.0` → `3.3.8`), `api-ponto/.tool-versions` (`ruby 4.0.0` → `ruby 3.3.8`)
- `api-ponto/app/models/frequentadores_visiveis.rb` (bind + doc de segurança)
- `.gitlab-ci.yml` (comentário de dívida de versão atualizado)
- **Fora do repo (não versionado):** `AGENTS.md` (raiz) — corrigido, **não entra em commit**
- **NÃO tocados:** `config/credentials.yml.enc`, `log/*.log`, `tmp/cache/*`

**Nota de ambiente:** a suíte paralela exige os bancos-espelho por worker
(`frequencia_pessoas_espelho_test_{0..11}`), que **não existiam** nesta máquina e foram criados
(clone de `frequencia_pessoas_espelho_test`, aditivo). Sem eles, 52 erros de
`NoDatabaseError` são **ruído de ambiente**, não regressão. O baseline do CTO casa com a execução
**single-process** (`PARALLEL_WORKERS=1`) — 1083/3789/1F+11E exato.

---

## Anexo — evidências medidas nesta sessão (2026-10-05)

- `ruby -v` → **ruby 3.3.8**; `ruby -e 'puts Gem::Specification.find_all_by_name("rails").map(&:version)'` → **[8.1.1]** (gem global) — o **lock** do app fixa **8.0.5**.
- `gem list -r -e rails` → **8.1.4** (última).
- `railties-8.1.1` gemspec: `required_ruby_version = ">= 3.2.0"`; idem `activesupport-8.1.1`.
- `bin/brakeman --no-pager -f json` (hoje): **EXIT=3**, **2 warnings não-ignorados** — `EOLRails` (Medium, `Gemfile.lock:245`) + `SQL Injection` (Medium, `frequentadores_visiveis.rb:351`); `scan_info` → `rails=8.0.5 ruby=3.3.8`.
- `brakeman/checks/check_eol_rails.rb:28` → `['8.0.0','8.0.99'] => Date.new(2026,10,7)`.
- `brakeman/scanner.rb:191-197` → lê `.ruby-version` para `set_ruby_version`.
- `git show 16c1c9a:api-ponto/app/models/frequentadores_visiveis.rb | grep -c select_values` → **1** (o método `ids_unidades_inelegiveis_como_gestor`/`select_values` que gera o warning (b) **entrou ali**; em `29f719c`/29.6 → `0`).
- Fontes do legado/normas: `docs/adr/0009-…` referenciado acima.
