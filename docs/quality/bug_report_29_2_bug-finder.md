# Relatório Bug Finder — Iteração 29, Tarefa 29.2 — Dev B

> **Branch:** `feature/demanda-29-schema-gestor-individual`
> **Data:** 2026-09-29
> **Propósito:** Teste adversarial da migration `AddLegacyFieldsToGestoresIndividuais`, do concern `Desativavel` e dos models `GestorIndividual` / `GestorIndividualGerenciado` (schema para o dado real do Intranet — PRD §2.5). Nunca corrigir — apenas reportar.

## Resumo

| Métrica | Valor |
|---------|-------|
| Total de cenários testados | 23 |
| Bugs encontrados | 11 |
| 🔴 Crítico | 0 |
| 🟠 Alto | 2 |
| 🟡 Médio | 2 |
| 🟢 Baixo | 4 |
| ⚪ Info | 3 |

**Ambiente/evidências:** banco de teste `api_ponto_test` (10.150.110.174:5000) para os cenários de model/constraint; banco scratch descartável `api_ponto_scratch_292` (criado, populado, migrado, revertido, re-migrado e **destruído** ao fim) para o cenário de rollback com dados. Nenhum dado do `api_ponto_development` foi alterado. Nada foi commitado.

---

### Bug 1 — Rollback da migration é destrutivo: apaga todas as colunas de dado real

- Severidade: 🟠 Alto
- RF/RN violado: RN global "não apague dados do usuário / não remova histórico operacional sem arquivar"; critério 29.2 "Rollback testado"
- Passos:
  1. Popular um banco com dados de legado: gestor local + gestor importado (`id_legado`, `gestor_cpf`, `gestor_user`, `data_criacao_legado`) + vínculos.
  2. `bin/rails db:rollback STEP=1` (reverte a 29.2).
  3. Inspecionar as colunas e as linhas.
  4. `bin/rails db:migrate` (re-aplica).
- Atual: o `remove_column` do `change` apaga `id_legado`, `gestor_cpf`, `gestor_user_id`, `data_criacao_legado`, `ativo`, `data_exclusao` de **todas as linhas**. Após o rollback, `sample=[{nome="Local Scratch", id_legado=nil, ...}, {nome="Importado Scratch", id_legado=nil, gestor_cpf=nil, ...}]` — o `id_legado` 4242 e o `gestor_cpf` "111" do importado **desapareceram**; o vínculo perdeu o `id_legado` 777. O re-migrate recria colunas vazias e re-marca `ativo=true` (default), perdendo o estado de soft-delete. As linhas em si sobrevivem (só as colunas novas são dropadas).
- Esperado: `change` é reversível no *schema*, mas **não preserva os dados** das colunas novas. Como o Intranet (fonte) será descomissionado, um rollback acidental em produção descarta o único registro do vínculo legado — irrecuperável.
- Evidência:
  ```
  $ DATABASE_URL=... bin/rails db:rollback STEP=1
  -- remove_column(:gestores_individuais, :id_legado, :bigint)
  -- remove_column(:gestores_individuais, :gestor_cpf, :string)
  -- remove_column(:gestores_individuais, :observacao, :text)
  -- remove_column(:gestores_individuais, :ativo, :boolean, {:null=>false, :default=>true})
  -- remove_column(:gestores_individuais, :data_exclusao, :datetime)
  -- remove_column(:gestores_individuais, :data_criacao_legado, :datetime)
  -- remove_reference(:gestores_individuais, :gestor_user, {:foreign_key=>{:to_table=>:users}, :null=>true})
  == 20260929120000 AddLegacyFieldsToGestoresIndividuais: reverted (0.0399s)
  # após rollback: rows=2 / gestores cols=["id","nome","orgao","created_at","updated_at"]
  # re-migrate: sample=[{nome=>"Importado Scratch", id_legado=>nil, ativo=>true, gestor_user_id=>nil}]
  ```
- Impacto: perda definitiva de dados do legado após descomissionamento do Intranet. O rollback também cruza o sentido "aditivo" — a migration é aditiva *para frente*, mas o `remove` é integralmente destrutivo.
- Sugestão (não implementar): documentar a 29.2 como **forward-only** na medida em que o dado passa a ser fonte de verdade; se rollback for necessário, exigir backup snapshot da tabela antes do `db:rollback`. Não bloqueia a tarefa (nenhum código chama rollback), mas deve constar como risco operacional.

