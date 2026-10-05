# Relatório Bug Finder — Iteração 29, Tarefa 29.2 — Dev B — 3ª RODADA

> **Branch:** `feature/demanda-29-schema-gestor-individual`
> **Data:** 2026-09-29
> **Propósito:** Teste adversarial da TERCEIRA rodada da Tarefa 29.2 — foco no código NOVO da correção do **Bug 15** (`validate :gestor_user_nao_e_gerido_ativo` em `GestorIndividual`, guardando o invariante de auto-gerência "tardia" pelo lado do gestor). Procurar bugs NOVOS introduzidos por essa validação (tijolamento, N+1, transições de `gestor_user_id`, ramo `persisted?` × associação carregada, assimetria com o lado do vínculo), reconfirmar as correções das rodadas 1 e 2 e verificar de forma independente que o Bug 15 está de fato fechado. Nunca corrigir — apenas reportar.

## Resumo

| Métrica | Valor |
|---------|-------|
| Total de cenários testados | 23 |
| Bugs NOVOS encontrados | 3 |
| 🔴 Crítico | 0 |
| 🟠 Alto | 2 |
| 🟡 Médio | 0 |
| 🟢 Baixo | 1 |
| ⚪ Info | 0 |

**Ambiente/evidências:** banco de teste local `api_ponto_test` (Postgres, `localhost:5432`). Todas as verificações de comportamento foram feitas por **teste temporário dentro da transação** (`bin/rails test`, com `insert_all!`/savepoints) — nunca por `bin/rails runner` em `RAILS_ENV=test` neste ambiente (evita lixo persistente). Os 4 arquivos temporários `test/models/zz_bf29r3_*_test.rb` foram **removidos** ao fim. **Nada foi corrigido, commitado ou pushado.**

**Higiene do banco de teste — CONFIRMADA LIMPA:** `gestores_individuais = 0` e `gestor_individual_gerenciados = 0` em `api_ponto_test` (verificado após rodar toda a suíte e os temporários: `TEST gestores=0 vinculos=0`). `api_ponto_development` também **0 linhas** em ambas (não foi tocado). Sem bancos scratch nesta rodada (nenhuma migração executada).

---

### CONFIRMAÇÃO — Bug 15 está FECHADO (com ressalva de escopo)

Verificação independente do código novo (`app/models/gestor_individual.rb:79-99`), não por reexecução dos testes do dev:

| Cenário do Bug 15 | Resultado medido | Veredito |
|---|---|---|
| Ordem natural: cria gestor → vincula gerido ATIVO → associa login = o gerido | `gestor.valid? == false`; erro "Gestor user não pode ser um dos geridos ativos"; `save!`/`update!` levantam | ✅ **fechado** (era o furo original) |
| Gerido ATIVO com login criado por **bypass** (`insert_all!`) → editar gestor | `gestor.valid? == false` (validação reexecuta em todo save) | ✅ **fechado** para o lado gestor |
| Promover a gestor um gerido **desativado** (vínculo inativo) | `gestor.valid? == true`, `update!` passa | ✅ **sem falso positivo** |
| Dar login a usuário que NÃO é gerido / login legítimo / limpar login (`nil`) | passam | ✅ |
| Gestor sem login (`gestor_user_id` blank) | validação retorna cedo, `update!(nome:)` passa | ✅ |
| Vínculo criado por `update_column` / SQL direto | **não detectado** | ⚠️ esperado (bypass explícito, não é caminho de escrita do app) |

O invariante é guardado pelos **dois lados** (gestor e vínculo) para o fluxo de escrita da aplicação — **isso está correto e foi verificado**. O que a 3ª rodada encontrou são **dois efeitos colaterais da validação nova** que ficam visíveis **no caminho de escrita da aplicação** (não em bypass puro) e que atingem diretamente a **29.3**. Registrados como Bugs 17 e 18 abaixo.

---

### Bug 17 — Validação de auto-gerência "envenena" a reimportação do gestor: registro de-gravável mas não-atualizável, e algemado para sempre

