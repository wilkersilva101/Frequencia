# Relatório Bug Finder — Iteração 29, Tarefa 29.2 — Dev B — 2ª RODADA

> **Branch:** `feature/demanda-29-schema-gestor-individual`
> **Data:** 2026-09-29
> **Propósito:** Teste adversarial da SEGUNDA rodada da Tarefa 29.2 — verificar de forma independente as correções aplicadas pelo Code Specialist aos 11 achados da 1ª rodada (`docs/quality/bug_report_29_2_bug-finder.md`) e procurar bugs NOVOS introduzidos por elas (assimetria validação × índice parcial, `desativar!`, `restrict_with_exception`, `schema:load`, formato de CPF, migrations em sequência). Nunca corrigir — apenas reportar.

## Resumo

| Métrica | Valor |
|---------|-------|
| Total de cenários testados | 31 |
| Bugs NOVOS encontrados | 5 |
| 🔴 Crítico | 0 |
| 🟠 Alto | 0 |
| 🟡 Médio | 1 |
| 🟢 Baixo | 2 |
| ⚪ Info | 2 |

**Ambiente/evidências:** banco de teste local `api_ponto_test` (Postgres 17 em `localhost:5432` — descobriu-se nesta rodada que o banco de teste NÃO é o remoto `10.150.110.174:5000`; o remoto só tem `api_ponto_development`). Bancos scratch descartáveis criados, usados e **DROPPADOS** ao fim: `api_ponto_scratch_292_r2` (migração de zero + cenários de model/constraint) e `api_ponto_scratch_292_r2_load` (verificação de `db:schema:load`). **`api_ponto_development` ficou intocado** (confirmado: 0 linhas em `gestores_individuais`, mesmo `schema_migrations`). Nada foi corrigido, commitado ou pushado.

**Confirmação das correções da 1ª rodada (independente):** todas as 5 que mataram mutação estão vivas e corretas — ver seção "Cenários Testados (sem bugs)".

---

### CONFIRMAÇÃO — Correções da 1ª rodada (nenhuma regressão)

Verificação independente, não por reexecução dos testes do dev (que passam), mas por cenários próprios:

| Achado 1ª rodada | Correção | Verificação r2 | Veredito |
|---|---|---|---|
| 🟠 Bug 1 — rollback destrutivo | documentado FORWARD-ONLY na migration | texto presente no topo do arquivo; rollback de schema limpo (ver abaixo) | ✅ documentado |
| 🟠 Bug 2 — `dependent: :destroy` | `restrict_with_exception` | `gestor.destroy` → `ActiveRecord::DeleteRestrictionError`; vínculo preservado | ✅ corrigido |
| 🟡 Bug 3 — par duplicado `id_legado` nulo | índice UNIQUE parcial `WHERE ativo` + validação | 2 ativos do par → bloqueados (model e banco); inativo + re-vínculo → permitidos | ✅ corrigido (com ressalva — Bug 12 abaixo) |
| 🟡 Bug 4 — auto-gerência | `validate :gerido_nao_e_o_proprio_gestor` | `create`/`update!` do vínculo apontando para o `gestor_user` → barrados | ✅ corrigido (com furos — Bug 15 abaixo) |
| 🟢 Bugs 5/6 — guard de `desativar!` | `momento ||= Time.current` + preserva 1ª data | data legada preservada com flag divergente; `nil` cai no tempo atual | ✅ corrigido |
| ⚪ Bug 10 — `gestor_cpf` formato | `format: /\A\d{11}\z/, allow_nil: true` | máscara/curto/12 dígitos rejeitados; 11 dígitos e `nil` aceitos | ✅ corrigido (com ressalva — Bug 14 abaixo) |

---

### Bug 12 — ASSIMETRIA validação × índice parcial: vínculo NOVO `ativo: false` é barrado quando o par já tem um ATIVO (mas o banco o aceitaria)

- Severidade: 🟡 Médio
- RF/RN violado: critério 29.2 "reimportação não duplica o mesmo gestor→gerido"; desvio aprovado "índice UNIQUE **parcial** em `ativo` para preservar o histórico de re-vínculo". **Normalização de vínculos histórico do legado na importação da 29.3 (traz `data_exclusao` legada).**
- Passos:
  1. Para um par gestor `g` / gerido `u`, criar o vínculo ATIVO: `GestorIndividualGerenciado.create!(gestor_individual: g, user: u)`.
  2. Construir um vínculo NOVO para o MESMO par, porém **inativo** (é exatamente o dado que a importação da 29.3 traz do Intranet — vínculo histórico com `data_exclusao` preenchida): `GestorIndividualGerenciado.new(gestor_individual: g, user: u, ativo: false, data_exclusao: Time.zone.local(2020,1,1))`.
  3. `save` (ou `save!`).
