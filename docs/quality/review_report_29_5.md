# Relatório de Revisão — Tarefa 29.5 (Regra de elegibilidade para desconsiderar um dia)

## Metadados

| Campo | Valor |
|-------|-------|
| Revisor | Code Reviewer (AI Workflow) |
| Data | 2026-10-02 |
| Iteração | Sprint 29 |
| Tarefa | 29.5 — `ElegibilidadeDesconsideracao` |
| Branch origem | `feature/demanda-29-5-elegibilidade-desconsiderar` |
| Base | `integration/sprint-29` @ `edb9d9f` |
| Worktree | `wt-29.5` |
| TASK_MODE / COMMIT_MODE | STANDARD / manual |
| SUGGESTION_LEVEL / BUG_LEVEL | 1 / 1 |

### Arquivos revisados

| Arquivo | Δ | Situação |
|---------|---|----------|
| `api-ponto/app/models/elegibilidade_desconsideracao.rb` | NOVO | PORO de consulta/decisão |
| `api-ponto/app/models/autorizacao_frequencia.rb` | +27/-0 | aditivo puro (`gestor_de_orgao_do?`) |
| `api-ponto/test/models/elegibilidade_desconsideracao_test.rb` | NOVO (24 testes) | |
| `docs/progress/iteration_29.md`, `docs/governance/lessons.md` | docs | rastreabilidade |

**Fora de escopo (ignorados):** `api-ponto/log/test.log`, `api-ponto/tmp/cache/*` (trackeados, inflam, não entram em commit).

## Veredito: ✅ APROVADO — sem blockers

Entrega técnica fiel à D5 e ao legado, cláusula a cláusula. Commit **desbloqueado** (COMMIT_MODE=manual: aguarda ação do dev). Todas as mutações críticas reproduzidas morrem. Achados não-bloqueantes abaixo.

- Blockers: **0**
- Sugestões: **3** (Melhoria: 2 / Débito: 1)
- Elogios: **4**

---

## Verificação célula a célula

### 1. Fidelidade ao legado `podeDesconsiderarFrequencia` (Java linhas 91-108)

Fonte lida diretamente: `intranet/src/modules/presenca/services/RegistroFrequenciaServices.java:91-108`.

| # | Cláusula do legado | Implementação (`elegibilidade_desconsideracao.rb`) | Situação |
|---|---------------------|-----------------------------------------------------|----------|
| 1 | `dia.getRegistros()!=null && size>0` | `return false if dia.registros.empty?` (:68) | ✅ fiel |
| 2 | `!meta==0` | `calculo.meta_segundos.to_i.zero?` (:73) | ✅ fiel |
| 3 | `!isFalta()` | `calculo.falta?` (:74) | ✅ fiel |
| 4 | `!isFaltaCompensada() \|\| isFaltaADescontar() \|\| isDescontadoEmFolha()` | `calculo.falta_compensada? \|\| falta_a_descontar? \|\| descontado_em_folha?` (:75) | ✅ fiel (inócuo hoje — ver §3) |
| 5 | loop: `!registro.getHorario().equals(DESCONSIDERADO)` | `dia.registros.any?(&:desconsiderado?)` (:81) | ✅ fiel |
| 6 | `usuario.isGestorOrgao(lotacaoAtual)` | `AutorizacaoFrequencia#gestor_de_orgao_do?` → passo 5 (:90) | ✅ fiel à D5 |
| 7 | `!gestorEhMesmoFrequentador` + ramo magistrado | `mesmo_frequentador?` com guard `frequentador_do_acionador.nil?` (:86, :123-152) | ✅ fiel |

Ordem conferida contra o Java. A **cláusula 6 usa SOMENTE o passo 5** (`hierarquia?`), nunca `pode_ver?`. Confirmado no código e por mutação.

### 2. Cláusula de gestor é fiel à D5 (prova)