- Severidade: 🟠 **Alto**
- RF/RN violado: objetivo da 29.2/29.3 ("a fonte de verdade do vínculo passa a ser o Frequencia, alimentado pela importação idempotente"; `id_legado` é a chave de upsert da 29.3). Violado: o upsert/reimport do **próprio gestor** passa a falhar de forma não-recuperável no caminho de escrita da aplicação.
- Passos (reprodução mínima, dentro da transação):
  1. `login = User.create!(...)`
  2. `gestor = GestorIndividual.create!(nome: "G", gestor_user: login)` — **passa** (na 1ª importação o vínculo ainda não existe; a validação não tem o que acusar).
  3. A importação grava o vínculo gestor→gerido por **upsert/`insert_all!`** (o padrão documentado em `gestor_individual_gerenciado.rb` para a 29.3), apontando para o próprio `login`.
  4. Numa segunda passada, a importação re-salva o gestor (ex.: `gestor.update!(orgao: ...)`, ou qualquer atributo com `id_legado`).
- Atual:
  - `gestor.update!(orgao: "...")` → **`ActiveRecord::RecordInvalid`** — a validação roda em **todo** `save`, não só quando `gestor_user_id` muda, e acusa `["Gestor user não pode ser um dos geridos ativos (auto-gerência não é permitida)"]`.
  - O registro está **persistido** (`id`, `ativo=true`) e é **retornado pela importação**, mas **toda** escrita subsequente pela aplicação é refused: renomear, alterar `orgao`, associar outro login, gravar `observacao`, marcar `id_legado`...
  - O soft-delete da aplicação também falha: **`gestor.desativar!` → `ActiveRecord::RecordInvalid`** (`desativar!` usa `update!`, que revalida; `ativo` continua `true` e `data_exclusao` continua `nil`). O registro fica **algemado**: não pode mais ser desativado pela via canônica (o soft-delete da 29.2) nem editado.
  - **Nenhuma mutação de estado escapa**: o estado de auto-gerência "tardia" já está persistido (criado por bypass/upsert), e a validação do lado do gestor tornou-o **auto-perpetuante** (não há caminho in-app para limpá-lo).
  - *Escape hatch*: `gestor.update_column(:ativo, false)` (bypass puro) funciona — mas é bypass, não caminho de escrita do app.
- Evidência:
  ```
  === F1 === reimport (update orgao) do gestor: ActiveRecord::RecordInvalid
      valid?=false ativo=true data=nil
      desativar! (soft-delete) possivel? ActiveRecord::RecordInvalid
      escape: update_column(ativo:false) -> OK (bypass puro)
  ```
  ```
  === H1-TIJOLAMENTO === rename="RecordInvalid: ["Gestor user não pode ser um dos geridos ativos..."]"
                        desativar="RecordInvalid: ["..."]"
      ainda ativo? true data=nil
  ```
- Impacto: **bloqueia a 29.3.** A auto-gerência "tardia" **existiu de fato no ambiente** porque o dev a reproduziu em runtime (`docs/progress/iteration_29.md`, higiene do banco: "1 gestor e 2 vínculos órfãos") e registrou o bug na r2 — logo o dado ruim alcança o banco de produção pelas mesmas vias que a validação do lado do gestor não cobre. Quando ele existir, o gestor correspondente fica **inoperante por inteiro** na aplicação (não edita, não desativa, upsert não reconcilia). A validação nova fechou um buraco de escrita e abriu um modo de falha em que um único vínculo ruim transforma o gestor num registro travado. O fetch de `gestores_individuais` no `index` também passa a **bloquear a renderização**: `@gestores = GestorIndividual.includes(:gerenciados).order(:nome)` chama `valid?` no momento em que a view lê as mensagens de erro de qualquer registro inválido — aqui o registro válido-no-banco inválido-no-model faz o index levantar `RecordInvalid` (não medido nesta rodada por falta de admin logado; inferido do mecanismo de `ActiveModel`).
- Sugestão (não implementar): restringir a revalidação ao evento que de fato muda o invariante — p.ex. `validate :gestor_user_nao_e_gerido_ativo, if: -> { gestor_user_id_changed? || new_record? }` (assim renomear/alterar `orgao`/`observacao`/`id_legado` não falha). Complementarmente (e independente): dar à aplicação um caminho de recuperação para o estado de auto-gerência "tardia" já persistido (ex.: no `desativar!`, fazer o soft-delete sem revalidar o gestor), senão não há como sair do tijolo. Decidir explicitamente se `save(contexto)`/`update_columns` é aceitável para a importação da 29.3 (não é, pela regra "sem bypass") — o que traz a correção de volta ao âmbito do app.