- Atual:
  - **A validação do Rails BARRA** — `valid? == false`, `errors.full_messages == ["User já está em uso"]`. O `uniqueness: { scope: :gestor_individual_id, conditions: -> { where(ativo: true) } }` não considera que a LINHA NOVA é inativa; o `conditions` só filtra as linhas **existentes** no banco, não o registro sendo validado. Logo qualquer linha nova (ativa ou não) do par com um ativo existente é rejeitada.
  - **O índice do banco PERMITIRIA** — `insert_all!` com `ativo: false` para o mesmo par passa sem erro (a linha nova não entra no índice parcial `WHERE ativo`). 3ª confirmação da assimetria.
  - Inverso (criar ATIVO quando só existe INATIVO) **passa** corretamente nos dois lados (`valid? == true`, insert OK).
- Evidência:
  ```
  === C2: assimetria exata — ATIVO existente + INATIVO novo ===
  novo INATIVO com ATIVO existente -> valid?=false
    erro exato: ["User já está em uso"]
    insert_all! ativo:false -> OK, DB PERMITE (index parcial). Model bloqueia. ASSIMETRIA CONFIRMADA
  ```
  ```
  === C1: dois INATIVOS do mesmo par SEM nenhum ativo (model deixa?) ===
  segundo inativo (sem ativo existente) valid=true
    save=true
    total=2
  ```
- Impacto: se a importação da 29.3 criar os vínculos via **ActiveRecord** (não `insert_all!`/upsert SQL) e o mesmo par tiver, no legado, um vínculo ATIVO e outro INATIVO (ou dois vínculos históricos sendo um deles ativo), o inativo legítimo será **rejeitado com "User já está em uso"** — a importação perde o vínculo histórico ou aborta, e o histórico de re-vínculo que o índice parcial existe justamente para preservar não pode ser reconstruído. O desvio aprovado só protege o re-vínculo **via `desativar!`** (que faz `UPDATE`, não `INSERT`); a reconstrução via `INSERT` inativo é o caminho quebrado. Note-se ainda que **os testes da 1ª/2ª rodada não cobrem esse caminho**: o único teste da assimetria ("vínculo INATIVO do mesmo par convive com o ativo") só cria o segundo inativo **quando ainda não há ativo**, ou usa `insert_all!` — nunca `create` de um inativo com um ativo já presente.
- Sugestão (não implementar): na validação, curto-circuitar quando o próprio registro é inativo (`return if ativo == false`) OU trocar a validação por uma que consulte o par ativo apenas quando `ativo` é verdadeiro; e decidir explicitamente se a importação da 29.3 usa upsert SQL (`insert_all!`/`upsert_all`) ou ActiveRecord — se usar ActiveRecord, este bug vira **bloqueio de importação**. Adicionar teste: "criar vínculo INATIVO com um ATIVO já existente do mesmo par deve ser permitido".

### Bug 13 — `desativar!` tem tipo de retorno inconsistente (`true` vs `self`)

- Severidade: 🟢 Baixo
- RF/RN violado: contrato de método / previsibilidade da API do concern `Desativavel`
- Passos:
  1. `g = GestorIndividual.create!(nome: "x")` (ativo, sem data).
  2. `g.desativar!` → caminho `update!` (retorno de `update!` = `true`).
  3. `g.desativar!` de novo (já inativo com data) → caminho `return self`.
- Atual: a 1ª chamada retorna `true` (Boolean, efeito colateral de `update!`); a 2ª retorna o próprio registro (`GestorIndividual`). O tipo de retorno depende do ramo interno.
- Evidência:
  ```
  === H5-return / C7 ===
  caminho normal retorna: true (classe TrueClass)
  caminho early-return retorna: self(GestorIndividual)
  ```
- Observação adicional: `desativar!` num registro **não persistido** (`GestorIndividual.new`) não levanta — `update!` faz um `INSERT` (persistiu `id=9`, `ativo=false`). Isso é um comportamento surpreendente para um método de "desativar", mas é consequência natural de `update!` sobre registro novo; só relevante se algum fluxo futuro chamar `desativar!` num objeto nunca salvo.
- Impacto: baixo — nenhum consumidor atual encadeia o retorno. Mas um método de ciclo de vida que ora devolve `true` ora devolve o registro é armadilha para `if g.desativar!`/encadeamento na 29.4.
- Sugestão (não implementar): `update!(...)` seguido de `self`, ou documentar que o retorno não é contrato.