- `gestor_de_orgao_do?` chama direto `hierarquia?` (passo 5). **Não vaza** passo 1 (próprio), 2 (admin/role geral), 3 (terceirizado) nem 4 (gestor individual).
- Mutação `gestor_de_orgao_do? → pode_ver?` (violaria a D5): **2 falhas** — morreu (testes "D5: gestor individual (passo 4) VE ... mas NAO pode desconsiderar" e "D5: admin/role geral (passo 2) VE mas NAO desconsidera").
- Mutação `gestor_de_orgao_do? → true`: **5 falhas** — morta.
- **Auto-bloqueio por `Frequentador`** (não por `User`/CPF): com o método `mesmo_frequentador?` substituído integralmente por comparação CPF-string, o teste "(acionador e alvo são Users DIFERENTES que resolvem para o mesmo Frequentador)" falha — morta.
- **Ramo magistrado** (`frequentadorDoGestor == null` → não aplica auto-bloqueio): remover o guard `return false if frequentador_do_acionador.nil?` produz **1 erro** (NoMethodError em acionador sem frequentador) — morta.

### 3. Cláusulas de `falta_a_descontar`/`falta_compensada`/`descontado_em_folha` (decisão sobre código hoje inócuo)

Reproduzi o buraco por conta própria:

- `calculo_diario_service.rb:23-25` declara os três campos como pertencentes à consolidação mensal.
- **Busca por escritores de produção:** `grep` por `falta_a_descontar\s*[:=]`, `falta_compensada\s*[:=]`, `descontado_em_folha\s*[:=]` em `app/` e `lib/` → **zero ocorrências**. Nenhum código de produção escreve os três campos.
- `ConsolidacaoMensalService` (Sprint 17, **existe e roda** via `CalcularFrequenciaJob`) agregra em `RegistroMensalFrequencia` (`faltas`, `saldo_liquido`, etc.) mas **não** escreve os três booleans em `calculo_diarios`. Ou seja, o buraco é real e persiste mesmo com a consolidação mensal atual.

**Avaliação:**
- **(a) Implementar código sabidamente inócuo é a decisão certa?** Sim. A alternativa (omitir as 3 cláusulas) seria *menos* fiel ao legado e, no dia em que os campos passarem a ser preenchidos, o gate **liberaria indevidamente** um dia descontado em folha — falha aberta. Manter as 3 cláusulas é *fail-closed* e não custa nada hoje. Correto.
- **(b) O teste `motor_nao_preenche_*` (:140-151) é guard legítimo ou documento?** É um **guard fraco**. Ele chama `CalculoDiarioService.calcular` direto e verifica que os 3 campos ficam `false`; **não** exercita `ConsolidacaoMensalService.consolidar`. Como o snippet Java (referência do "descontado em folha") corresponde à consolidação mensal, o guard falso-verde permanecerá verde mesmo se a consolidação passar a preencher os campos. Serve como *documento do fato de hoje*, não como alarme de regressão. Classificado como 🟠 S3.
- **(c) Existe outro campo/estado hoje que represente "descontado em folha"?** Não em `calculo_diarios`; `RetificadorBancoHoras::CREDITO_POR_DESCONTO_EM_FOLHA` é registro de retificador mensal, não estado por dia. Nada que o gate devesse consultar hoje. A decisão do agente (manter os 3 campos + declarar) é a mais defensável.

### 4. Exceção à instrução "não altere o PORO da 29.4"

- Diff de `autorizacao_frequencia.rb` é **puramente aditivo: +27/-0**. Nenhuma linha existente alterada.
- O método extraído é `gestor_de_orgao_do?`, que chama **apenas** `hierarquia?` (passo 5). Não expõe `pode_ver?` inteiro.
- Justificativa sustentada: a D5 manda **reusar** o passo 5, não reimplementar. Extrair um predicado público é a mudança mínima para isso, e evita duplicar a hierarquia (com risco de divergência). A exceção à instrução é justificada e benéfica.
- **Regressão 29.4:** `autorizacao_frequencia_test.rb` + `time_record_test.rb` = **62/143/0/0**. `pode_ver?` idêntico em comportamento; a `Ability`, o motor de cálculo e `desconsiderar!` intactos.

### 5. Onde o gate vive (contrato para a 29.7)

