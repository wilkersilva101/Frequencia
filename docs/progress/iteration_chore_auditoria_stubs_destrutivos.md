# iteration chore: auditoria dos `remove_method` destrutivos + remoção da blindagem da 29.4

> **Modo:** AGILE | **Branch:** `chore/auditoria-stubs-destrutivos` | **Data:** 2026-10-01
> **Base:** `integration/sprint-29` @ `eb38b1e`
> **Worktree:** `wt-audit-stubs/` (isolado; não tocar nos demais worktrees)
> **Tipo:** chore (correção de TESTE — sem alteração de código de produção `app/`).
> **COMMIT_MODE=manual** (sem commit/push nesta etapa).
> **Rastreabilidade:** débito 🟠2 do commit `eb38b1e`; sugestão ao CTO no mesmo commit
> ("auditar outros `remove_method` em stubs — hoje são seguros porque stubam métodos PRÓPRIOS").
> **Correção desta chore:** essa sugestão estava **subestimada** — há vazamentos reais.

---

## Tarefa A — remover a blindagem local da 29.4 (gatilho cumprido)

### Diagnóstico
`test/models/autorizacao_frequencia_test.rb` capturava `SCOPE_ATIVOS_REAL` no load e o reinstalava no
`setup` se `Pessoas::Vinculo.respond_to?(:ativos)` fosse `false`. Era contorno para o stub destrutivo
de `dashboard_controller_test.rb` (que fazia `remove_method(:ativos)` num scope Rails). O commit
`eb38b1e` corrigiu a causa-raiz → a blindagem virou no-op.

### Patch
Removidos: a constante `SCOPE_ATIVOS_REAL`, o método `restaurar_scope_ativos!` e a chamada no `setup`.
Mantido apenas `skip_sem_espelho!` (legítimo). Nenhuma referência residual (grep = 0).

### Como testar / prova
- `dashboard_controller_test.rb` + `autorizacao_frequencia_test.rb`, **8 seeds (1..8)**: 43 runs /
  120 assertions / **0F/0E** em todas (o sintoma original era order-dependent; ≥6 seeds exigido).
- Arquivo da 29.4 **sozinho**: 37 runs / 90 assertions / 0F/0E.

### Riscos
Baixo. A blindagem só agia em estado já corrompido; a causa-raiz foi eliminada em `eb38b1e`.

---

## Tarefa B — auditoria dos `remove_method`

### Diagnóstico (a sugestão anterior estava ERRADA por ordem de magnitude)

A afirmação "os outros `remove_method` são seguros porque stubam métodos PRÓPRIOS, não scopes Rails"
**está errada**: "método próprio" (`def self.` de produção) e "scope Rails" são **ambos métodos de
singleton da própria classe** — `remove_method` mata os dois igualmente. Medido por probe: o
`remove_method` mata **todo** método definido na própria classe (scope ou `def self.`); só é inócuo
para métodos **herdados** do ORM (ex.: `find_by`), onde cai de volta no ancestral.

### Medição (probe determinístico, order-independente via `Minitest.after_run`)

Classificação por medição (`singleton_class.instance_method(m).source_location` e
`method_defined?(m, false)`), com o padrão real dos testes (`define_singleton_method` → `remove_method`):

| Método | Classe | Classificação (medida) | `remove_method` mata? |
|---|---|---|---|
| `Pessoas::CategoriaTrabalhador.em_uso` | scope Rails (`categoria_trabalhador.rb:21`) | **scope** | **SIM** |
| `User.ativos` | scope Rails (`user.rb:54`) | scope — **não stubbado em lugar nenhum** (ver nota) | SIM (mas não ocorre) |
| `Pessoas::Vinculo.ativos` | scope Rails (`vinculo.rb:22`) | scope | SIM |
| `frequentadores_ativos`, `unidades_por_vinculo`, `cpfs_por_nome`, `orgaos_em_uso`, `cpfs_por_orgao` | `def self.` (`vinculo.rb`) | **produção** | **SIM** |
| `pares_matricula_cpf_para` | `def self.` (`gestorh_contracheque_mirror.rb:18`) | **produção** | **SIM** |
| `por_user` | `def self.` (`pessoa.rb:18`) | produção | SIM |
| `buscar_por_cpf` | `def self.` (`pessoas/user.rb:23`) | produção | SIM |
| `mais_recente` | `def self.` (`resolver_cpf_por_matricula_service.rb:26`) | produção | SIM |
| `call` (ImportarGestoresIndividuaisService / CalculoDiarioService / SyncDigitaisService) | `def self.` de services | produção | SIM |
| `find_by` | **ancestral** do ActiveRecord (`core.rb:283`) | ORM | **NÃO** (volta ao ancestral) |
| `new` | ancestral (Class) | ORM | NÃO |