### Bug 18 — Assimetria inversa do invariante: auto-gerência "tardia" INATIVA bloqueia o upsert do vínculo e derruba a reimportação do vínculo histórico

- Severidade: 🟠 **Alto**
- RF/RN violado: critério 29.2 "reimportação não duplica o mesmo gestor→gerido"; desvio aprovado "índice UNIQUE **parcial** em `ativo` para preservar o histórico de re-vínculo"; RN §3 (auto-autorização na cascata 29.4/29.5). É o **espelho exato** do 🟡 Bug 12 da r2, agora do lado do vínculo e no **quadrante INATIVO** que a última correção deixou de fora.
- Passos (reprodução mínima, dentro da transação):
  1. `login = User.create!(...)`
  2. `gestor = GestorIndividual.create!(nome: "G")` — **sem** login ainda.
  3. `v = GestorIndividualGerenciado.create!(gestor_individual: gestor, user: login)` — passa (na criação ainda não há `gestor_user`).
  4. `v.desativar!` → o vínculo vira **inativo** (histórico legado).
  5. `gestor.update!(gestor_user: login)` — o lado do gestor **passa** (só vínculos ativos conflitam — comportamento pretendido, evita falso positivo de promoção).
  6. A importação da 29.3 re-salva o vínculo histórico (`v.save!`, ou recria via `create`) para reconciliar `id_legado`/`data_exclusao`.
- Atual:
  - Passo 5: `gestor.valid? == true` — correto, o gestor **não** é barrado (promoção legítima preservada).
  - Passo 6: **`v.save!` → `ActiveRecord::RecordInvalid`** `["User não pode ser o próprio gestor (auto-gerência não é permitida)"]` — mas o vínculo está **INATIVO**: não representa auto-autorização corrente, e o lado do gestor explicitamente o considera não-conflitante. Os dois lados do invariante **discordam** sobre o mesmo vínculo.
  - O **banco/índice aceita** o inativo (`insert_all!` OK): o índice parcial `WHERE ativo` não o considera; só a validação Ruby do vínculo (`gerido_nao_e_o_proprio_gestor`, `app/models/gestor_individual_gerenciado.rb:50-56`) o barra — ela **não** tem o filtro `ativo` que o lado do gestor ganhou.
  - Também barra o `create` de um vínculo **novo INATIVO** cujo `user` é o `gestor_user` (`valid? == false`), ainda que o banco o aceite.
- Evidência:
  ```
  === F2 === gestor.valid?=true | vinculo(inativo).valid?=false
      re-salvar vinculo inativo via AR (reimport): ActiveRecord::RecordInvalid ["User não pode ser o próprio gestor..."]
      banco/upsert aceitaria inativo? OK
  ```
  ```
  === A1 === gestor.valid?=true | vinculo(inativo).valid?=false [...]
      re-salvar vinculo inativo: ActiveRecord::RecordInvalid
  === A2 === create inativo historico auto-gerencia via AR: valid?=false
      banco aceitaria? insert_all OK
  ```
