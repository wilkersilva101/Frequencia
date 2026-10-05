# Relatório Bug Finder — Sprint 29, Tarefa 29.2-D7 (concern único do invariante)

> **Branch:** `feature/demanda-29-schema-gestor-individual`
> **Data:** 2026-09-29
> **Propósito:** Teste adversarial do concern `InvarianteAutoGerencia` (`app/models/concerns/invariante_auto_gerencia.rb`) **depois** das correções dos 14 achados do Code Reviewer — alvo prioritário: `gestor = gestor.reload if gestor.persisted?` no lado do vínculo (hipótese 1), custo do `reload` em lote (hipótese 2), gestor deletado/inalcançável (hipótese 3), janelas de revalidação (hipótese 4), `ativo: nil` (hipótese 5), I18n (hipótese 6), D8/caminho de leitura (hipótese 7) e a regressão dos 4 quadrantes × 2 lados (hipótese 8).
> **Tarefas testadas:** 29.2-D7 (e o código dos models da 29.2 que o concern passou a reger).
> **Arquivos analisados:** `app/models/concerns/invariante_auto_gerencia.rb`, `app/models/concerns/desativavel.rb`, `app/models/gestor_individual.rb`, `app/models/gestor_individual_gerenciado.rb`, `config/locales/pt-BR.yml`, `app/controllers/admin/gestores_individuais_controller.rb`, `app/views/admin/gestores_individuais/index.html.erb`, `db/schema.rb`, `.gitignore` (raiz).
> **Método:** sondas temporárias em `bin/rails test` (transação do teste, nunca `runner`), removidas ao final. `api_ponto_development` intocado; `api_ponto_test` deixado com **0 linhas** em `gestores_individuais` e `gestor_individual_gerenciados`.

## Resumo

| Métrica | Valor |
|---------|-------|
| Total de cenários testados | 23 |
| Bugs encontrados | 5 |
| 🔴 Crítico | 0 |
| 🟠 Alto | 1 |
| 🟡 Médio | 1 |
| 🟢 Baixo | 0 |
| ⚪ Info | 3 |

> **Hipótese 1 é BUG REAL e está no caminho normal de escrita** (não exige bypass). É o achado bloqueante da rodada — ver Bug 1.

---

## Bugs por Severidade

## Bug 1 — `reload` do gestor no lado do vínculo descarta as mudanças pendentes do chamador e **grava vínculo de auto-gerência ATIVA** (falso negativo)

- Severidade: 🟠 Alto
- RF/RN violado: RN do invariante de auto-gerência (decisão (a) do CTO: *nenhum vínculo ATIVO liga o gestor a si mesmo*); tarefa 29.2-D7, achado 1 do Code Reviewer.
- Arquivo: `app/models/concerns/invariante_auto_gerencia.rb:85-95` (`host_tem_auto_gerencia_ativa?`).

**Passos (reprodução mínima, caminho normal da importação da 29.3 — ActiveRecord, sem bypass):**
```ruby
gestor = GestorIndividual.create!(nome: "G-Import")   # DB: gestor_user_id = nil
login  = User.create!(nome_completo: "Login Resolvido Depois", password: "123456")

g = GestorIndividual.find(gestor.id)   # carrega do banco (stale-safe: mesma instância do chamador)
g.gestor_user = login                  # resolve o login DEPOIS de carregar — AINDA NÃO SALVO

vinculo = g.gestor_individual_gerenciados.build(user: login, ativo: true)
vinculo.save                           # => true, errors=[]
```
- **Atual:** `vinculo.save` retorna **`true`** e o banco fica com um vínculo **ATIVO** ligando o gestor a si mesmo. Evidência (sonda H1c):
  ```
  [H1c] vinculo.save = true errors=[]
  [H1c] AUTO-GERENCIA ATIVA NO BANCO? true  -> FURO CONFIRMADO
  ```
  Causa: `host_tem_auto_gerencia_ativa?` faz `gestor = gestor.reload if gestor.persisted?`. O `reload` **descarta `gestor.gestor_user = login`** (mudança pendente), volta `gestor_user_id` a `nil` no objeto, e a checagem `gestor.gestor_user_id.blank?` retorna `false` → validação passada. O objeto do chamador é **mutado em lugar** (`vinculo.gestor_individual.equal?(g) == true`), então o `g.save` seguinte também não persiste o login.