> **Correção de escopo ao briefing:** o briefing listava `User.ativos` como removido. **Medido: NÃO.**
> Nenhum `remove_method`/`define_singleton_method` toca `User.ativos` em `test/`. O "User.ativos" do
> briefing provavelmente confundiu `Pessoas::Vinculo.ativos` (o do `dashboard_controller_test`) com o
> scope local. `User.ativos` tem 5 consumidores em produção, mas **não há vazamento dele**.

### Vazamentos PROVADOS (arquivo ofensor roda sozinho → método some no `after_run`)

| # | Arquivo | Método(s) que vazam | Evidência |
|---|---|---|---|
| 1 | `test/controllers/users_controller_test.rb` | `Pessoas::Vinculo.frequentadores_ativos` | `respond=FALSE` no after_run |
| 2 | `test/controllers/admin/users_controller_test.rb` | `Pessoas::Vinculo.frequentadores_ativos` | idem |
| 3 | `test/controllers/admin/authorization_matrix_test.rb` | `Pessoas::Vinculo.frequentadores_ativos` | idem |
| 4 | `test/controllers/admin/frequencia_por_orgao_controller_test.rb` | `orgaos_em_uso`, `cpfs_por_orgao` | idem |
| 5 | `test/controllers/admin/frequentadores_controller_test.rb` | `frequentadores_ativos`, `unidades_por_vinculo`, `CategoriaTrabalhador.em_uso`, `pares_matricula_cpf_para` | idem |
| 6 | `test/controllers/time_records_controller_test.rb` | `Pessoas::Vinculo.cpfs_por_nome` | `respond=FALSE` no after_run |
| 7 | `test/services/resolver_cpf_por_matricula_service_test.rb` | `pares_matricula_cpf_para` | idem |
| 8 | `test/jobs/importar_servidores_unidade_job_test.rb` | `pares_matricula_cpf_para` | idem |

**A/B discriminador (live victim)**: rodando `time_records_controller_test.rb` +
`resolver_cpf_por_matricula_service_test.rb` + `tmp_victim_test.rb` (chama os métodos reais):
- **sem o fix (baseline git-stash):** 2 failures — `cpfs_por_nome MORTO`, `pares MORTO`.
- **com o fix:** 0 failures.

### NÃO vazam (medido) — não mexidos

| Arquivo(s) | Motivo medido |
|---|---|
| `test/jobs/importar_dados_pessoa_job_test.rb`, `sincronizar_afastamentos_job_test.rb` | só stubbam `find_by` (ancestral AR) — `remove_method` desfaz o stub |
| `test/services/importar_gestores_individuais_service_test.rb`, `test/lib/frequencia_importar_gestores_individuais_rake_test.rb`, `test/jobs/importar_gestores_individuais_job_test.rb`, `test/models/user_test.rb`, `test/controllers/*/sessions_controller_test.rb`, `test/controllers/sessions_controller_test.rb`, `test/controllers/presencia/iniciar_ponto_controller_test.rb`, `test/integration/presenca_endpoints_test.rb` | **já restauram** via capturar/restaurar (`Method`/`UnboundMethod`) — medido: `source_location` volta a `app/...` |
| `test/services/intranet/sync_digitais_service_test.rb`, `test/jobs/sync_digitais_job_test.rb` | já restauram `call`/`new` (medido) |