### Bug 2 — `dependent: :destroy` em `gestor_individual_gerenciados` executa hard-delete em cascata

- Severidade: 🟠 Alto
- RF/RN violado: RN global "nunca hard-delete / preserve histórico operacional"; desvio aprovado "soft-delete explícito via `desativar!`"
- Passos:
  1. `g = GestorIndividual.create!(nome: "t_dep")`
  2. `v = GestorIndividualGerenciado.create!(gestor_individual: g, user: u)`
  3. `g.destroy`
  4. Verificar `GestorIndividualGerenciado.exists?(v.id)`
- Atual: `false` — o `dependent: :destroy` (linha 22 de `gestor_individual.rb`) apaga **fisicamente** a linha do vínculo. Há uma via de hard-delete que contorna totalmente o soft-delete `desativar!`.
- Esperado: se a regra é "nunca hard-delete", a associação deveria ter sido trocada por `dependent: :restrict_with_exception` (ou removido o `dependent`), para que um `destroy` futuro do gestor não apague o histórico do vínculo silenciosamente.
- Evidência:
  ```
  === H. dependent: :destroy -> destroy do gestor apaga vinculos? ===
  antes: vinculo=true
  apos g3.destroy: vinculo existe=false (false => HARD-DELETE em cascata)
  ```
- Impacto: qualquer fluxo futuro (ou console, ou `destroy_all`) que chame `destroy` no gestor apaga os vínculos em cascata sem respeitar o `ativo`/`data_exclusao` do vínculo — a cascata da 29.4/29.6 perde a rastreabilidade do gerido. O desvio aprovado só cobriu *não sobrescrever `destroy`*, não *remover o `dependent` herdado*.
- Sugestão (não implementar): trocar por `dependent: :restrict_with_exception` (ou nenhum `dependent`) alinhado ao soft-delete, e cobrir com teste que prove que `destroy` do gestor **não** apaga vínculo. É o achado mais próximo de bloqueio da tarefa.

### Bug 3 — Vínculo duplicado (mesmo gestor, mesmo user) é permitido quando `id_legado` é nulo

- Severidade: 🟡 Médio
- RF/RN violado: critério 29.2 "reimportação não duplica o mesmo gestor→gerido"; impacto direto na contagem "Gerenciados" (29.3/29.4/29.6)
- Passos:
  1. Para um gestor g e um user u:
  2. `GestorIndividualGerenciado.create!(gestor_individual: g, user: u)` (id_legado nil)
  3. Repetir o mesmo create.
- Atual: `count == 2` — o banco aceita dois vínculos idênticos. O UNIQUE de `id_legado` não protege (admite múltiplos NULL); não há índice UNIQUE de par `(gestor_individual_id, user_id)`. Vínculos locais (sem `id_legado`) podem duplicar livremente.
- Esperado: um índice UNIQUE parcial/composto (ou guard) impedindo o mesmo par, sobretudo porque `gestor.gerenciados` não filtra por `ativos` hoje — a cascata herdará a duplicata.
- Evidência:
  ```
  === D. vinculo duplicado do MESMO par com id_legado null ===
  vinculos mesmo par: 2 (sem unique => duplica)
  ```
- Impacto: inflação da contagem de "Gerenciados" e listagem repetida do mesmo gerido na 29.4/29.6, exatamente o risco citado no desvio aprovado — mas o desvio só fecha o lado *importado*; o lado *local* fica aberto.
- Sugestão (não implementar): avaliar `add_index ..., [:gestor_individual_id, :user_id], unique: true` ou filtro/validação no fluxo de cadastro; decidir se faz parte da 29.2 ou de tarefa posterior.

### Bug 4 — Auto-gerência permitida: gestor individual pode gerenciar a si mesmo

- Severidade: 🟡 Médio
- RF/RN violado: RN §3 "bloqueia o próprio ponto" (29.5); integridade da cascata
- Passos:
  1. `gi = GestorIndividual.create!(nome: "x"); gi.update!(gestor_user: u)`
  2. `GestorIndividualGerenciado.create!(gestor_individual: gi, user: u)`
