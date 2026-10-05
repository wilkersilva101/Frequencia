# Relatório de Revisão — Code Reviewer — Iteração 29 — Tarefa 29.3

> **Tipo:** review_report (1ª revisão do bloco 29.3)
> **Data:** 2026-09-30
> **Branch de origem:** `feature/demanda-29-3-importacao` (worktree `wt-29.3`, base `f82c965`) → destino: integração da Sprint 29
> **Base:** trabalho **NÃO commitado** (`COMMIT_MODE=manual`; sem commit/push)
> **Revisor:** Code Reviewer (sessão independente, worktree próprio)
> **Tarefas revisadas:** 29.3 — Importação idempotente de gestores individuais do Intranet
> **Arquivos alterados/adicionados:**
> - `api-ponto/app/services/importar_gestores_individuais_service.rb` (NOVO, 324 linhas)
> - `api-ponto/app/jobs/importar_gestores_individuais_job.rb` (NOVO, 44)
> - `api-ponto/lib/tasks/frequencia_importar_gestores_individuais.rake` (NOVO, 34)
> - `api-ponto/test/services/importar_gestores_individuais_service_test.rb` (NOVO, 414)
> - `api-ponto/test/jobs/importar_gestores_individuais_job_test.rb` (NOVO, 77)
> - `api-ponto/test/lib/frequencia_importar_gestores_individuais_rake_test.rb` (NOVO, 83)
> - `docs/progress/iteration_29.md`, `docs/governance/lessons.md` (modificados)
> **Insumos:** `docs/progress/iteration_29.md` (29.3), `docs/adr/0007-...md`, models `GestorIndividual`/`GestorIndividualGerenciado`, concerns `Desativavel`/`InvarianteAutoGerencia`, migrations `20260929120000`/`20260929130000`, gem `sticapi_client-3.5.3` (`intranet.rb`).

---

## Veredito

| Escopo | Veredito | Blockers | Sugestões |
|---|---|---|---|
| **29.3 — serviço + job + rake + testes** | ✅ **APROVADO** (sem blockers; 2 decisões ratificadas com ressalva) | 🔴 0 | 🟡 3 / 🟠 1 / 🟢 3 |

**Nenhum blocker (🔴).** A entrega está **liberada para commit** (stage seletivo — ver §Higiene). As duas decisões que o autor submeteu a ratificação estão **ratificadas com uma ressalva cada** (ver §Decisões): não impedem o commit desta tarefa, mas a ressalva de (1) precisa de decisão do CTO **antes da 29.4/29.6** consumirem `GestorIndividual#ativo`. A idempotência — critério central — está **provada por medição independente** (`2ª execução = 0 criações`).

---

## Métricas medidas nesta revisão (independentes)

| Medição | Resultado medido | Declarado pelo autor | Status |
|---|---|---|---|
| Direcionados 29.3 (serviço + job + rake) | **27 runs / 97 assertions / 0 failures / 0 errors / 0 skips** | 100/272/0 (dois conjuntos) | ✅ 27 batido |
| `test/models` + `test/controllers/admin` | **518 runs / 1800 assertions / 0/0/0** | 518/1800/0 | ✅ **baseline exato** |
| Suíte completa | **923 runs / 3246 assertions / 1 failure / 11 errors / 0 skips** | 923 runs / 3243 / 12 pré-existentes | ✅ 923 batido (`3246` inclui as 3 asserções do meu harness descartável — ver nota) |
| RuboCop (6 arquivos novos) | **0 offenses** | 0 offenses | ✅ |
| Zeitwerk | **All is good!** | OK | ✅ |
| Mutação "`e.message` no lugar de `full_messages`" | **MORTA** (teste falha) | morta após reforço | ✅ confirmado |
| 13ª variação (`Pessoas::Vinculo.ativos` some) | **REPRODUZIDA sem os arquivos da 29.3** | pré-existente | ✅ confirmado |

> **Nota das assertions:** medi `923 runs / 3246 assertions`. O delta de +3 sobre as 3243 declaradas vem do meu harness descartável (`test/services/zz_review_repro_test.rb`, removido após uso). Sem ele o número bate o declarado.