- Impacto: se a importação da 29.3 reconciliar o vínculo via **ActiveRecord** (`save!`/`create`/update de `id_legado`), ela **falha ou perde o vínculo histórico** toda vez que a base tiver os **dois** fatos: (a) o usuário é/foi o gestor do próprio vínculo e (b) o vínculo está inativo. É exatamente o caso que a correção do Bug 15 criou ao permitir login de ex-gerido — e o histórico legado que o índice parcial existe para preservar. O Bug 12 (r2) foi corrigido reduzindo a validação de **par** ao quadrante ativo (`if: :ativo?`); a validação de **auto-gerência do vínculo** não recebeu o mesmo tratamento, reintroduzindo a assimetria validação × índice num eixo diferente. Grave também porque o par "gestor aponta para ex-gerido inativo" passou a ser **legítimo por decisão** (Bug 15), mas o vínculo correspondente **não pode mais ser reescrito**.
- Sugestão (não implementar): alinhar `gerido_nao_e_o_proprio_gestor` ao lado do gestor — só conflitar quando o **próprio vínculo** está ativo (`return if !ativo?` / `if: :ativo?`), para que o quadrante inativo espelhe o do gestor e o banco. Decidir com o dev se o invariante deve ser "nenhum vínculo ATIVO liga o gestor a si mesmo" (proposta, coerente com Bug 15) e cobrir os 4 quadrantes **pelos dois lados** no teste.

### Bug 19 — `destroy` do gestor com vínculo criado fora do cache do `has_many` estoura `InvalidForeignKey` bruto em vez de `DeleteRestrictionError`

- Severidade: 🟢 **Baixo**
- RF/RN violado: contrato de `dependent: :restrict_with_exception` (Bug 2 da r1)
- Passos:
  1. `g = GestorIndividual.create!(nome: "G")`; `u = User.create!(...)`.
  2. `GestorIndividualGerenciado.insert_all!([...])` (ou qualquer criação em que o cache do `has_many` não seja invalidado — ex.: insert por upsert/`update_all`, ou associação pré-carregada **vazia** antes do insert).
  3. `g.destroy`.
- Atual: `restrict_with_exception` só consegue bloquear vínculos que **carrega** via `dependent:`. Como a associação não foi invalidada/populada, ela aparece vazia → o Rails **executa o DELETE** → o **Postgres** bloqueia pela FK `fk_rails_ccb2d82d4d` → estoura **`ActiveRecord::InvalidForeignKey` (PG::ForeignKeyViolation)** em vez do `ActiveRecord::DeleteRestrictionError` documentado. O registro **não é apagado** (a integridade está correta), mas o tipo/mensagem do erro é outro e não é o que o Bug 2 prometeu.
- Contexto (não agrava): com o vínculo criado por **ActiveRecord** (`create!`) a associação é invalidada corretamente e dá `DeleteRestrictionError` — confirmado D1/D2/D4. O desvio aparece no caminho de **bypass** (D3), que é justamente o caminho de upsert da 29.3.
- Evidência:
  ```
  === D1 === (create! AR)          ActiveRecord::DeleteRestrictionError
  === D2 === (insert_all!)         ActiveRecord::DeleteRestrictionError
  === D4 === (assoc pre-carregada) ActiveRecord::DeleteRestrictionError
  === D3 === (assoc carregada VAZIA + insert_all depois) ActiveRecord::InvalidForeignKey
  ```
- Impacto: baixo — a gravação é impedida (correto); só o contrato do `restrict` não é o observado no nicho de bypass, e um `rescue DeleteRestrictionError` futuro não pegaria este caso. Não é caminho de escrita do app hoje (nenhum consumidor chama `destroy` de `GestorIndividual`).
- Sugestão (não implementar): não é preciso código agora; registrar que, se a 29.3 passar a criar/deletar vínculos por upsert, o `restrict_with_exception` deixa de ser garantia e a FK é que segura — documentar os dois tipos de exceção.

---

## Cenários Testados (sem bugs)