PORO de consulta, mesmo padrão do `AutorizacaoFrequencia` (29.4): não altera `Ability`, não acopla `TimeRecord`, não muda o motor. Contrato: consultar `pode_desconsiderar?` antes de `desconsiderar!`. Adequado para a 29.7. **Confirmado:** nenhum controller/rota/view chama `desconsiderar!`/`desconsiderar_por_predio!` (grep zerado); callers só em testes. O fluxo é código não-exposto (correção do registro em `edb9d9f` confirmada).

### 6. Mutation testing — reprodução

| Mutação | Resultado | Morreu? |
|---------|-----------|---------|
| Sem registros | 1F | ✅ |
| Meta-zero | 1F | ✅ |
| Falta | 1F | ✅ |
| Compensada/a descontar/descontado | 3F | ✅ |
| Registro já desconsiderado | 1F | ✅ |
| Auto-bloqueio removido | 2F | ✅ |
| `calculo.nil?` removido | 1E | ✅ |
| `gestor_de_orgao_do?` → `pode_ver?` | 2F | ✅ |
| `gestor_de_orgao_do?` → true | 5F | ✅ |
| Identidade CPF-string (método inteiro) | 1F | ✅ |
| Nível Frequentador removido | 1F | ✅ |
| Guard magistrado removido | 1E | ✅ |

**Nota de rigor:** a mutação "identidade por CPF-string" só morre quando substitui o **método inteiro**. A variante que troca **apenas o branch (a)** (`alvo.id == acionador.id`) por CPF-string **sobrevive** — porque o branch (b) cobre o mesmo cenário. Isso é *spurious survival* (mutação obsoleta por ramo redundante), não lacuna real. Ver S2.

### 7. Auto-bloqueio pelo próprio ponto + ramo magistrado

Ambos conferidos no Java e no Ruby. O agente **endurece** o legado num caso que ele não cobre (mesmo `User` id sem CPF) — declarado no código como deliberado, aceitável.

### 8. Reprodução do achado 4 (teste degenerado)

Reproduzi o cenário pré-correção (frequentador compartilhado via stub, MAS acionador sem hierarquia sobre o alvo): o `refute` passa **nas duas versões** (identidade correta e CPF-string) — prova que ele passava pela cláusula de hierarquia (6), não pela identidade (7), e que a mutação sobrevivia. **Achado do agente confirmado.** A correção (controle positivo: com hierarquia verdadeira sem frequentador compartilhado → libera; com frequentador compartilhado → bloqueia) é legítima e mata a mutação. Lição registrada em `lessons.md` está correta e bem formulada.

---

## Achados

### 🔴 Blockers

Nenhum.

### 🟡 Sugestões de Melhoria

**S1 — Contrato `Pessoas::Pessoa` anunciado é falso (crash, não fail-closed).**
`elegibilidade_desconsideracao.rb:60-71` (doc de `initialize`/`pode_desconsiderar?`) anuncia alvo `[User, Pessoas::Pessoa]`. Medido: com `Pessoas::Pessoa` como alvo e acionador **não-nulo**, `Dia.para(pessoa, data)` → `user.time_records` → `NoMethodError: undefined method 'time_records' for an instance of Pessoas::Pessoa` (`dia.rb:44`; `Pessoas::Pessoa` não tem `time_records`). Com acionador nulo retorna `false` (guard de entrada), mascarando o defeito nos testes. **Impacto:** a 29.7 pode confiar no contrato documentado e crashar. **Sugestão:** ou remover a menção a `Pessoas::Pessoa` (o gate é essencialmente `User`-keyed, como `TimeRecord`), ou tratar alvo não-`User` como fail-closed (`return false unless frequentador.is_a?(User)`), alinhando código e doc.

**S2 — Cobertura da identidade não isola o branch (a).**
O teste de identidade por Frequentador tem controle positivo (bom), mas não há cenário dedicado ao branch (a) [mesmo `User` id]. Consequência: a mutação que troca **apenas o branch (a)** por CPF-string sobrevive (coberta acidentalmente pelo branch (b)). **Sugestão:** caso de regressão — acionador `User` sem CPF que é o próprio alvo → bloqueia (garante o ramo do id sem CPF).

### 🟠 Sugestões de Qualidade/Débito