- **Esperado:** `vinculo.save` deveria ser **barrado** (`errors[:user_id]` com a mensagem de auto-gerência) — que é exatamente o comportamento do controle `H1d` quando o login é salvo **antes** de montar o vínculo.

**Perda silenciosa de dados (mesma causa, medido na sonda H1):**
```ruby
g.gestor_user = login; g.nome = "Nome Pendente"; g.orgao = "Orgao Pendente"
[antes]   user=980190974  changed=["nome","orgao","gestor_user_id"]
v = g.gestor_individual_gerenciados.build(user: outro, ativo: true); v.valid?   # dispara o reload
[depois]  user=nil        changed=[]          # TODAS as mudanças pendentes sumiram
g.save  # => DB gestor_user_id = nil (esperado 980190974); nome = "G-Base" (esperado "Nome Pendente")
```
Qualquer `valid?`/`save` de um vínculo montado a partir de um gestor persistido apaga as alterações não salvas do gestor (`gestor_user_id`, `nome`, `orgao`, `observacao`).

- **Impacto:** é o **furo que o achado 1 do reviewer tentava fechar, agora invertido**: em vez de "gestor stale no banco" deixar passar (o que o `reload` deveria corrigir), a versão atual transforma "login recém-resolvido em memória" em "banco nil" e **deixa passar** a auto-gerência. O caminho é o documentado da 29.3 (reconciliação ActiveRecord: carregar gestor, resolver login, gravar vínculo). O invariante canônico é gravado violado — auto-autorização na cascata da 29.4/29.5. Não requer `update_column`/SQL direto.
- **Teste sugerido:** (a) `g = GestorIndividual.find(id); g.gestor_user = login; v = g.gestor_individual_gerenciados.build(user: login, ativo: true); assert_not v.valid?` — hoje falha; (b) contrato anti-perda: `g.nome = "Novo"; g.gestor_individual_gerenciados.build(user: outro).valid?; assert g.changed.include?("nome")` e `assert_equal login.id, g.gestor_user_id`.
- **Sugestão de correção (não implementar):** só recarregar quando o gestor **não tem mudanças pendentes** (`gestor.reload if gestor.persisted? && !gestor.changed?`) — ou melhor, quando `gestor_user_id` **não** é uma das mudanças pendentes; nunca mutar o objeto do chamador; considerar ler o valor de outra forma (ex.: consulta pontual ao banco) sem tocar a instância recebida.

## Bug 2 — `reload` de gestor apagado/inacessível levanta `RecordNotFound` cru dentro da validação

- Severidade: 🟡 Médio
- RF/RN violado: requisito de robustez da importação (critério da 29.3: "nada é silenciosamente ignorado; tratamento de `RecordInvalid`").
- Arquivo: `app/models/concerns/invariante_auto_gerencia.rb:91`.

**Passos (sonda H4b):**
```ruby
gestor = GestorIndividual.create!(nome: "G-Sumiu", gestor_user: User.create!(...))
g = GestorIndividual.find(gestor.id)
v = g.gestor_individual_gerenciados.build(user: outro, ativo: true)
GestorIndividual.where(id: gestor.id).delete_all   # outra sessão apagou / substituição de id_legado
v.valid?
```
- **Atual:** `ActiveRecord::RecordNotFound: Couldn't find GestorIndividual with [WHERE "gestores_individuais"."id" = $1]` **escapa do callback de validação**.
  ```
  [H4b] EXCECAO NA VALIDACAO: ActiveRecord::RecordNotFound: Couldn't find GestorIndividual ...
  ```