**Composição dos 12 pré-existentes (confirmada, nenhum novo):** 11× `NoMethodError: private method 'redirect_to'` nos controllers Devise `users/sessions` (Sprint 23) + 1× timezone em `test/integration/presenca_endpoints_test.rb:187`. Os 923 runs = 896 baseline + 27 novos, exato.

---

## Checklist dirigido (pontos do briefing)

| # | Item | Resultado |
|---|---|---|
| 1 | **Mapeamento de identidade** (decisão 1) | ⚠️ **Correto e consistente com os índices UNIQUE** — ratificado com ressalva (risco de merge por `id_vinculo_gestor` reutilizado; ver §Decisões). |
| 2 | **Nome do gestor** (decisão 2) | ⚠️ **Aceitável** — ratificado com ressalva (risco de placeholder "grudento"; ver §Decisões). |
| 3 | **Mutação sobrevivente do Bug 8** | ✅ **Verificada e morta.** Reproduzi: mutar `full_messages`→`e.message` faz `test_erro_de_RecordInvalid...` falhar com `Expected /erro impediu este registro\|Validation failed/ to not match "registro inválido: Validation failed: Gestor cpf é inválido"`. O discriminante (wrapper `Validation failed:`/`1 erro impediu...`) é **exclusivo do `e.message`** — `full_messages` nunca o contém. Restaurei o arquivo. |
| 4 | **Idempotência** | ✅ 2ª execução = 0 criações (medido: `r1 imp=1 atu=0; r2 imp=0 atu=1`, 0 diferenças de contagem). Reimportação atualiza sem duplicar. Transição ativa→inativa e inativa→ativa **funciona** (`REPRO B`: ativo→false c/ data, →true c/ data nil, `total id_legado=1 count=1`). ⚠️ Achado 🟡2: ativo do gestor com múltiplos geridos é order-dependent. |
| 5 | **Integridade transacional** | ✅ `gestor.save!` + `vinculo.save!` numa `ActiveRecord::Base.transaction`; `RecordInvalid` faz rollback e cai no relatório (sem sucesso parcial). |
| 6 | **Invariante de auto-gerência** | ✅ Recusado e relatado (`test "auto-gerencia ativa e recusada..."` verde; vínculo de auto-gerência não é gravado). O `rescue DeleteRestrictionError, InvalidForeignKey` **não mascara** no caminho de escrita — ver 🟡3 (wording). |
| 7 | **D8** (`valid?` proibido no caminho de leitura) | ✅ `grep 'valid?'` no serviço: nenhum; só `save!` nas linhas 220/228. Nenhum `valid?` novo no caminho de leitura. |
| 8 | **`DRY_RUN=1`** | ✅ Percorre a resolução inteira, escreve nada (`assert_no_difference` verde), sem efeito colateral (só contadores/relatório; sem log por linha, sem mutação de estado). `abort` só em execução real com não-resolvidos. |
| 9 | **4 débitos da triagem** | ✅ ⚪11 (`id_legado > 0`), ⚪14 (`""`→`nil` via `presence`, sem tocar `allow_nil`), 🟢19 (`DeleteRestrictionError` + `InvalidForeignKey`), `ativo: nil` normalizado — todos cobertos e testados. |
| 10 | **Higiene** | ✅ Sem segredo/log/tmp nos arquivos novos; `credentials.yml.enc`/`.ruby-version`/`.tool-versions` intocados. ⚠️ 2 artefatos pré-existentes rastreados (ver 🟡1). |
| 11 | **13ª variação** | ✅ **Acusação confirmada.** `dashboard_controller_test.rb` + `lib/pessoas_espelho_helper_test.rb`, sozinhos, com **seeds 1 e 2** → `NoMethodError: undefined method 'ativos' for class Pessoas::Vinculo`. O teardown (`dashboard_controller_test.rb:17`) usa `remove_method(:ativos)`. Arquivo **intocado na branch** (último commit `1a73a4d`, Sprint 26). Não é regressão da 29.3. |

---

## Achados por severidade

### 🔴 Blockers

**Nenhum.**

### 🟡 Sugestões de Melhoria