**S3 — `motor_nao_preenche_*` guarda só o motor diário, não a consolidação mensal.**
`elegibilidade_desconsideracao_test.rb:140-151` trava o fato chamando `CalculoDiarioService.calcular` direto. Não exercita `ConsolidacaoMensalService.consolidar` (que existe desde a Sprint 17 e roda via job), embora o conceito legado "descontado em folha" venha da consolidação. **Sugestão:** estender o guard para, após `consolidar`, assertar que os 3 campos seguem `false` — ou renomear o teste para explicitar que ele cobre só o cálculo diário.

### 🟢 Elogios

- **E1 — Fidelidade e declaração honesta do buraco:** as 3 cláusulas inócuas são implementadas *fail-closed* e o buraco é declarado no topo do PORO, no teste e na documentação da sprint. Exatamente o comportamento desejado.
- **E2 — Correção de um teste degenerado com controle positivo ao lado:** o próprio agente detectou que seu primeiro teste de auto-bloqueio passava pela condição errada, corrigiu e registrou a lição em `lessons.md`. Postura de rigor exemplar.
- **E3 — Exceção mínima e aditiva no PORO da 29.4:** +27/-0, expondo *apenas* o passo 5, evitando duplicação da hierarquia e respeitando a D5.
- **E4 — Cobertura de mutação forte:** 12/13 mutações reproduzidas mortas, incluindo as críticas (`gestor_de_orgao_do?` → `pode_ver?` e o guard magistrado).

---

## Falsos positivos refutados

- **"O fluxo está exposto / é risco de autorização em produção"** — **refutado.** `grep` em `app/controllers/`, `app/views/`, `config/routes.rb` por `desconsiderar!`/`desconsiderar_por_predio!` = **zero**. Callers só em testes. O fluxo é código de produção **não-exposto**. A correção do registro prévio (commit `edb9d9f`) está certa.
- **"A suíte completa é discriminadora de contaminação cross-arquivo"** — **refutado.** Paraleliza por arquivo. Usei A/B serial com seeds 1/7/42/6000 no arquivo-alvo (24/42/0/0 em todas) e combo serial (104/214/0/0). Sem contaminação atribuível à 29.5.
- **"A mutação CPF-string sobrevive"** — **parcialmente refutado.** Só a variante do branch (a) isolado sobrevive (ramo redundante, spurious). A substituição do método inteiro morre. Ver S2.
- **"`falta_a_descontar`/etc. são preenchidos pela consolidação mensal atual (Sprint 17)"** — **refutado.** `ConsolidacaoMensalService` existe, mas **nenhum** código de produção escreve os 3 booleans de `calculo_diarios`. O buraco declarado é real.

---

## Higiene

| Item | Situação |
|------|----------|
| `credentials.yml.enc` / `.ruby-version` / `.tool-versions` | intocados ✅ |
| `application.css` temporário | criado para a suíte; será removido ✅ |
| `Frequencia/docs` (checkout principal) | limpo (`git status docs` vazio) ✅ |
| `Frequencia/api-ponto/{credentials,log,tmp}` | modificados por *execução de testes*, não pelo escopo ✅ |
| `docs/quality/review_report_29_5.md` | novo ✅ |

## Métricas

- Alvo 29.5: **24 runs / 42 assertions / 0F / 0E / 0 skips** (seeds 1/7/42/6000 idênticos).
- 29.4 + auto-bloqueio + alvo + cálculo (serial): **104 / 214 / 0F / 0E**.
- RuboCop/Zeitwerk: reportados pelo agente (0 offenses / OK) — não reexecutados aqui.

## Ações corretivas para o commit

Nenhuma obrigatória (sem blockers). Recomendação não-bloqueante: corrigir S1 (contrato `Pessoas::Pessoa`) **antes** da 29.7 expor o fluxo, para não propagar um contrato falso.

## Certificação de entrega

Entrega técnica **aprovada sem blockers (🔴 = 0)**. Próximo passo: Code Specialist realiza o agrupamento de commits atômicos e o protocolo de entrega (COMMIT_MODE=manual — aguarda o dev). O fechamento da rastreabilidade é pré-requisito para a próxima tarefa.