- Atual: `id` criado com sucesso; nada no banco nem no model impede que `gestor_user_id == user_id` no vínculo.
- Esperado: não é escopo explícito da 29.2, mas cria risco concreto para a cascata da 29.4/29.5 — o gestor passaria a se auto-autorizar. Um CHECK (`gestor_user_id <> user_id`) ou guard de model seria a defesa na borda.
- Evidência:
  ```
  === E. auto-gerencia: gestor_individual_id == user_id possivel? ===
  auto-gerencia criada id=49 (sem guard)
  ```
- Impacto: risco de autobenefício se a 29.4 tratar `gestor_user` como identidade autorizada; hoje mitigado apenas porque não há caminho de escrita além do console/fixtures.
- Sugestão (não implementar): registrar como débito carried-forward para 29.4/29.5 e/ou adicionar constraint.

### Bug 5 — Guard de `desativar!` é inconsistente nos estados limítrofes

- Severidade: 🟢 Baixo
- RF/RN violado: critério "idempotente / preserva a data da primeira exclusão"
- Passos:
  1. Caso A: registro com `ativo=false` e `data_exclusao=nil` → `desativar!(momento)`.
  2. Caso B: registro com `ativo=true` e `data_exclusao` preenchida (registro legado desativado com data mas flag divergente) → `desativar!(momento_novo)`.
- Atual: A retorna cedo? Não — o guard é `!ativo && data_exclusao.present?`, então com `data_exclusao` nulo ele **preenche** a data (não é idempotente no sentido de "não muda nada"). B **sobrescreve** a data legada pela nova.
- Esperado: um critério único e documentado — ou "preserva sempre a primeira data" (guard só em `!ativo`), ou "sempre sincroniza". Como está, o comportamento difere conforme o estado.
- Evidência:
  ```
  === 1. ativo=false, data_exclusao=nil ===  -> data=2026-09-29 10:00  (preenche)
  === 2. ativo=true, data_exclusao=2020-01-01 === -> data=2026-09-29 10:00 (sobrescreve legada)
  ```
- Impacto: na importação da 29.3 (que traz `data_exclusao` legada), chamar `desativar!` num registro legado pode sobrescrever a data real de exclusão do Intranet.
- Sugestão (não implementar): definir a semântica e alinhar o guard; documentar que o import deve setar `data_exclusao` legada diretamente, não via `desativar!`.

### Bug 6 — `desativar!` aceita `momento` nulo ou no futuro

- Severidade: 🟢 Baixo
- RF/RN violado: integridade do soft-delete
- Passos: `g.desativar!(nil)` e `g.desativar!("2099-12-31 23:59:59")`.
- Atual: `nil` grava `ativo=false, data_exclusao=nil` (estado "desativado sem data"); string no futuro é gravada como data de exclusão futura. Nenhuma validação de `momento`.
- Esperado: `momento` nulo deveria cair no default (`Time.current`) — hoje o default só é aplicado se o argumento for omitido, não se for `nil` explícito.
- Evidência:
  ```
  === 3. desativar! com momento nil === ativo=false data=nil
  === 4. desativar! com momento string / futuro === data=2099-12-31 23:59:59
  ```
- Impacto: dados de exclusão implausíveis (nulo ou futuro) dificultam auditoria e ordenação da cascata.
- Sugestão (não implementar): `momento ||= Time.current` e/ou validar intervalo.

### Bug 7 — FK `gestor_user_id` bloqueia `destroy` do `User` com `ActiveRecord::InvalidForeignKey` (sem `dependent:`, sem `on_delete`)

- Severidade: 🟢 Baixo
- RF/RN violado: consistência de deleção de `User` no domínio
- Passos:
  1. `u = User.create!(...); g = GestorIndividual.create!(nome: "x", gestor_user: u)`
  2. `u.destroy`