### Bug 14 — `gestor_cpf: ""` (string vazia) é rejeitado apesar de `allow_nil` (blank ≠ nil)

- Severidade: ⚪ Info
- RF/RN violado: robustez da ponte de casamento `gestor_cpf` na importação da 29.3
- Passos: `GestorIndividual.new(nome: "x", gestor_cpf: "").valid?` e `gestor_cpf: "   "`.
- Atual: `allow_nil: true` só libera `nil`; string vazia é validada pelo formato `\A\d{11}\z` e **falha** (`errors == ["é inválido"]`). Um CPF vindo como `""` da fonte (em vez de `NULL`) vira erro de validação.
- Evidência:
  ```
  === C5 ===
  vazio valid=false (allow_nil nao cobre string vazia?) errors=["é inválido"]
  ```
- Nota de contexto: essa é **exatamente** a convenção do `User` do projeto — `validates :cpf, uniqueness: true, format: { with: /\A\d{11}\z/ }, allow_nil: true` (`app/models/user.rb:52`) — então **não é desvio introduzido pela 29.2**, é consistência com o padrão existente. Registrado porque a 29.3 (upsert por CPF) é justamente onde string vazia vs `nil` importa.
- Impacto: baixo; a importação deve normalizar `""`→`nil`/`blank` na borda.
- Sugestão (não implementar): na 29.3, `gestor_cpf = ...presence` antes do upsert; opcionalmente `allow_blank: true` se o projeto quiser tolerar vazio (mas isso divergiria do `User`).

### Bug 15 — Auto-gerência "tardia": vínculo criado antes de o gestor ganhar `gestor_user` não é revalidado

- Severidade: 🟢 Baixo
- RF/RN violado: RN §3 "bloqueia o próprio ponto" (29.5); integridade da cascata
- Passos:
  1. `gu = User.create!(...)`
  2. `g = GestorIndividual.create!(nome: "x")` — **sem** `gestor_user` ainda.
  3. `v = GestorIndividualGerenciado.create!(gestor_individual: g, user: gu)` — criação passa (não há como saber ainda que `gu` será o gestor).
  4. `g.update!(gestor_user: gu)` — agora `g.gestor_user_id == v.user_id`.
  5. `v.reload.valid?`
- Atual: `v.valid? == false` (a validação **detecta** a auto-gerência), mas a linha **já está persistida e ativa** — a validação do vínculo só roda em `save` do vínculo, não em `save` do gestor. Não há CHECK no banco cruzando as duas tabelas (impossível de fazer em Postgres, como o próprio comentário do model reconhece).
- Evidência:
  ```
  === H4a ===
  vinculo criado: id=5 valido=true
  apos setar gestor_user no gestor: vinculo valido=false  AUTO-GERENCIA PRESENTE?
    gestor_individual.gestor_user_id=3 user_id=3
  ```
- Furos secundários avaliados:
  - **`build` (gestor não persistido)**: a validação funciona — `valid? == false` com "auto-gerência não é permitida" (usa `gestor_individual.gestor_user_id`, disponível em memória). ✅
  - **`update!` no vínculo** mudando `user_id` para o `gestor_user`: barrado. ✅
  - **Bypass via `update_column(:user_id, gestor_user_id)` / SQL direto**: passa (sem validação). Esperado para bypass explícito; registrado para completude.
- Impacto: se a 29.4 tratar `gestor_user` como identidade autorizada e um fluxo de cadastro criar o vínculo **antes** de preencher o login do gestor (ordem natural: cria gestor → vincula geridos → depois associa login), a auto-gerência passa silenciosamente. Hoje mitigado porque não há caminho de escrita além de console/fixtures.
- Sugestão (não implementar): revalidar os vínculos do gestor no callback de `GestorIndividual` quando `gestor_user_id` muda (ou guard no fluxo da 29.4/29.5); documentar a ordem obrigatória.

### Bug 16 — Índice parcial não serve a consultas que filtram só por `gestor_individual_id`