### Patch (padrão de `eb38b1e` — capturar/restaurar `UnboundMethod`, não outro padrão)

Novo helper compartilhado `test/support/class_method_stub_helper.rb`, incluído na base de testes
(`ActiveSupport::TestCase`, herdado por `ActionDispatch::IntegrationTest`/`ActiveJob::TestCase`):

```ruby
com_metodo_de_classe_stubado(owner, metodo, corpo) { ... }
com_metodos_de_classe_stubados([[owner, metodo, corpo], ...]) { ... }
# captura singleton_class.instance_method(metodo) no início e faz
# define_method(metodo, original) no ensure (roda inclusive sob falha/erro).
```

**Justificativa do helper (reduz código real):** o padrão se repetia em 12+ pontos; o helper elimina o
par `define_singleton_method`/`remove_method` e o risco de esquecer a restauração. **Não** é criação de
abstração sem uso: 8 arquivos passaram a usá-lo. Para métodos **herdados** do ORM (`find_by`) o
`define/remove` local foi **mantido** — o helper só serve para métodos OWN (documentado no arquivo).

Arquivos alterados: os 8 vazadores acima + `test/jobs/calcular_frequencia_job_test.rb` (o `ensure`
reinstalava um **wrapper** que chamava o original — override permanente no singleton; trocado pelo
helper, que restaura o método de produção real) + comentário enganoso em
`test/lib/frequencia_importar_gestores_individuais_rake_test.rb`.

### Como testar / prova

- Probe `Minitest.after_run` em cada offensor (antes: `MORTO`; depois: `source_location` =
  `app/...` ou gem). Scan dos 19 arquivos com `remove_method`: **0 vazamentos** após o fix.
- A/B victim (acima): 2 failures → 0.
- `test/models` + `test/controllers/admin`: **563 / 1903 / 0F / 0E** (baseline 518/1800/0 + 45 runs
  dos diffs da Fase 2; 0F/0E).
- `test/controllers` (todos): **268/1352/1F+11E/1skip** = baseline exato (1 timezone pré-existente +
  11 erros pré-existentes de `redirect_to`).
- `test/jobs`+`test/services`+`test/lib`: 205/605/0F/0E.
- Suíte completa: **986/3398/2F+11E/1skip** = baseline canônico Fase 2 **exato**.
- RuboCop nos arquivos alterados: **0 offenses**. Zeitwerk: OK.

### O que foi MEDIDO vs. SUPOSTO
- **MEDIDO:** classificação (source_location + own-method), vazamento por arquivo (after_run probe),
  A/B victim, source_location pós-fix aponta produção, totais de suíte, RuboCop/Zeitwerk.
- **SUPOSTO:** que a suíte completa (paralelizada por arquivo) possa mascarar contaminação
  cross-arquivo — mesmo fenômeno documentado em `eb38b1e`; a prova determinística é o probe + A/B serial.

### Riscos
Baixo. Só arquivos de teste; sem produção. O helper replica o padrão já homologado. Casos de métodos
herdados do ORM mantêm o padrão local (seguro por medição).

### Pendências / débitos
| Débito | Dono | Critério de pronto |
|---|---|---|
| Avaliar adoção do helper nos restantes que "já restauram" (padronização; hoje corretos) | Code Reviewer / CTO | decisão de padronização |
| Adicionar regra ao RuboCop que barre `remove_method` em stubs (prevenção) | CTO | regra customizada avaliada |

### 🧭 Decisões do CTO — sugestões (a) e (b) (2026-10-01)

> Ruling sobre as duas sugestões que sobraram da auditoria. Medições desta rodada: helper usado por **10 arquivos**; ainda há **8 arquivos** com restauração manual e **~4 variantes** de escrita (capturar `Method` + `remove_method`/`define` + `ensure`; `define` + `ensure define_method(original)`; `SCOPE_ATIVOS_REAL` no load + `teardown`; `alias_method`/`alias_method`). Nenhum dos 8 vaza hoje (medido na auditoria) — a padronização é **cosmética**.