- **Esperado:** erro de validação tratado (ou o vínculo abortado de forma controlada). A exceção **não é** `RecordInvalid`, então um `rescue ActiveRecord::RecordInvalid` no import dá vazamento de exceção crua e **aborta a importação inteira** em vez de contar o item como não resolvido.
- **Impacto:** latente (exige o gestor ter sido removido/alterado por outra sessão no meio da operação); o CTO declarou que esse fluxo não é esperado na 29.3. Ainda assim, é uma exceção não tratada introduzida pelo `reload`.
- **Teste sugerido:** montar o vínculo a partir de gestor persistido, apagar o gestor, e assertar que `valid?` **não** levanta `RecordNotFound` (ou que o import resgata `RecordNotFound` explicitamente).
- **Sugestão:** envolver o `reload`/checagem em tratamento que degrade para "sem conflito conhecido" ou para um erro de validação legível, e documentar o resgate no import.

## Bug 3 — `ativo: nil` explícito pula a validação de auto-gerência (mitigado pela constraint, mas acopla-se a ela)

- Severidade: ⚪ Info
- Arquivo: `app/models/gestor_individual_gerenciado.rb:57-59` (`janela_de_revalidacao → ativo?`) + `invariante_auto_gerencia.rb:59`.

**Passos (sondas H7/H7b):**
```ruby
v = GestorIndividualGerenciado.new(gestor_individual: gestor, user: gestor.gestor_user, ativo: nil)
v.ativo?          # => false  -> a janela `if: :janela_de_revalidacao` é false
v.valid?          # => true, errors=[]     (validação de auto-gerência PULADA)
v.save            # => NotNullViolation
```
- **Atual:** com `ativo: nil` a validação de auto-gerência (e as demais `if: :ativo?`) **não roda**. O `save` é salvo da violação apenas pela constraint `NOT NULL` da coluna (`ativo boolean default true not null`), que levanta `ActiveRecord::NotNullViolation` cru.
- **Esperado:** irrelevante para o fluxo normal (a coluna tem default `true` e nunca fica `nil` a partir do banco), mas registra-se o acoplamento: a validação de invariante depende de a coluna ser `NOT NULL` para não haver quadrante descoberto.
- **Impacto:** nenhum no caminho de escrita (a constraint cobre); informativo para quem for mexer na coluna.
- **Teste sugerido:** se algum dia `ativo` virar anulável, cobrir `ativo: nil` como quinto quadrante.

## Bug 4 — `record_invalid` dos dois caminhos de I18n **não concordam** (o `e.message` sai em inglês)

- Severidade: ⚪ Info
- Arquivo: `config/locales/pt-BR.yml:100` e `:136`.

**Passos (sonda H9):** `I18n.t("activerecord.errors.messages.record_invalid")` vs `I18n.t("errors.messages.record_invalid")` e um `save!` real.
- **Atual:**
  ```
  [H9] record_invalid(ar)     = "Validation failed: %{errors}"       # caminho que o RecordInvalid consulta
  [H9] record_invalid(errors) = "1 erro impediu este registro de ser salvo: %{errors}"
  [H9] e.message do RecordInvalid = "Validation failed: Nome não pode ficar em branco"
  ```
  O comentário no locale afirma que os dois caminhos "concordam", mas as **frases diferem** e a efetivamente usada (`activerecord.`) traz o prefixo **em inglês** — num app com I18n estrito em pt-BR.
- **Esperado:** ambos os caminhos com a mesma frase pt-BR (ex.: `"1 erro impediu este registro de ser salvo: %{errors}"`).
- **Impacto:** o blocker da 29.3 (Bug 8) está funcionalmente resolvido (não há mais "Translation missing"), mas o operador vê "Validation failed:" em inglês. Cosmético/i18n.
- **Teste sugerido:** assertar `assert_equal I18n.t("errors.messages.record_invalid"), I18n.t("activerecord.errors.messages.record_invalid")`.

## Bug 5 — Lado do gestor persistido não vê vínculos recém-construídos em memória (`exists?` vai ao banco)

- Severidade: ⚪ Info
- Arquivo: `app/models/gestor_individual.rb:129-142` (`host_tem_auto_gerencia_ativa?`).