- Severidade: ⚪ Info
- RF/RN violado: performance potencial da cascata da 29.4/29.6
- Passos: `EXPLAIN SELECT * FROM gestor_individual_gerenciados WHERE gestor_individual_id = 1;` num scratch com o índice parcial.
- Atual: o índice `index_gestor_individual_gerenciados_on_par_ativo` só cobre o par **+** `ativo`; para a query por `gestor_individual_id` sozinho (o que `GestorIndividual#gerenciados`/`includes(:gerenciados)` faz), o planner usa `Seq Scan`/índice de FK simples (`index_..._on_gestor_individual_id`). A dedupe do plano do índice parcial exige o predicado `ativo`.
- Evidência:
  ```
  EXPLAIN SELECT * FROM gestor_individual_gerenciados WHERE gestor_individual_id = 1;
   Seq Scan on gestor_individual_gerenciados  (Filter: gestor_individual_id = 1)
  ```
- Impacto: nenhum correto — é só uma nota de que o índice parcial **não substitui** o índice de FK (que continua existindo), o que está certo no schema atual. Registrado para que a 29.4 não assuma que o índice do par cobre o filtro por gestor sozinho (o `includes(:gerenciados)` não filtra por `ativos` hoje — débito já registrado no iteration).
- Sugestão (não implementar): na 29.4, consumir `gerenciados` através de `GestorIndividualGerenciado.ativos.where(gestor_individual: ...)` para de fato usar o índice parcial.

---

## Cenários Testados (sem bugs)

- **`db:schema:load` reproduz o índice parcial EXATAMENTE** (Hipótese 3): `pg_indexes` do banco migrado vs do banco carregado via `db:schema:load` são **idênticos byte a byte**, incluindo `... USING btree (gestor_individual_id, user_id) WHERE ativo` — o `db/schema.rb` (`t.index ..., unique: true, where: "ativo"`) **não** perde a cláusula `where`. `diff` retornou "IDENTICOS" nos 8 índices das duas tabelas.
- **Migrations de zero em sequência**: `db:migrate` de um banco vazio aplica as 26 migrations (incluindo `20260929120000` e `20260929130000`) sem erro; `schema_migrations` fica com as duas versões novas.
- **Rollback das DUAS migrations em ordem inversa** (`db:rollback STEP=2`): a 130000 é revertida primeiro (`remove_index` do par parcial) e depois a 120000; ao fim **não há resíduo**: restam apenas `id, nome, orgao, created_at, updated_at` em `gestores_individuais` e `id, gestor_individual_id, user_id, created_at, updated_at` em `gestor_individual_gerenciados`, com só os índices/FKs originais (`index_..._on_gestor_individual_id`, `index_..._on_user_id`, `fk_rails_e60917cb99`, `fk_rails_ccb2d82d4d`). Zero índice órfão, zero coluna órfã. Re-migrate após reverter recria tudo.
- **Índice parcial no banco** (Hipótese 2): dois ATIVOS do mesmo par via `insert_all!` → `RecordNotUnique`; ATIVO + INATIVO via `insert_all!` → permitido; dois INATIVOS → permitidos. Comportamento do banco é o documentado (parcial em `ativo`).
- **`restrict_with_exception`** (Hipótese 6): `gestor.destroy` com vínculo → `ActiveRecord::DeleteRestrictionError` ("Cannot delete record because of dependent gestor_individual_gerenciados"); `GestorIndividual.destroy_all` com vínculo → mesma exceção (bloqueia, não apaga). `gestor.destroy` sem vínculo funciona. **Nenhuma chamada a `destroy`/`destroy_all`/`delete_all` de `GestorIndividual` em `app/`, `lib/`, `db/seeds.rb`, `test/fixtures/`** — o único consumidor é `Admin::GestoresIndividuaisController#index` (e `includes(:gerenciados)` não dispara deleção). **Nenhuma regressão pelo `restrict`.**
- **Formato de `gestor_cpf`** (Hipótese 7): 11 dígitos e `nil` aceitos; `"123.456.789-01"`, `"123"` (curto) e `"123456789012"` (12) rejeitados. O `api_ponto_development` tem **0 registros** em `gestores_individuais` → nenhum registro existente quebrado (não há CPF mascarado no dev). Sem `unique` de CPF, dois gestores com o mesmo CPF coexistem — é decisão da 29.3 (não escopo).
- **`desativar!` — estados restantes** (Hipótese 5): `ativo=false, data=nil` → preenche a data; registro novo (não persistido) → faz `INSERT` (não levanta); validação falhando (ex.: `gestor_cpf` inválido) → `ActiveRecord::RecordInvalid` (mensagem ainda "Translation missing" — débito global já registrado como Bug 8 da 1ª rodada); `momento` futuro → aceito sem validação; `desativar!` duas vezes a partir de `ativo=false, data=nil` → preserva a 1ª data (idempotente).
- **`desativar!` num registro legado divergente** (`ativo=true` + `data_exclusao` preenchida): preserva a data legada e só ajusta a flag — o comportamento que a 29.3 espera para não sobrescrever a data real do Intranet.
- **Fluxos normais de vínculo**: criar ativo depois de só existir inativo → permitido; re-vincular após `desativar!` → permitido; pares diferentes → permitidos; `id_legado` duplicado → `RecordNotUnique` pelo banco; `id_legado` nulo múltiplo → convive.