- Atual: `ActiveRecord::InvalidForeignKey: PG::ForeignKeyViolation ... still referenced from table "gestores_individuais"` (constraint `fk_rails_aa8c1610dd`). Não há `on_delete: :nullify` nem `dependent:` em `GestorIndividual`.
- Esperado: se um login local pode ser removido, a FK deveria anular (`on_delete: :nullify`) por ser opcional; hoje a remoção do usuário falha com exceção de banco (comportamento `restrict`).
- Evidência:
  ```
  === F. apagar User que e gestor_user de um gestor ===
  destroy levantou: ActiveRecord::InvalidForeignKey: PG::ForeignKeyViolation ... "fk_rails_aa8c1610dd" on table "gestores_individuais"
  === G. apagar User que e gerido ===
  destroy levantou: ... "fk_rails_ccb2d82d4d" on table "gestor_individual_gerenciados"
  ```
- Impacto: se houver fluxo futuro de remoção de `User`, ele quebrará com exceção crua. Para a 29.2 é apenas FK nova herdando o padrão `restrict` do projeto.
- Sugestão (não implementar): decidir política (anular vs restringir vs `dependent:`), coerente com `User#has_many ..., dependent: :restrict_with_exception` do resto do app. Nota: para o vínculo gerido, `restrict` é o comportamento correto (não anular); para `gestor_user` opcional, `nullify` é discutível.

### Bug 8 — Mensagem de `RecordInvalid` sai como "Translation missing" (locale pt-BR sem `record_invalid`)

- Severidade: 🟢 Baixo
- RF/RN violado: qualidade de diagnóstico; não é da 29.2, mas afeta o caminho de erro de `desativar!`
- Passos: provocar falha de validação em `desativar!` (ex.: `nome` em branco) e ler `e.message`.
- Atual: `"Translation missing: pt-BR.activerecord.errors.messages.record_invalid"`. O Rails só interpola as mensagens dos atributos quando a chave `record_invalid` existe; como `config/locales/pt-BR.yml` não a define, a mensagem perde o detalhe. `errors.full_messages` traz o correto ("Nome não pode ficar em branco").
- Esperado: `"Nome não pode ficar em branco"` também em `e.message`.
- Evidência:
  ```
  default_locale=pt-BR
  msg=Translation missing: pt-BR.activerecord.errors.messages.record_invalid
  full_messages=["Nome não pode ficar em branco"]
  ```
- Impacto: qualquer erro de validação em qualquer model do app reporta mensagem inútil em logs/UI quando acessado via `e.message`.
- Sugestão (não implementar): adicionar `errors.messages.record_invalid: "Validation failed: %{errors}"` (ou equivalente pt-BR) ao locale — provavelmente débito de tarefa de i18n, não da 29.2.

### Bug 9 — Concern `Desativavel` não valida presença das colunas: explode em runtime em model sem `ativo`/`data_exclusao`

- Severidade: ⚪ Info
- RF/RN violado: contrato do concern (documentado, mas não verificado em runtime)
- Passos: incluir `Desativavel` em model cuja tabela não tem as colunas e chamar `desativar!` / `ativos`.
- Atual: `NameError: undefined local variable or method 'ativo'` e `ActiveRecord::StatementInvalid: PG::UndefinedColumn: column users.ativo does not exist`.
- Esperado: o comentário do concern exige as colunas no host; nenhuma guarda impede inclusão indevida. Ambos os models atuais têm as colunas, então não há falha hoje.
- Evidência:
  ```
  include Desativavel em model sobre "users":
  NameError: undefined local variable or method `ativo`
  scope ativos: PG::UndefinedColumn: column users.ativo does not exist
  ```
- Impacto: risco só se o concern for reaproveitado fora dos models previstos.
- Sugestão (não implementar): nota de documentação; opcionalmente falhar cedo (`raise`) na inclusão se as colunas não existirem.

### Bug 10 — Sem constraint semântica (nome+orgao / gestor_cpf): local e importado podem coexistir duplicados

- Severidade: ⚪ Info
- RF/RN violado: risco para o casamento do upsert da 29.3 (não escopo explícito da 29.2)
- Passos: criar um local e um importado com o mesmo `nome`/`orgao`; criar dois `gestor_cpf` no mesmo CPF com máscara diferente.
- Atual: `count == 2` nos dois casos; nada normaliza/valida unicidade semântica.
- Evidência:
  ```
  locais+importados com nome identico coexistindo: 2
  dois formatos do mesmo CPF coexistem: 2
  ```