**Passos:**
```ruby
g = GestorIndividual.find(id)                       # persistido
g.gestor_individual_gerenciados.build(user: login, ativo: true)  # só em memória, não salvo
g.gestor_user = login
g.valid?   # ramo `persisted?` usa exists?/query no banco -> NÃO vê o vínculo em memória
```
- **Atual:** o ramo `persisted?` (`gestor_individual_gerenciados.ativos.where(...).exists?`) consulta o banco e **ignora** vínculos não persistidos na coleção em memória; o ramo `else` (não-persistido) olha a memória. Simetria incompleta.
- **Esperado:** irrelevante para o invariante final — quando o vínculo em memória for salvo, o **lado do vínculo** o barra (validação de auto-gerência com `ativo?`). Não há caminho que grave auto-gerência só por isso.
- **Impacto:** informativo; relembra que o `exists?` é a otimização declarada como não-provada por teste. Não confundir com o Bug 1 (que **é** o caminho de gravação real).
- **Teste sugerido:** se quiser fechar, o ramo poderia checar primeiro a coleção carregada e só então o banco.

---

## Cenários Testados (sem bugs)

Confirmações independentes (todas OK):

1. **D8 — `valid?` no caminho de leitura:** com um registro **inválido-no-model / válido-no-banco** (auto-gerência ativa criada por `insert_all!`) presente no banco, `GET /gestores_individuais` retorna **200** e a célula "Gerenciados" renderiza. O `index` (`GestorIndividual.includes(:gerenciados)`) **não** dispara `valid?` nem `RecordInvalid`. ✅
2. **4 quadrantes × 2 lados (hipótese 8):** ativo/ativo barra; inativo/ativo, ativo/inativo e inativo/inativo passam — pelos **dois** lados (validação do gestor e do vínculo) e no banco via `insert_all!`. Bugs 3/4/12/15/17/18 permanecem fechados. ✅
3. **Load-bearing do `reload`:** o cenário puro (gestor **já com login salvo no banco**, vínculo montado a partir dele) é corretamente **barrado** — o `reload` funciona quando o banco é a fonte da verdade e não há mudanças pendentes. ✅ (o defeito é só com mudanças pendentes — Bug 1).
4. **`janelas de revalidação`:** módulo chama `if: :janela_de_revalidacao`; **os dois hosts a definem e ela é privada** (`private_method_defined? → true`, `public → false`); `respond_to?` no público → `false`; o método de validação `auto_gerencia_nao_ativa` também é privado nos dois hosts. `include Desativavel` (antes do `private`) manteve `desativar!` e `scope :ativos` **públicos** nos dois models. ✅
5. **I18n:** as duas chaves `activerecord.errors.models.{gestor_individual,gestor_individual_gerenciado}.auto_gerencia` **resolvem** (textos reais: "não pode ser um dos geridos ativos (auto-gerência não é permitida)" / "não pode ser o próprio gestor (auto-gerência não é permitida)"). Não caem em translation-missing. ✅ (a inconsistência de frase está no Bug 4, eixo `record_invalid`, não nestas).
6. **Gestor deletado/inalcançável:** ver Bug 2 (é o único modo de falha encontrado).
7. **`dependent: :restrict_with_exception`** inalterado; `destroy` com vínculos bloqueia. ✅
8. **Higiene de banco:** sondas rodaram em transação (`bin/rails test`, nunca `runner`); nenhum lixo persistente; `api_ponto_test` com **0 linhas** em ambas as tabelas após a rodada. ✅
9. **Segurança (achado 4 do reviewer):** `.gitignore` da raiz cobre `/master.key`, `/credentials.yml.enc`, `/config/master.key` (verificado com `git check-ignore`). Observação: `api-ponto/config/credentials.yml.enc` continua **rastreado** (o ignore não alcança arquivo já no índice) — já sinalizado pelo Code Reviewer (achado 13), fora do escopo da 29.2. ⚪
10. **Métricas de suíte:** direcionados 29.2 (`test/models/gestor_individual_test.rb` + `gestor_individual_gerenciado_test.rb` + `test/migrations`) **96 runs / 276 assertions / 0 failures**; `test/models` + `test/controllers/admin` **514 / 1788 / 0** (baseline mantido); RuboCop dos 4 arquivos do concern/models **0 offenses**; `zeitwerk:check` **All is good**. Nenhum teste existente quebra com o código atual. ✅

