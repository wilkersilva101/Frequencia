# Review Report — Tarefa 29.4 (`AutorizacaoFrequencia` — cascata de visualização)

> **Branch:** `feature/demanda-29-4-autorizacao-cascata` (worktree `wt-29.4`, base `integration/sprint-29` @ `a7c776d`)
> **Data:** 2026-10-01
> **Revisor:** Code Reviewer (AI Workflow)
> **Propósito:** Primeira revisão da Tarefa 29.4 — verificar os 10 critérios de aceite, a blindagem da varíola de ordem e a caracterização honesta das medições.
> **Tarefas revisadas:** 29.4
> **Arquivos alterados:** `api-ponto/app/models/autorizacao_frequencia.rb` (novo, 301 linhas), `api-ponto/test/models/autorizacao_frequencia_test.rb` (novo, 36 testes), `api-ponto/app/models/pessoas/unidade.rb` (+47), `pessoas/vinculo.rb` (+16), `pessoas/pessoa.rb` (+10), `api-ponto/test/models/pessoas_unidade_test.rb` (+58), `docs/progress/iteration_29.md` (doc)
> **Fora do escopo (não revisado como mérito):** `api-ponto/log/test.log` (+407 mil linhas — ruído de execução, NÃO deve entrar em commit), `api-ponto/tmp/cache/*`.

## Veredito

> **✅ APROVADO — 0 Blockers.** A entrega técnica está correta e provada por medição independente. Os 10 critérios de aceite estão cumpridos. Nenhum defeito de produção foi encontrado. Restam 1 sugestão (🟡), 3 débitos (🟠) e elogios (🟢).

## Métricas (medição independente do revisor)

| Medição | Resultado | Confere com o autor? |
|---------|-----------|----------------------|
| `test/models/autorizacao_frequencia_test.rb` isolado | **36 runs / 84 assertions / 0F / 0E / 0 skips** | ✅ |
| `test/models` + `test/controllers/admin` | **562 / 1897 / 0F / 0E** (baseline 518/1800/0) | ✅ exato |
| Suíte completa (3 execuções) | **985 / 3392 / 2F+11E+1skip** · **985 / 2F+12E** · **985 / 2F+13E** | `runs`/`failures` ✅; `errors` variam pela varíola |
| A/B blindado (4 seeds) | **4/4 → 42 / 114 / 0F / 0E** | ✅ |
| A/B sem blindagem (6 seeds) | **5/6 limpos · 1/6 → 42 / 77 / 0F / 15E** | ❌ **o autor reportou "15 errors" como determinístico — é probabilístico** |
| N+1 da cadeia (`includes`) | **2 queries constantes** em profundidade 3 **e** 4 | ✅ provado |
| `motivo` completo (passo 5) | **16 queries fixas** (não por ancestral) | ✅ |
| RuboCop (6 arquivos) | **0 offenses** | ✅ |
| Zeitwerk | **OK** | ✅ |

## Decisão do revisor sobre a "blindagem" (`restaurar_scope_ativos!`)

**Aceitável, com ressalva registrada.** O mecanismo reinstala o `UnboundMethod` **real** de `Pessoas::Vinculo.ativos` capturado no load (`SCOPE_ATIVOS_REAL`), e **somente** quando `respond_to?(:ativos)` é falso — condição que uma suíte saudável nunca atinge.

- **Não mascara falha do código de produção** (verificado): o método reinstalado é o próprio scope do model, não uma cópia; e a lógica do PORO (que consome `.ativos`) roda igual nos dois cenários — o A/B muda **apenas o modo de falha de uma varíola alheia** (erros → verde). A contagem de **assertions é idêntica** (114) com e sem blindagem; portanto ela **não infla** o resultado.
- **Risco residual (🟠2):** se `Pessoas::Vinculo.ativos` for **legitimamente** redefinido no futuro, a blindagem ressuscitaria a versão **antiga** capturada no load — porém só no caso patológico de o método estar ausente, que ela mesma detecta. É dívida de baixo risco e curta duração: deve ser **removida** quando o teste ofensor for corrigido.
- **Conclusão:** aceitável como mitigação local da 29.4. **Não substitui** a correção da causa-raiz (🟠1).

