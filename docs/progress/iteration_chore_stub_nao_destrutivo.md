# iteration chore: stub não-destrutivo em `dashboard_controller_test.rb`

> **Modo:** AGILE | **Branch:** `chore/suite-stub-nao-destrutivo` | **Data:** 2026-10-01
> **Base:** `integration/sprint-29` @ `0f1fdfd`
> **Rastreabilidade:** `iteration_29.md` §Blindagem da varíola (linhas ~383–387) e
> `quality/review_report_29_4.md` §🟠1; `quality/review_report_29_3.md` §achado 11 (a "13ª variação").
> **Tipo:** chore (correção de teste — não altera código de produção).
> **COMMIT_MODE=manual** (sem commit/push nesta etapa — o coordenador commita).

## Descrição

`test/controllers/dashboard_controller_test.rb` stubbava `Pessoas::Vinculo.ativos` com
`remove_method(:ativos)` no `teardown` (linha 17) e no helper `stub_vinculos_ativos`
(linha 21). No Rails, **scopes SÃO definidos como `singleton_class.define_method(name)`**
(`activerecord-8.0.5/lib/active_record/scoping/named.rb:174`) — logo `remove_method(:ativos)`
**não removia um stub: removia o PRÓPRIO scope de negócio** e **não o restaurava**. Resultado:
um teste que **mata um scope de negócio no processo inteiro** e contamina qualquer arquivo
rodado **depois** dele (`NoMethodError: undefined method 'ativos' for class Pessoas::Vinculo`),
de forma **order-dependent**.

O scope real (`app/models/pessoas/vinculo.rb:22`) é consumido em produção por
`app/controllers/admin/dashboard_controller.rb:31` (`Pessoas::Vinculo.ativos.count`) — a
contaminação, portanto, **falsifica** resultados de teste de outros arquivos, não o de produção.

## Causa-raiz (confirmada na fonte)

| Fato | Evidência |
|---|---|
| Scope é método de singleton definido pelo Rails | `activerecord-8.0.5/lib/active_record/scoping/named.rb:174` (`singleton_class.define_method(name)`) |
| `remove_method(:ativos)` remove o **scope real** | Probe determinístico: `respond_to?(:ativos)=false` após o arquivo rodar sozinho (abaixo) |
| Não é restaurado | Nenhuma reinstalação no arquivo original |
| Explosão é **order-dependent** | `dashboard + configuracoes_sistema`: 5 de 7 seeds → `NoMethodError`; 2 seeds limpos |

## Vítimas (arquivos que usam o scope, direta ou indiretamente)

| # | Arquivo | Como usa |
|---|---|---|
| 1 | `test/controllers/admin/configuracoes_sistema_test.rb:72` | `get dashboard_path` → controller chama `.ativos` |
| 2 | `test/lib/pessoas_espelho_helper_test.rb:26` | `pessoa.vinculos_ativos` (→ `Pessoa#vinculos_ativos`, que chama o scope) |
| 3 | `test/controllers/users_controller_test.rb:10` | `index` lista `.ativos` (via `frequentadores_ativos`) |
| 4 | `test/controllers/admin/frequentadores_controller_test.rb:12` | idem (via `frequentadores_ativos`) |
| 5 | `test/models/autorizacao_frequencia_test.rb` | PORO consome `Pessoa#vinculos_ativos`; **hoje tem blindagem local** (débito 🟠2, abaixo) |

## Patch proposto

Substituir o par `remove_method` por **capturar/restaurar** o `UnboundMethod` real — mesmo
padrão já usado na blindagem da 29.4:

```ruby
# no LOAD do arquivo (antes de qualquer teste rodar)
SCOPE_ATIVOS_REAL =
  Pessoas::Vinculo.singleton_class.instance_method(:ativos) if Pessoas::Vinculo.respond_to?(:ativos)

teardown do
  restaurar_scope_ativos!   # roda mesmo quando o teste FALHA (teardown do Minitest)
end

def stub_vinculos_ativos(lista)
  Pessoas::Vinculo.define_singleton_method(:ativos) { lista }  # NÃO remove
end

def restaurar_scope_ativos!
  return unless SCOPE_ATIVOS_REAL
  Pessoas::Vinculo.singleton_class.send(:define_method, :ativos, SCOPE_ATIVOS_REAL)
end
```

- **`Pessoas::Vinculo.stub(:ativos, lista)` (Minitest) NÃO serve:** medido — o bundle usa
  **Minitest 6.0.6**, que **não tem** `minitest/mock` nem `Object#stub`
  (`require "minitest/mock"` → `LoadError: cannot load such file`; `Object.method_defined?(:stub)` → `false`).
  Neste ambiente o `stub` do Minitest está indisponível.
- **A restauração sobrevive à falha:** o `teardown` do Minitest roda mesmo sob exceção/assertion-falha.
- **Comportamento idêntico ao de hoje:** o stub continua devolvendo a `lista` fixa durante o teste
  (controle negativo abaixo) — só deixa de ser destrutivo.

## O que foi MEDIDO vs. SUPOSTO

### MEDIDO