**🟡1 — `api-ponto/log/test.log` e `api-ponto/tmp/cache/bootsnap/load-path-cache` aparecem como rastreados e modificados apesar do `.gitignore`.**
Arquivo: `wt-29.3/.gitignore:7-8` (`api-ponto/log/`, `api-ponto/tmp/`). Cenário: `git status` mostra os dois como `M`; foram trackeados **antes** de o `.gitignore` cobri-los, então o ignore não retroage. Sugestão: como `COMMIT_MODE=manual`, garantir que o stage do commit da 29.3 seja **seletivo** (apenas os 6 arquivos novos + os 2 `.md`), nunca `git add -A`. Débito correlato (não desta tarefa): `git rm --cached` dos dois para parar de versioná-los. **Não é blocker.**

**🟡2 — Ativo do `GestorIndividual` (uma linha por PESSOA) é sobrescrito a cada linha legada: o valor final depende da ORDEM das linhas quando o gestor tem geridos ativos E excluídos.**
Arquivo: `app/services/importar_gestores_individuais_service.rb:235-238` (`aplicar_estado`, chamado também para o gestor via `aplicar_gestor:218`) + `:211-221`. Cenário **reproduzido** (harness descartável, removido): gestor `id_legado=900` com 3 linhas legadas — 1 par ATIVO e 2 pares excluídos no legado.
- Ordem `[ativa, excl1, excl2]` → `GestorIndividual.ativo = false`
- Ordem `[excl1, excl2, ativa]` → `GestorIndividual.ativo = true`

Ou seja, **a última linha processada vence** (a `data_exclusao` da última linha define o `ativo` da PESSOA-gestor). Não há duplicação nem corrupção — o banco fica consistente —, mas o `ativo` do gestor não tem semântica definida para o caso "gestor com parte dos vínculos excluída". Impacto hoje **baixo** (a tela `admin/gestores_individuais` não lê `ativo`; ver `app/views/admin/gestores_individuais/index.html.erb` e o controller, que só listam nome/orgão/`gerenciados.size`), mas **cresce na 29.4/29.6**, que dependem de "gestor ativo" (ADR-0007, Consequências). Nenhum teste cobre este caso (o teste `reaproveita UM gestor para varias linhas` usa **todas** ativas).
Sugestão: definir a semântica e aplicá-la de forma determinística — p.ex. derivar `gestor.ativo` do conjunto de vínculos (`exists?(ativo: true)`), não da última linha — e cobrir no teste. **Recomendo resolver antes da 29.4/29.6, não necessariamente antes deste commit.**

**🟡3 — `rescue ... InvalidForeignKey` é mais largo que o necessário e o rótulo do relatório é enganoso; o `rescue StandardError` genérico transforma bug de programação em "não resolvido".**
Arquivo: `app/services/importar_gestores_individuais_service.rb:199-208`. Cenário: no caminho de escrita **não há `destroy`**, então nem `DeleteRestrictionError` (levantado só por `dependent: :restrict_with_exception` num `destroy`) nem `InvalidForeignKey` de deleção podem ocorrer ali. O único `InvalidForeignKey` plausível nesta transação seria de uma colisão do índice parcial `par_ativo` (`index_gestor_individual_gerenciados_on_par_ativo`), que sairia rotulada "violação de integridade referencial" — **wording impreciso** para "já existe um vínculo ativo deste par". Adicionalmente, `rescue StandardError` (linha 205) rebaixa qualquer `NoMethodError`/erro de programação a "não resolvido" sem sinalizar que é bug. Sugestão: manter o resgate (é defensivo e evita abortar a importação), mas (a) ajustar o texto do 🟢19 para não prometer deleção quando o caminho é insert/update, e (b) manter um ponto de escape (p.ex. só `RecordNotFound`/`RecordNotUnique`/`PG::Error` explícitos) para que erro de lógica não passe por dado legado ruim.

### 🟠 Sugestão de Qualidade / Débito

**🟠1 — Placeholder de nome pode "grudar" por causa do `||=`.**
Arquivo: `app/services/importar_gestores_individuais_service.rb:214` (`gestor.nome ||= nome_do_gestor(gestor_cpf)`). Cenário: numa execução em que `Pessoas::Pessoa.find_by` falha (banco Pessoas indisponível — o `rescue` em `:285-288` devolve o placeholder), o gestor é gravado com `"Gestor individual <CPF>"`; numa reimportação **posterior**, quando o Pessoas volta, o `||=` **não** substitui o placeholder por `nil`/pelo nome real — o dado sintético **persiste** e não é corrigível pela própria importação. Sugestão: quando a origem do nome for o fallback, não marcar como definitivo (p.ex. gravar só quando houver nome real; ou distinguir origem com um flag/coluna). Débito correlato à decisão (2).