## Baselines medidos (2ª rodada)

| Comando | Resultado |
|---|---|
| `test/models/gestor_individual_test.rb` + `test/models/gestor_individual_gerenciado_test.rb` + `test/migrations/` | 77 runs / 235 assertions / **0 failures / 0 errors** |
| `bin/rails test test/models test/controllers/admin` | 495 runs / 1747 assertions / **0 failures / 0 errors** (idêntico ao dev) |
| `bin/rails test` (suíte completa) | 869 runs / 3084 assertions / **1 failure + 11 errors** — exatamente os **12 pré-existentes** (11× `NoMethodError: private method 'redirect_to'` nos controllers Devise `users/sessions` e `users/passwords` da Sprint 23 + 1× timezone em `presenca_endpoints_test.rb`) |
| RuboCop / Zeitwerk | não reexecutado nesta rodada (nenhum arquivo de produção alterado pela 2ª rodada) |

## Veredito Final

**Nenhum bloqueio de conformidade na 29.2.** As 5 correções da 1ª rodada foram verificadas de forma independente e estão corretas; a suíte não regrediu (869/3084, mesmos 12 pré-existentes); `schema:load` e rollback produzirão um banco correto. Os 5 achados desta rodada são **NOVOS** e nenhum é 🔴/🟠 na 29.2 — mas o Bug 12 é uma **armadilha de borda com destino certo na 29.3**:

1. **🟡 Bug 12 (o mais relevante):** a validação de par e o índice parcial do banco **discordam** para o caso "vínculo novo inativo sobre par com ativo existente". O banco aceita; o Rails barra. Se a importação da 29.3 criar vínculos via ActiveRecord (em vez de `insert_all!`/upsert SQL), ela **falhará ou perderá o vínculo histórico** — exatamente o cenário que o índice parcial foi criado para suportar. Recomenda-se (a) ajustar a validação para não barrar registro inativo e (b) decidir o modo de escrita da importação antes da 29.3. **Se a 29.3 usar ActiveRecord, este bug vira bloqueio de importação.**
2. **🟢 Bug 15:** auto-gerência "tardia" (vínculo antes do login do gestor) — decidir a ordem no fluxo da 29.4/29.5.
3. **🟢 Bug 13 / ⚪ Bug 14 / ⚪ Bug 16:** baixo/info (retorno de `desativar!`, CPF `""`, uso do índice parcial na 29.4).

**Sinalização ao CTO:** padrão recorrente confirmado — as correções da 1ª rodada fecharam os sintomas, mas a **assimetria entre validação-de-model e constraint-de-banco** (agora sobre índice PARCIAL) reapareceu como o achado novo. Sugestão de item permanente no checklist de migrations: para índices parciais, testar **todos os 4 quadrantes** (ativo/ativo, ativo/inativo, inativo/ativo, inativo/inativo) **pelos dois lados** (validação Rails e `insert_all!` no banco), pois o Rails valida o registro NOVO por completo e o banco só indexa a fatia ativa. O locale `pt-BR` sem `record_invalid` (1ª rodada, Bug 8) permanece débito de i18n de alcance global e reaparece em todo `RecordInvalid` desta rodada.

**Nota de ambiente (limpeza):** bancos `api_ponto_scratch_292_r2` e `api_ponto_scratch_292_r2_load` criados e **DROPPADOS**; `api_ponto_development` intocado (0 linhas). Descoberta útil: nesta máquina o banco de teste é o Postgres **local** (`api_ponto_test` em `localhost:5432`), não o remoto de `config/database.yml` — as migrations estavam pendentes no local e foram aplicadas (`RAILS_ENV=test bin/rails db:migrate`) para a suíte rodar; nenhum arquivo versionado foi alterado.
