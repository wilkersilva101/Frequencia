# ADR-0009: Versão-alvo da toolchain (Ruby/Rails), lockstep das fontes de versão e política do ledger Brakeman

> **[⌂ Home](../README.md)**

## Status

Aceito (CTO, 2026-10-05). Origina a chore `chore/bump-rails-8.1`
(`docs/progress/iteration_chore_bump_rails_81.md`) e fecha a "dívida de versão do Ruby"
registrada em `docs/governance/_context.md` ("três fontes conflitantes, dono pendente").
Orienta o gate `scan_ruby`/`security` do `.gitlab-ci.yml`.

## Contexto

- **Três fontes de versão conflitam e nenhuma bate com o ambiente medido:**

  | Fonte | Declara | Realidade |
  |-------|---------|-----------|
  | `api-ponto/.ruby-version` | `ruby-4.0.0` | Ruby 4.0 **não existe** |
  | `api-ponto/.tool-versions` | `ruby 4.0.0` | idem |
  | `AGENTS.md` (raiz, Identidade) | "Ruby 4.0.0 / Rails 8.0.4" | defasado nas duas pontas |
  | **Medido** (`ruby -v`) | — | **Ruby 3.3.8** |
  | `Gemfile.lock` | `rails (8.0.5)`; `Gemfile` `~> 8.0.4` | confere o lock |

- **O `.ruby-version` mentiroso não é cosmético:** o Brakeman lê essa fonte para detectar a versão
  de Ruby (`brakeman/scanner.rb:191-197`). Como `4.0.0` não casa **nenhuma** faixa de
  `check_eol_ruby.rb` (a tabela termina em `['3.4.0','3.4.99']`), o check **EOLRuby nunca dispara** —
  a fonte errada **suprime** um lembrete de EOL.

- **O gate `security` está vermelho por design até o bump.** O Brakeman 8.0.5 emite
  `Unmaintained Dependency`/`EOLRails` **Medium** porque `check_eol_rails.rb:28` mapeia
  `['8.0.0','8.0.99'] => 2026-10-07`. O constraint `~> 8.0.4` do `Gemfile` **exclui** o 8.1.x.
  A política do projeto (ruling M2, `iteration_29.md`) **não aceita ignorar** `Medium` — bump é o
  tratamento.

- **Cobrir `EOLRails` no ledger é um time bomb:** qualquer baseline que embuta o warning count fica
  obsoleto quando o Rails sobe. É o motivo de o ledger carregar as flags anti-drift (exit 8/9) — o
  ledger é **registro de aceitação auditável**, não silenciador.

- **Restrição de escopo/deadline:** a chore tem 2 dias; o Rails 8.1 exige apenas `>= 3.2.0`
  (verificado na gemspec `railties-8.1.1`), logo o Ruby medido (3.3.8) **basta**.

## Alternativas Consideradas

### Alternativa A — Fixar Ruby em **3.3.8** e Rails em **8.1.x**, só nesta chore; tratar o ledger por correção
- **Prós:** mínimo blast radius; mira o gatilho (`bin/brakeman` = EXIT 0); o Ruby-alvo já é o da imagem
  do GitLab CI (`ruby:3.3.8-slim`); corre o risco de "exit 0 sem escanear" só uma vez.
- **Contras:** o projeto continua 1 minor atrás do Ruby "desejado"; deixa dívida declarada de Ruby major.

### Alternativa B — Subir Ruby para 3.4/4.0 **junto** com o Rails
- **Prós:** alinha com o que os docs *diziam* querer.
- **Contras:** blast radius de toolchain (mise/asdf/vendor bundle em `ruby/3.3.0`); o Rails 8.1 **não
  exige**; invisível para o gatilho; arriscada em 2 dias. **Rejeitada.**

### Alternativa C — Ignorar `EOLRails` no ledger (ou `-x EOLRails`/`--no-exit-on-warn`)
- **Contras:** reintroduz o anti-padrão "passa sem escanear"; rearma o time bomb. **Rejeitada** por ruling.

### Alternativa D — Ligar `config.load_defaults 8.1` na mesma chore
- **Contras:** o default `action_controller.action_on_path_relative_redirect = :raise` incide
  **exatamente** sobre as 11 falhas pré-existentes de Devise `redirect_to`, podendo transformá-las em
  exceções e **mudar o baseline**. Acopla dois riscos. **Rejeitada** para a chore.

## Decisão

> **ADOTAMOS A ALTERNATIVA A.** A chore `chore/bump-rails-8.1` fixa **Ruby 3.3.8** e **Rails 8.1.x
> (alvo 8.1.4)**, mantém `load_defaults 8.0`, e resolve o gate corrigindo o **código ou o ledger** —
> nunca cobrindo `EOLRails`.

Regras:

1. **Versão-alvo do Ruby = 3.3.8** (o medido). **Lockstep obrigatório** das 3 fontes:
   `.ruby-version` = `3.3.8`; `.tool-versions` = `ruby 3.3.8`; `AGENTS.md` (raiz) = "Ruby 3.3.8".
   A migração de Ruby **major** (3.4/4.0) é chore própria, fora deste escopo.
2. **Versão-alvo do Rails = 8.1.x, patch mais recente (8.1.4).** Constraint do `Gemfile`:
   `"~> 8.1.0"`. Exige **editar o `Gemfile`** (o `~> 8.0.4` bloqueia o 8.1) + `bundle update rails`.
3. **`config.load_defaults` permanece `8.0`** na chore. `new_framework_defaults_8_1.rb`, se
   materializado, entra **100% comentado** (registro). Adoção dos defaults é incremental e futura; o
   default #4 (`action_on_path_relative_redirect = :raise`) só depois de cobrir as 11 falhas Devise.
4. **O ledger `config/brakeman.ignore` é registro de aceitação** (ruling M2 vigente): `Weak` de tipo
   genérico só entra com `note` citando motivo/débito/data; `Medium`+ e dependência/versão **nunca**
   entram — são tratados estruturalmente. `EOLRails` **não** é coberto: é removido pelo bump.
5. **O bump é necessário mas não suficiente para o gate**: um 2º warning `SQL Injection` Medium
   (`frequentadores_visiveis.rb:351`, nasceu no `16c1c9a`/29.7) precisa ser **corrigido** (via
   `sanitize_sql_array`/`Arel.sql` consciente) **ou aceito no ledger com `note`** — o acréscimo ao
   ledger é **escopo da chore**, não uma exceção a ela.
6. **Prova de execução do gate:** `bin/brakeman` = **EXIT 0 com relatório gerado** (a lição
   "exit 0 sozinho não prova execução" vale como guarda). Exits 8/9 (anti-drift) conferidos.
7. **Critério de aceite da chore:** `bin/brakeman` EXIT 0 **e** `bin/rails test` **sem falha nova** vs.
   baseline **1083/3789/1F+11E** (12 pré-existentes: 11 Devise `redirect_to` + 1 timezone em
   `presenca_endpoints_test.rb`). Validado **localmente** (runner GitLab offline).

## Consequências

### Positivas
- O gate `security` fica **verde de fato** (não por silenciamento) — o `Medium` de EOL é eliminado
  estruturalmente pelo bump, não escondido.
- As 3 fontes de versão passam a **concordar** com o ambiente e com a imagem do CI.
- `EOLRuby` **volta a ter sinal** (a fonte deixa de mentir), e o workflow GitHub (`ruby-version: .ruby-version`)
  passa a resolver `3.3.8` naturalmente.
- A estratégia "bump primeiro, defaults depois" mantém o baseline estável e facilita o bisect.

### Negativas / Trade-offs
- O projeto permanece 1 minor atrás no Ruby (dívida declarada, não escondida).
- A adoção dos 6 defaults do 8.1 fica **adiada** — nova chore/feature (dono a definir, sugerido CTO/CS).
- Se optar por **(b2)** (ledger) para o warning da 29.7 em vez de corrigir o SQL, o ledger cresce 1
  entrada e há um re-review pendente do código da 29.8.

### Neutras
- Não altera migrations, schema do Pessoas, nem a semântica de autorização da Sprint 29.
- Não muda a idempotência da 29.3 nem o mapeamento `id_legado`.

## Compliance

- `.ruby-version`, `.tool-versions` e `AGENTS.md` devem citar **3.3.8**; `Gemfile` `~> 8.1.0`; lock **8.1.4**.
- `config/application.rb` mantém `load_defaults 8.0` até a adoção incremental documentada.
- `config/brakeman.ignore` **não** contém `EOLRails` nem qualquer entrada sem `note`.
- `bin/brakeman` = EXIT 0 **com relatório**; suíte sem falha nova vs. o baseline congelado.
- Qualquer futuro `Medium`+ não entra no ledger — é corrigido ou vira ADR/ruling.

## Notas

- ADRs relacionados: 0008 (semântica de estado do gestor individual), 0001 (integração com Pessoas).
- Fontes: `docs/progress/iteration_chore_bump_rails_81.md`; `iteration_29.md` §Ruling M2 / §Triagem Fase 2;
  `docs/governance/_context.md` ("Dívida de versão do Ruby"); `bin/brakeman`;
  `brakeman/checks/{check_eol_rails,check_eol_ruby,eol_check}.rb`; `brakeman/scanner.rb`.
- Ambiente medido (2026-10-05): Ruby **3.3.8**; gem global rails **8.1.1**; lock **8.0.5**; remoto **8.1.4**;
  `.gitlab-ci.yml` usa `image: ruby:3.3.8-slim`.