- **Bug 15 — reconfirmação completa (ver tabela na abertura):** ordem natural barrada; bypass detectado na edição do gestor; promoção de ex-gerido desativado permitida; login legítimo/limpar login/gestor sem login passam.
- **Ramo `else` (gestor novo, não persistido) é alcançável e funciona:** gestor em memória com um vínculo ativo em memória apontando para o próprio `gestor_user_id` → `valid? == false` com **ambos** os erros ("Gestor individual gerenciados é inválido" + "Gestor user não pode ser um dos geridos ativos"). Ou seja, **o ramo que o dev declarou não-provado É morto por um teste** (posso confirmar: basta um teste que monte `gestor.gestor_individual_gerenciados.build(...)` + `gestor.gestor_user = ...` sem persistir). Registro para o dev: a lacuna de mutation testing declarada no iteration **é fechável** com um teste simples.
- **`exists?` do ramo `persisted?` dispara query mesmo com a associação carregada em memória:** com `GestorIndividual.includes(:gestor_individual_gerenciados).find(...)` carregado, `valid?` emitiu **1** `SELECT 1 AS one FROM "gestor_individual_gerenciados"` — o `exists?` **não** usa o array já carregado (o `where(user_id:)` é uma consulta nova). Confirmado o passivo de query.
- **N+1 / carga na leitura (Hipótese 2):** a validação **não** roda no `index` (é só leitura; `includes` não salva). Mas:
  - **Todo save de `GestorIndividual` COM `gestor_user` ganha +1 SELECT** — medido: `update!` com login = **4 statements** (savepoint + `SELECT 1 AS one...` + `UPDATE` + release); sem login = **3 statements** (savepoint + `UPDATE` + release; `gestor_user_id` blank curto-circuita).
  - **Em lote, é 1 query por linha:** 10 updates de 10 gestores com login = **40 statements, 10** da validação → **O(N)**, sem batching. Um loop de importação que re-salve N gestores paga N SELECTs extras. Não é bloqueio (o upsert em massa da 29.3 tende a usar `upsert_all`), mas é custo real de um loop Ruby.
- **Mutações do caminho de validação:** esquecer o `where(user_id:)` faria a validação acusar **qualquer** gestor que tenha qualquer gerido ativo (não só o próprio login) — o teste `H7` mostra que um vínculo de **outro** usuário não conflita (`valid? == true`), ou seja, o filtro por `user_id` está vivo. Trocar `ativos` por "todos" faria o cenário de promoção de ex-gerido falhar — já coberto pelos testes do dev (Bug 15).
- **Interação com Bug 2 (`restrict_with_exception`):** vínculo ativo criado por AR → `DeleteRestrictionError`; gestor sem vínculo → `destroy` normal. Preservados das rodadas anteriores, exceto o nicho do Bug 19.
- **`desativar!` (Bug 13):** retorno é `self` nos **dois** ramos (`r1.equal?(gestor) == true` e `r2.equal?(gestor) == true`); preserva a primeira data (`2020-01-01` mantida após 2ª chamada com `2026-01-01`). Correção viva.
- **Bug 12 (r2) reconfirmado:** com um ativo existente do par, criar um **inativo** novo **passa** (`valid? == true`); criar outro **ativo** é **barrado**. Os dois quadrantes corretos hoje — o `if: :ativo?` está vivo.
- **Nenhum caminho de escrita além do `index`:** grep confirma que `GestorIndividual` só aparece no model, no controller `index` (leitura) e no `Ability` (comentário). Não há `create`/`update`/`destroy`/`insert_all` de gestor no app hoje — os Bugs 17/18 são pré-condição da **29.3**, não regressão ativa.
- **Estados pós-erro:** registro inválido tem as mudanças **revertidas** da memória (`update!` levanta antes do commit) — o dado no banco fica intacto (mas inválido). Não há "escrita parcial".

## Baselines medidos (3ª rodada)