### 🟢 Elogios

| ID | Elogio | Tarefa |
|---|---|---|
| 🟢1 | **Mutação do Bug 8 agora é morta — com prova.** O `refute_match(/erro impediu este registro\|Validation failed/, motivo)` discrimina as duas implementações; o `e.message` carrega o wrapper do `record_invalid` que o `full_messages` nunca tem. Fechou corretamente o furo de prova fraca relatado. | 29.3 |
| 🟢2 | **Correção do padrão de stub destrutivo.** Os testes novos salvam e restauram o `Method` original (`com_stub_de_classe`) em vez de `remove_method` no teardown — o padrão que envenena a suíte (🟡/13ª variação) não foi replicado nos arquivos novos. Lição registrada em `lessons.md`. | 29.3 |
| 🟢3 | **Separação limpa da lógica testável.** Serviço puro (injeção de `registros:`), job/rake como borda fina; dry-run percorre o mesmo caminho de resolução; relatório com `nao_resolvidos` enumerável (nada é engolido) e `abort` honesto em execução real. Cabeçalho da classe documenta o mapeamento de identidade e o modo de escrita (ADR-0007). | 29.3 |

---

## Decisões submetidas a ratificação

### Decisão (1) — Mapeamento de identidade — ✅ RATIFICADA, com ressalva ao CTO

`gestor_individual_gerenciados.id_legado = id` (chave do PAR) e `gestores_individuais.id_legado = id_vinculo_gestor` (chave da PESSOA-gestor). **Correto**: é o único mapeamento compatível com os dois índices UNIQUE da 29.2 (`schema.rb:108` parcial `WHERE ativo` no par; `:110` UNIQUE em `id_legado`), e é consistente com o propósito do `GestorIndividual` (uma linha por PESSOA — caso contrário N linhas duplicariam o gestor na tela). O isolamento em `encontrar_gestor`/`chave_do_gestor` permite troca sem tocar no resto.

**Ressalva (precisa de ruling do CTO antes da 29.4/29.6):** o código pressupõe que o **mesmo `id_vinculo_gestor` sempre carrega o mesmo gestor** (`encontrar_gestor` casa só por `id_legado`, `:252`). Não há guarda nem log para o caso de `id_vinculo_gestor` **reutilizado com CPF de gestor diferente**: o segundo CPF seria silenciosamente ignorado (o gestor existente é reaproveitado e `gestor_cpf` **não** é reescrito para o novo CPF — `:213` sobrescreve). Também não há garantia de que o `id` da linha legada seja único/estável — a base já terá o UNIQUE do vínculo (`:110`) como rede, então colisão viraria `RecordNotUnique` **resgatado como "não resolvido"** na reimportação (não falha dura, mas entrada duplicada no relatório). Pergunta objetiva ao CTO: *um `id_vinculo_gestor` pode ser reutilizado por outra pessoa ao longo do tempo?* Se sim, o casamento só por `id_legado` do gestor precisa de uma segunda condição (p.ex. o `gestor_cpf`). **Não bloqueia o commit da 29.3** (o cenário é hipotético e o dado legado está estável agora), mas **bloqueia a decisão de consumir `GestorIndividual` na cascata**.

### Decisão (2) — Nome do gestor — ✅ RATIFICADA, com ressalva ao CTO

O payload legado **não traz nome** (confirmado no fonte da gem `sticapi_client-3.5.3/lib/sticapi_client/intranet.rb`: campos `id data_criacao data_exclusao observacao id_vinculo_gestor matricula_gestor id_vinculo_gerido matricula_gerido`) e `nome` é `presence: true` no model. Preencher do Pessoas com fallback é razoável para não descartar uma linha legada válida.

**Ressalva:** o texto `"Gestor individual <CPF>"` é **dado sintético que se parece com dado real** — na tela não há como distinguir de um nome cadastrado. Há alternativas melhores a submeter ao CTO: (a) gravar o nome real do Pessoas e, quando ausente, um texto **explicitamente de sistema** (ex.: `"(sem nome — CPF 12345678901)"`), ou (b) registrar a origem em coluna/flag. Reforça o 🟠1 (placeholder gruda por `||=`). Não bloqueia o commit.