- Impacto: a 29.3 pode casar o registro local com o importado por engano (ou duplicar), já que só `id_legado` distingue. Sem `unique`/normalização de CPF, a ponte `gestor_cpf` é frágil.
- Sugestão (não implementar): definir em 29.3 a chave de casamento e normalização de CPF; registrar como decisão da importação.

### Bug 11 — `id_legado` aceita 0 / negativo / string numérica; sem valor-sentinela

- Severidade: ⚪ Info
- RF/RN violado: robustez da chave de upsert
- Passos: criar com `id_legado: 0`, `id_legado: -7`, `id_legado: "123"`.
- Atual: 0 e -7 persistem; `"123"` é convertido para `123`. `0` é um valor legítimo no UNIQUE (não é NULL) — se o legado usar 0 como sentinela de "sem id", colidiria com um id real.
- Evidência:
  ```
  A. 0 -> ok ; -7 -> ok
  B. valor persistido=123
  C. locais=2 importado=imp5
  ```
- Impacto: se a fonte trouxer 0/negativo para "sem vínculo", o upsert da 29.3 casaria registros indevidamente. String numérica virando inteiro é aceitável.
- Sugestão (não implementar): a 29.3 deve validar `id_legado > 0` antes do upsert; opcionalmente CHECK `id_legado > 0`.

---

## Cenários Testados (sem bugs)

- Rollback revertido e **re-migrado** no scratch com dados: colunas/FK/índices recriados corretamente, sem objeto órfão residual (FKs `[]`→`[["gestor_user_id","users"]]`, índices corretos). O *schema* volta intacto.
- Re-migrate após aplicação: `db:migrate` de novo é no-op (idempotente).
- `db:schema:load` do schema.rb atual no scratch: sem `PG::DuplicateObject` — o dedup de `calculo_diarios`/FK duplicada está correto. Confirmado que `web` não tinha bloco duplicado real (1 `create_table` `calculo_diarios`); o `git diff` mostra a dedup contra a linha-basada-em-merge.
- `id_legado` duplicado (gestores e vínculos) rejeitado pela **constraint do banco** via `insert_all!` (`RecordNotUnique`).
- Múltiplos registros locais (`id_legado` NULL) convivem nas duas tabelas; local NULL não conflita com importado com valor.
- `desativar!` marca inativo com data e **não apaga a linha**; não afeta gerido nem vínculo.
- `scope :ativos` exclui desativados nas duas tabelas; `ativo?` resolve para o predicado nativo.
- Registros locais existentes preservados pela migration aditiva; `gestor_user` opcional; `data_criacao_legado` datetime.
- Sem duplicatas em `db/schema.rb` (`create_table`, `add_foreign_key`, `add_index`).
- Suíte direcionada 34/119/0; RuboCop 7 arquivos 0 offenses; Zeitwerk OK.

## Veredito Final

**Nenhum bloqueio de conformidade**: os critérios literais da 29.2 são atendidos (migration aditiva, colunas/índices corretos, soft-delete, rollback de schema, UNIQUE de `id_legado`). Os 2 achados 🟠 são riscos que merecem decisão explícita antes da 29.3:

1. **Bug 2 (🟠)** é o mais relevante para a regra "nunca hard-delete": há uma via concreta de hard-delete em cascata (`dependent: :destroy`) que o desvio aprovado não cobriu. Recomenda-se corrigir ou abertamente aceitar/documentar.
2. **Bug 1 (🟠)**: rollback apaga o dado real; documentar como forward-only ou exigir backup antes de rollback.
3. **Bugs 3 e 4 (🟡)**: integridade do vínculo (duplicata de par e auto-gerência) — carried-forward para 29.4/29.5/29.6, com impacto direto na contagem da cascata.

**Sinalização ao CTO:** padrão recorrente — os testes da 29.2 provam a *constraint* e o *schema*, mas não exercitam `destroy`/cascata nem rollback **com dados**. Vale incluir no checklist de testes de migrations futuras: (a) rollback com dados presentes, (b) caminhos de hard-delete via `dependent:`, (c) estados limítrofes de flags de soft-delete. O locale `pt-BR` sem `record_invalid` (Bug 8) é débito de i18n de alcance global.