| Comando | Resultado |
|---|---|
| `bin/rails test test/models/gestor_individual_test.rb test/models/gestor_individual_gerenciado_test.rb test/migrations` | 87 runs / 257 assertions / **0 failures / 0 errors** |
| `bin/rails test test/models test/controllers/admin` | 505 runs / 1769 assertions / **0 failures / 0 errors** (idêntico ao dev) |
| `bin/rails test` (suíte completa) | 879 runs / 3106 assertions / **1 failure + 11 errors** — exatamente os **12 pré-existentes** (11× `NoMethodError: private method 'redirect_to'` em `users/sessions` e `users/passwords` da Sprint 23 + 1× timezone em `presenca_endpoints_test.rb`). Nenhuma transitória flaky apareceu nesta rodada. |
| `bin/rubocop` (3 arquivos da 29.2) | 3 files inspected, **no offenses** |
| `bin/rails zeitwerk:check` | All is good! |
| Banco de teste `api_ponto_test` | `gestores_individuais = 0`, `gestor_individual_gerenciados = 0` — **LIMPO** |
| Banco `api_ponto_development` | 0 linhas nas duas tabelas — **intocado** |

## Veredito Final

**O Bug 15 está fechado para o fluxo de escrita da aplicação** (criar/editar o vínculo e dar login ao gestor, nos dois sentidos) — confirmado por cenários próprios, incluindo o ramo `else` que o dev declarou não-provado. Restam descobertos apenas bypass explícito (`update_column`/SQL direto), que **não** é caminho de escrita do app.

Porém, a **validação nova introduziu dois efeitos colaterais 🟠 no caminho da 29.3**, ambos assimetrias entre a validação do lado do gestor e a do lado do vínculo:

1. **🟠 Bug 17 — tijolamento do gestor:** como a validação roda em **todo** save, um vínculo de auto-gerência "tardia" já persistido (criado por upsert/bypass — e o dev reproduziu esse estado em runtime) faz o gestor **não editar e não desativar** pela aplicação (`desativar!` → `RecordInvalid`, `ativo` fica `true`). O estado é **auto-perpetuante** (sem caminho in-app de recuperação). Fecha: **renomear/alterar atributos irrelevantes à auto-gerência deve passar** (gatilhar a validação só quando `gestor_user_id` muda/novo).
2. **🟠 Bug 18 — assimetria inversa:** o lado do gestor ignora vínculos **inativos** (promoção de ex-gerido é legítima, por decisão do Bug 15), mas o lado do **vínculo** continua barrando um vínculo **INATIVO** cujo `user` é o `gestor_user` — e o banco/índice o aceita. Reconciliar o vínculo histórico via ActiveRecord na 29.3 falha/perde o dado. Fecha: aplicar o mesmo filtro `ativo` em `gerido_nao_e_o_proprio_gestor`.
3. **🟢 Bug 19 —** `destroy` sob bypass dá `InvalidForeignKey` em vez de `DeleteRestrictionError`; gravação ainda é impedida (correto), contrato do `restrict` não é o observado no nicho.

**Nenhum bloqueio de conformidade estrutural na 29.2 em si** (a tela é só `index`; nenhum write path existe hoje) — mas **17 e 18 são bloqueios de importação da 29.3** e devem entrar no escopo dela (ou virar correção da 29.2, dado que a validação do lado do gestor é código da 29.2). Nenhum dos dois exige bypass para se manifestar no caminho de escrita — é o que os distingue de "débito" e justifica 🟠.

**Sinalização ao CTO (padrão recorrente):** terceira rodada seguida em que o achado novo é a **assimetria validação × constraint-de-banco** (agora sobre o eixo **ativo/inativo** do invariante de auto-gerência, espelhando o Bug 12 sobre o eixo do par). Item permanente de checklist proposto: para **todo** invariante cruzando duas tabelas, testar os **4 quadrantes de `ativo`** pelos **dois lados** (validação de cada model + `insert_all!` no banco) **antes** de declarar fechado. Reforço: a mesma correção de guard de `desativar!`/`ativo?`/`scope :ativos` (concentrada no concern `Desativavel`) **não** alcança as validações de invariante nos dois models — a duplicação de regra entre `GestorIndividual` e `GestorIndividualGerenciado` é a fonte estrutural das duas assimetrias. O débito de i18n (`pt-BR` sem `record_invalid`, Bug 8/r1) reaparece em todo `RecordInvalid` desta rodada e **agora é load-bearing**: é a mensagem que o operador da 29.3 verá quando o upsert falhar.