## Medições (hipóteses 2 e 3)

- **Custo do `reload` em lote:** validar **N** vínculos que apontam para o **mesmo gestor persistido** dispara **1 `reload` (SELECT do gestor) por vínculo** + a query da validação. Medido: **5 vínculos → 10 queries** (5 reloads + 5 checks). Escala **O(N)**, não O(1) por gestor. Confirmado que o `reload` **ignora associação já carregada** (`includes`/`.to_a`): **1 vínculo com associação carregada → 2 queries** (reload + check), ou seja, o `includes` da associação **não** é aproveitado.
- **Impacto na 29.3:** a importação em lote (reconciliação ActiveRecord de muitos vínculos) pagará **+1 SELECT de gestor por vínculo**, mesmo com `includes(:gestor_individual)` — o `reload` zera o cache. Consequência secundária do Bug 1; recomendável o lazy-load/`includes` do próprio gestor (uma leitura por gestor, não por vínculo) quando o reload for corrigido.

## Veredito Final

- **Bloqueia a 29.3?** O **Bug 1 (🟠)** sim, no sentido em que é a **mesma classe de falha** que a 29.2-D7 deveria eliminar: o concern centraliza o wiring (o `included do validate` funciona — confirmado), mas o `reload` do lado do vínculo **grava auto-gerência ativa** no caminho normal da reconciliação e **apaga mudanças pendentes** do gestor. O Bug 8 (blocker) e o wiring do D7 estão OK. O Bug 2 (🟡) deve entrar no tratamento de exceções da importação (resgatar `RecordNotFound`, não só `RecordInvalid`).
- **Hipótese 1 é bug real?** **Sim.** Modo de falha: `gestor.reload` incondicional em `host_tem_auto_gerencia_ativa?` descarta `changes` do gestor (incl. `gestor_user_id`) e muta o objeto do chamador; a validação lê `gestor_user_id` do banco (`nil`) e libera o par de auto-gerência, além de causar perda silenciosa de `nome`/`orgao`/`observacao`/`gestor_user_id` pendentes.
- **O que está sólido:** o wiring do D7 (validate único no módulo, janelas privadas nos dois hosts), o event-scope do gestor, o `if: :ativo?` do vínculo, os 4 quadrantes × 2 lados, o D8 no caminho de leitura, o I18n das mensagens de invariante e o `.gitignore` de segredos.
- **Prioridade de correção:** Bug 1 (antes de liberar a 29.2/entrar na 29.3) → Bug 2 (tratamento no import) → Bugs 3/4/5 (registro/documentação).

### 📢 Sinalização ao CTO

1. **O `reload` introduzido para corrigir o achado 1 do reviewer é uma correção com efeito colateral pior que o defeito original neste caminho.** A lição da 29.2 ("validação de invariante deve ser event-scoped e não travar o registro") tem uma irmã: **`reload` de associação dentro de callback de validação muta o objeto do chamador e descarta estado não persistido.** Um invariante que precisa "ver o outro lado atualizado" deve ler o valor sem recarregar a instância recebida (consulta pontual) ou só recarregar quando não há mudanças pendentes. Vale item de `structural-conformity-checklist`: "callback de validação não muta a instância do chamador".
2. **Divergência de I18n:** o fix do Bug 8 tem dois caminhos com frases diferentes; o `RecordInvalid#message` que o operador vê ainda começa em inglês ("Validation failed"). Recomendo alinhar as duas strings.
3. **Acoplamento validação × NOT NULL:** `ativo: nil` pula a validação e só a constraint segura; documentar para futuras alterações de anulabilidade da coluna.

---

**Estado final do banco de teste:** `api_ponto_test` — `gestores_individuais` = 0 linhas, `gestor_individual_gerenciados` = 0 linhas. `api_ponto_development` intocado. Sondas temporárias removidas (`test/models/zz_tmp_*`, `test/controllers/admin/zz_tmp_*`).