| Medição | Comando | Resultado |
|---|---|---|
| Reprodutor (antes do fix) | `bin/rails test dashboard configuracoes --seed {1..6}` | seeds 1/3/5/6 → `1 error` (`undefined method 'ativos'`); seeds 2/4 → limpo |
| **Probe determinístico (order-independent)** | `Minitest.after_run` após `dashboard` sozinho, original vs fix | **Original: `respond_to?(:ativos)=false`, `source=nil` (scope MORTO)**. **Fix: `respond_to?(:ativos)=true`, `source=[".../activerecord-8.0.5/lib/active_record/scoping/named.rb", 174]` → é o scope REAL, não o stub** |
| Controle negativo: stub ativo | teste temporário redefinindo `ativos` → `%w[a b c]` | `Pessoas::Vinculo.ativos == %w[a b c]`; `.count == 3`; `source_location` = arquivo do teste |
| **Restaura mesmo sob FALHA** | subclasse com `assert false` após usar o stub → `Minitest.after_run` | **1 failure registrada E o scope intacto: `respond=true source=named.rb:174`** |
| **A/B por seed (conjunto discriminante, 2 arquivos)** | `bin/rails test dashboard configuracoes --seed {1,2,3,4,5,6,6000}` | **Original: 5/7 seeds com 1 error `ativos`** (1,3,5,6,6000); **Fix: 7/7 limpo (48 assertions, 0 errors)** |
| Vítimas juntas (verde com o fix) | `bin/rails test dashboard configuracoes pessoas_espelho users frequentadores --seed {1..6}` | 6/6: 45 runs, 0 failures, 0 errors |
| Compatibilidade com 29.4 | `dashboard + autorizacao_frequencia --seed 5` | 43 runs, 0 failures, 0 errors (a blindagem da 29.4 é no-op com o fix) |
| Suíte completa | `bin/rails test [--seed 6000]` | **986/3398/2F+11E/1skip** = baseline canônico `0f1fdfd` exato |
| A/B suíte completa (baseline `a7c776d` vs. `0f1fdfd`) | `git archive` + `bin/rails test [--seed 6000]` | ambos: 2F+11E, **0 `ativos`** (a suíte completa paraleliza por arquivo e mascara a varíola) |

### SUPOSTO

- Que a suíte completa **nunca** exibe a varíola: provável (paralelização por *arquivo*); medi
  0 `ativos` em 3 execuções completas, mas o fenômeno é probabilístico — a prova determinística
  está no probe (`after_run`) e no conjunto de 2 arquivos.

## Prova determinística (o sintoma é order-dependent)

O número de testes do conjunto `dashboard + configuracoes` é **15** (< limiar 50) → roda **num
único processo**, então a ordem de seed é a **única** variável (reprodução fiel).

| Seed | Original (remove_method) | Fix (capturar/restaurar) |
|---|---|---|
| 1 | 1 error (`ativos`) | 0 errors |
| 2 | limpo | 0 errors |
| 3 | 1 error (`ativos`) | 0 errors |
| 4 | limpo | 0 errors |
| 5 | 1 error (`ativos`) | 0 errors |
| 6 | 1 error (`ativos`) | 0 errors |
| 6000 | 1 error (`ativos`) | 0 errors |

E a prova que **não depende de seed** (o scope sobrevive ao arquivo, seja qual for a ordem):
`Minitest.after_run` após rodar `dashboard` **sozinho** → original `respond_to?(:ativos)=false`;
fix `respond_to?(:ativos)=true` com `source=named.rb:174`.

## Gatilho para remover a blindagem da 29.4 (débito 🟠2)

`test/models/autorizacao_frequencia_test.rb` (setup ~linha 28) reinstala o scope
`Pessoas::Vinculo.ativos` quando detecta o vazamento — **contorno** criado quando a causa-raiz
ainda existia. **Este fix é o gatilho:** com o stub destrutivo eliminado, a blindagem vira
no-op. O coordenador pode removê-la (com o teste A/B sem ela provando verde). **Nesta tarefa ela
foi mantida de propósito** (decisão do coordenador: só sai quando o fix estiver provado).

## Arquivos alterados

- `api-ponto/test/controllers/dashboard_controller_test.rb` (único arquivo de código da chore)
- `docs/progress/iteration_chore_stub_nao_destrutivo.md` (esta rastreabilidade)

Sem alteração em código de produção (`app/`), conforme o escopo.

## Riscos

- **Baixo.** Correção limitada a um arquivo de teste; comportamento do stub preservado (controle
  negativo). A restauração roda no `teardown` (inclusive sob falha), espelhando o padrão já
  homologado na 29.4.
- **Residual:** a suíte completa paraleliza por arquivo; a prova do fenômeno depende do conjunto
  serial / do probe (documentados acima). Não é risco da correção — é limitação de medição da suíte.

## Pendências / débitos

| Débito | Dono | Critério de pronto |
|---|---|---|
| Remover a blindagem local da 29.4 (🟠2) | coordenador | A/B sem a blindagem → verde, após este fix |
| Registrar lição (scope Rails = `singleton_class.define_method`; nunca `remove_method`) | Code Specialist | `docs/governance/lessons.md` |