**(a) Padronizar o helper nos 8 que "já restauram" → AGENDAR (chore de baixa prioridade).**
- **Não fazer agora.** Valor = consistência apenas; risco = tocar 8–10 arquivos de teste que hoje funcionam, em branch (`integration/sprint-29`) com worktrees paralelos ativos (conflito garantido).
- **Dono:** Code Specialist (fluxo AGILE). **Gatilho binário:** a chore entra **quando um desses 8 arquivos for tocado por outro motivo** (bundle) **ou** na primeira suite-hygiene pós-merge da Sprint 29. Não abrir chore dedicada só para isso.
- **Nota de escopo:** o helper **não** serve para métodos herdados do ORM (`find_by`/`new`) — esses **mantêm** o par `define_singleton_method`/`remove_method` local (documentado no próprio helper). A padronização não toca esses casos.

**(b) Regra RuboCop custom que barre `remove_method` em stubs → AGENDAR como chore de PREVENÇÃO (a mais valiosa das duas).**
- **Valor desproporcional: SIM.** O bug mordeu **duas vezes** na mesma sessão (dashboard `Pessoas::Vinculo.ativos` em `eb38b1e`; os 8 arquivos desta auditoria). É uma **classe** de bug (stub destrutivo → contaminação order-dependent da VM compartilhada), silenciosa e de diagnóstico caro. Prevenção vale mais que a padronização cosmética.
- **Viabilidade (medida):** RuboCop **1.88.2** presente no bundle; o projeto **ainda não tem** cop custom (`.rubocop.yml` só faz `inherit_gem: rubocop-rails-omakase`; não há `lib/rubocop/` no app). Um cop custom exige: arquivo do cop + `require:` no `.rubocop.yml` + registro de departamento/`Cops` — **custo baixo, mecânica conhecida**, sem gem nova.
- ⚠️ **Risco de falso-positivo (por isso um cop ingênuo é RUIM):** um cop que barra **todo** `remove_method` marcaria os casos **legítimos e seguros** de métodos **herdados do ORM** (`Pessoas::Pessoa.define_singleton_method(:find_by)` + `remove_method(:find_by)` em `importar_dados_pessoa_job_test.rb`, `sincronizar_afastamentos_job_test.rb`), onde o `remove_method` **cai de volta no ancestral** e é o comportamento correto. **Distinguir OWN de herdado não é decidível estaticamente** (depende de `scope`/`def self.` do model).
- **Desenho recomendado (evita a classe de FP):** cop **config-driven com allowlist explícita** das exceções ORM conhecidas (`find_by`, `new`, …) — barra `remove_method` fora da allowlist; ou, alternativamente (mais barato e determinístico), um **meta-teste de suíte** (probe `Minitest.after_run` sobre `source_location` dos métodos OWN conhecidos, falha se algum apontar fora de `app/`/gem) — o mesmo probe que a auditoria já usou. Ambos resolvem; o cop ganha por rodar no gate `quality` do CI.
- **Dono:** **CTO (desenho do cop)** + Code Specialist (implementação). **Gatilho binário:** implementar **junto/antes da 29.6** — a 29.6 introduz testes NOVOS (propriedade + contagem de queries) que tendem a stubar, e é exatamente o ponto de exposição apontado no review da 29.4. Se a 29.6 usar o helper (já disponível), o risco cai, mas o cop fica como rede.
- **Pendente de aprovação do dev:** aceitar cop (com allowlist) **vs.** meta-teste; e se o gate `quality` do CI passa a **reprovar** por isso (hoje `quality` é `allow_failure: true` no `.gitlab-ci.yml`) ou só alerta.

## Arquivos alterados
- Tarefa A: `api-ponto/test/models/autorizacao_frequencia_test.rb`
- Tarefa B: `api-ponto/test/support/class_method_stub_helper.rb` (novo), `test/test_helper.rb`,
  e 10 arquivos de teste (os 8 vazadores + `test/jobs/calcular_frequencia_job_test.rb` +
  `test/lib/frequencia_importar_gestores_individuais_rake_test.rb`)
- `docs/governance/lessons.md` (lição) e esta rastreabilidade.

Sem alteração em código de produção (`app/`).