## Caracterização honesta do número "sem blindagem"

O autor registrou **"sem a blindagem = 42 runs / 15 errors"** como se fosse determinístico. **Não é.** Medição controlada por seed (combinado `dashboard_controller_test.rb` + `autorizacao_frequencia_test.rb`, método paralelo default — que **não** forka com 42 testes):

| seed | com blindagem | sem blindagem |
|------|---------------|---------------|
| 1000 | 42/114/0 | 42/114/**0** |
| 2000 | 42/114/0 | 42/114/**0** |
| 3000 | 42/114/0 | 42/114/**0** |
| 4000 | 42/114/0 | 42/114/**0** |
| 5000 | 42/114/0 | 42/114/**0** |
| 6000 | 42/114/0 | 42/77/**15E** |

**Número correto:** *"sem a blindagem, a combinação é **order-dependent**: o teardown destrutivo de `dashboard_controller_test.rb:17` mata `Pessoas::Vinculo.ativos` para o processo, e **quando aquele teste roda antes deste arquivo** os 36 testes deste arquivo explodem com 15 erros; observado em 1 de 6 execuções controladas por seed."* O "15" é um dos modos possíveis, não o resultado fixo.

## Critérios de aceite — verificação um a um

| # | Critério | Status | Evidência independente |
|---|----------|--------|------------------------|
| 1 | D6: 5 cenários (ausente sobe+loga, inativo não libera, extinto não libera, lotação inativa, gestor ativo acima de inativa libera) | ✅ **cumprido** | 5 testes presentes e verdes (test:182/192/203/212/223) |
| 2 | Bugs 1/2 na `cadeia_ascendente` **sem consulta** | ✅ **cumprido** | `assert_no_queries` verdes (pessoas_unidade_test:126/138); `to_i` antes da comparação (unidade.rb:37-38) e `uniq.size` antes de qualquer query (unidade.rb:43); + controle negativo |
| 3 | `includes` das 3 associações + log `cpf presente & por_user→nil` | ⚠️ **parcial** | `includes` provado (2 queries constantes); log `pessoa_ausente` **implementado (impl:212) mas sem teste** → 🟡1 |
| 4 | D8: nunca `valid?` no caminho de leitura | ✅ **cumprido** | teste `sem_validar` cobre hierarquia/gestor_individual/negado (test:362) |
| 5 | Bug 16: consumir via `GestorIndividualGerenciado.ativos.where(...)` | ✅ **cumprido** | impl:130 usa `.ativos.joins(:gestor_individual).where(user_id:)`; nunca `gerenciados` |
| 6 | Semântica de `ativo` do gestor **consumida** (projeção), não recalculada | ✅ **cumprido** | usa o scope `.ativos`; nenhum recálculo de projeção no PORO |
| 7 | Testes usam o schema real (ADR-0006) | ✅ **cumprido** | `PessoasEspelhoHelper` + inserts reais; nenhum stub nos critérios de SQL |
| 8 | PORO avalia em ordem, retornando no primeiro match | ✅ **cumprido** | 4 testes de precedência verdes (test:296-324) |
| 9 | Retorna o `motivo` para auditoria | ✅ **cumprido** | `MOTIVOS` (impl:35); todos os motivos exercitados |
| 10 | Alvo sem lotação → só passos 1–4; Pessoas indisponível → nega + loga | ✅ **cumprido** | testes 10 verdes (test:261/271/280); `pessoas_indisponivel` coberto |
| + | `GestorIndividual` inativo não libera | ✅ **cumprido** | test:141 verde |

**Resultado:** 10/10 cumpridos; o critério 3 tem a implementação completa mas **um sub-item sem teste** (🟡1).

## Blockers (🔴)

Nenhum.

## Sugestões (🟡) — SUGGESTION_LEVEL=1 (Code Specialist deve corrigir)

| ID | Descrição | Tarefa | Local | Sugestão |
|----|-----------|--------|-------|----------|
| 🟡1 | O log `autorizacao_frequencia.pessoa_ausente` (critério 3 explícito) está implementado mas **não tem teste**. O teste "10: alvo sem CPF" cai no early-return por CPF em branco e **não** exercita o ramo `cpf presente & por_user → nil`. | 29.4 | `app/models/autorizacao_frequencia.rb:211-216`; `test/models/autorizacao_frequencia_test.rb:271` | Adicionar teste análogo ao `pessoas_indisponivel` (test:280): um `User` com CPF válido **sem** `Pessoas::Pessoa` correspondente, capturando o log e assertando `autorizacao_frequencia.pessoa_ausente`. |

## Sugestões de Qualidade / Débito (🟠) — CTO registra no `iteration_29.md`

| ID | Descrição | Tarefa | Local | Nota |
|----|-----------|--------|-------|------|
| 🟠1 | **A varíola de suíte NÃO está corrigida** — só contornada no arquivo novo. `dashboard_controller_test.rb:17` faz `remove_method(:ativos)` destrutivo no teardown e mata o scope de negócio `Pessoas::Vinculo.ativos` para o processo. Reproduzi **duas vítimas além deste arquivo**: `configuracoes_sistema_test.rb:72` e `pessoas_espelho_helper_test.rb:26` (NoMethodError `ativos`). A 29.6 (teste de propriedade + contagem de queries) **ficará exposta**. | chore própria | `api-ponto/test/controllers/dashboard_controller_test.rb:17` | Registrar chore de alta prioridade: trocar `remove_method` por save/restore do `UnboundMethod` original (mesmo padrão já usado em `com_por_user_levantando`), **antes** da 29.6. |
| 🟠2 | Blindagem local (`SCOPE_ATIVOS_REAL` + `restaurar_scope_ativos!`) reinstala o scope capturado no load. Aceitável hoje (ver seção acima), mas deve ser **removida** quando a 🟠1 for corrigida — senão passa a ser ressurreição de versão antiga. | 29.4 | `test/models/autorizacao_frequencia_test.rb:14,28,388-390` | Registrar como débito de limpeza atrelado à 🟠1. |
| 🟠3 | Ação de pré-implementação da D4 (**medir** a frequência real de pessoas com >1 vínculo ativo no `pessoas2`) **não foi executada** — `master.key`/DB indisponíveis. Semântica adotada ("algum vínculo ativo") é segura (direção fail-closed, não vaza dado) e está fixada por teste. | 29.4/import real | `iteration_29.md` §29.4 (Lacuna documentada) | Manter como verificação pendente antes da importação real; documentado com honestidade pelo autor. |

## Falsos positivos refutados (verificados e descartados)

| Alegação | Resultado da verificação |
|----------|--------------------------|
| "A 29.4 alterou a `Ability` (violando D1)" | **Refutado.** `git diff a7c776d` não toca `ability.rb`; `grep AutorizacaoFrequencia app/ lib/` retorna **zero** consumidores em produção — só os testes. A 29.4 é PORO de consulta puro, conforme D1. |
| "PORO em `app/models/` viola a convenção do projeto" | **Refutado.** `app/models/ability.rb` já é um PORO documentado em `models/` (CanCanCan `Ability`, não-AR). O posicionamento segue precedente existente. (Sinalização leve ao CTO: registrar a convenção "PORO de consulta em `app/models/`" vs. `app/services/`.) |
| "A blindagem mascara falha do código de produção" | **Refutado.** Reinstala o `UnboundMethod` real (não uma cópia); assertions idênticas com/sem blindagem (114); o A/B muda só o modo de erro da varíola alheia. |
| "A blindagem infla o resultado / o autor forjou os testes" | **Refutado.** Os 36 testes passam em **isolamento sem blindagem** (36/84/0) — a blindagem só importa na execução combinada com o teste ofensor. |
| "A 2ª failure (`TimeRecordsControllerTest`) é causada pelo diff" | **Refutado.** `time_records_controller_test.rb:184` falha **em isolamento** (sem os arquivos alterados) e não usa `cadeia_ascendente`/`elegivel?`/`terceirizado?`/`AutorizacaoFrequencia`. Pré-existente, ambiente/timezone (`08:00:00` vs `00:00:00`). |
| "A varíola é determinística e vale 15 erros" | **Refutado.** Order-dependent: 1 de 6 seeds controlados. Ver seção de caracterização honesta. |

## Elogios (🟢)

| ID | Elogio | Relacionado |
|----|--------|-------------|
| 🟢1 | Cobertura de teste de alta qualidade: precedência, fail-closed, controle negativo dos Bugs 1/2, e a **prova da D8** via `sem_validar` (substitui `valid?` de todo `ActiveRecord::Base` por um `raise`) — verificação direta, não por inspeção. | 29.4 |
| 🟢2 | `includes(:gestor, :gestor_substituto, :gestor_excepcional)` de fato elimina o N+1: a cadeia custa **2 queries constantes** em profundidade 3 e 4 (provado com probe temporário). | 29.4 |
| 🟢3 | Design fail-closed consistente em todo o caminho (usuário/alvo nulo, Pessoas indisponível, path corrompido) sem nunca derrubar a request. | 29.4 |
| 🟢4 | Documentação honesta da lacuna da D4 e das limitações de medição no arquivo de rastreabilidade. | 29.4 |

## O que impede o commit

**Nada funcional.** A entrega está aprovada. Restrições de **higiene de stage** (COMMIT_MODE=manual):

1. **Nunca `git add -A`.** `api-ponto/log/test.log` (+407 mil linhas — ruído das execuções) e `api-ponto/tmp/cache/*` aparecem como modificados (tracked) e **NÃO** devem entrar no commit.
2. Stage seletivo apenas dos 7 arquivos do escopo: `app/models/autorizacao_frequencia.rb`, `test/models/autorizacao_frequencia_test.rb`, `app/models/pessoas/{unidade,vinculo,pessoa}.rb`, `test/models/pessoas_unidade_test.rb`, `docs/progress/iteration_29.md`.
3. `credentials.yml.enc` / `.ruby-version` / `.tool-versions` **intocados** (verificado) — não stagear. `application.css` temporário **removido** (verificado: só `.keep` em `app/assets/builds/`).
4. 🟡1 (teste do log `pessoa_ausente`) deve ser corrigido **antes** de fechar a rastreabilidade (SUGGESTION_LEVEL=1).

## Checklist de validação (para o Code Specialist)

- [ ] Adicionar teste do log `autorizacao_frequencia.pessoa_ausente` (🟡1).
- [ ] Re-rodar `bin/rails test test/models/autorizacao_frequencia_test.rb` (esperado ≥37 runs, 0F/0E).
- [ ] Registrar 🟠1/🟠2/🟠3 como débito no `iteration_29.md` (CTO).
- [ ] Commit seletivo (7 arquivos), sem `log/`/`tmp/`; `COMMIT_MODE=manual`.
- [ ] Agrupamento de commits atômicos e protocolo de entrega (source-code-delivery-protocol).

## Nota de método (limitações desta revisão)

- Banco de dev remoto (`10.150.110.174`) inacessível; rodei contra o Postgres local com o schema do espelho (`frequencia_pessoas_espelho_test`, ADR-0006) e bundle emprestado do checkout principal. `application.css` copiado e **removido** após as medições.
- Os números de "errors" da suíte completa **variam por run** justamente pela varíola de ordem — reportei 3 execuções para mostrar a variação; as assinaturas pré-existentes (9× Sessions + 2× Passwords `redirect_to`, 1× timezone em `presenca_endpoints_test.rb`) são estáveis; a variação é 100% `NoMethodError: ativos`.