---

## Falsos positivos refutados

| Alegação a verificar | Resultado |
|---|---|
| "A 13ª variação é pré-existente (código que não é nosso)" | ✅ **Confirmada.** Reproduzida com `dashboard_controller_test.rb` + `lib/pessoas_espelho_helper_test.rb` sozinhos, seeds 1 e 2, **sem nenhum arquivo da 29.3**. `remove_method(:ativos)` destrutivo no teardown (`dashboard_controller_test.rb:17`); arquivo intocado na branch. |
| "A suíte completa tem 12 pré-existentes e +27 = 923 exatos" | ✅ **Confirmada.** 923 runs (896+27) / 1 failure + 11 errors. Composição idêntica (11 Devise + 1 timezone). |
| "Os testes novos não usam `remove_method` destrutivo" | ✅ **Confirmado.** Serviço, job e rake salvam/restauram o `Method` original. |
| "A mutação do Bug 8 sobreviveu na 1ª rodada e foi corrigida" | ✅ **Confirmada** — hoje a mutação é morta (ver §Checklist #3). |
| "`test/models` + `test/controllers/admin` = 518/1800/0 exato" | ✅ **Confirmado**, medição independente. |

---

## Ações corretivas

- [ ] **(Antes do commit)** Stage seletivo: incluir apenas os 6 arquivos novos + `docs/progress/iteration_29.md` + `docs/governance/lessons.md`; **não** incluir `api-ponto/log/test.log` nem `api-ponto/tmp/cache/bootsnap/load-path-cache` (🟡1).
- [ ] **(Antes da 29.4/29.6, não do commit)** Ruling do CTO sobre as ressalvas das decisões (1) e (2).
- [ ] **(Antes da 29.4/29.6, não do commit)** Definir e testar a semântica determinística de `GestorIndividual#ativo` para gestor com parte dos vínculos excluída (🟡2).
- [ ] **(Oportunístico)** Refinar o rótulo do 🟢19 e estreitar o `rescue StandardError` (🟡3); tratar o placeholder de nome "grudento" (🟠1).

**Nenhum item acima é bloqueio do commit desta tarefa.** Todas as ações pré-commit estão satisfeitas no working tree atual (a única pendência é a disciplina de stage, e `COMMIT_MODE=manual` deixa o commit ao dev).

---

## Addendum — Rulings do CTO (2026-09-30)

> Aplicado **após** este review, em `docs/adr/0008-semantica-estado-gestor-individual-e-identidade-legado.md`
> e em `docs/progress/iteration_29.md` (§🧭 Rulings do CTO — Tarefa 29.3). O conteúdo do review acima
> permanece como registro da revisão; abaixo, o que foi **decidido** sobre as três pendências.

- **Decisão (1) — identidade:** ratificada, e **fechada** o risco de id reaproveitado: divergência de
  `gestor_cpf` para o mesmo `id_legado` do gestor vira `nao_resolvido` (conflito de identidade), sem
  reescrever CPF/`gestor_user`. A reciclagem de `id_vinculo_gestor` **não foi confirmada** (hipótese a
  verificar com a TI), mas a guarda torna a decisão robusta independentemente dela.
- **Decisão (2) — nome:** adotado marcador explícito de sistema `"(sem nome — CPF <cpf>)"`, substituível
  numa reimportação com o Pessoas de volta (mata o 🟠1 "gruda" por `||=`).
- **Achado 🟡2 — semântica de `ativo`:** decidida por **evidência do legado** (`presenca_gestorindividual`
  guarda `ativo` na **linha do par**; autorização do legado = "*algum* vínculo ativo"): `GestorIndividual#ativo`
  é **projeção** (ativo sse ≥ 1 vínculo ativo), determinística, recalculada pós-loop. **A opção (c) é
  impossível** (não existe estado de gestor no legado).
- **Achado adicional do CTO — 🔴 F1:** reimportação que reative um vínculo com `id_vinculo_gestor` presente
  colidiria com o índice UNIQUE parcial — regra de reancoragem corrigida (só na criação / recriação).
- **Complemento:** **29.3-D1/D2/D3** (correções de código/teste) entram antes da 29.4/29.6, na mesma linha
  de entrega da 29.3.
