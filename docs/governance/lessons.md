# Lições Aprendidas

> Registro de conhecimento operacional que emerge durante a implementação
> e que **não é coberto** pela documentação existente (iteration, quality, inception, ADRs).
> Ver skill `lessons-protocol` para critérios de registro.

---

### 2026-09-10 — Rolify `scopify` não cria scopes dinâmicos por nome de role

**Contexto:** Task 23.4 (Sprint 23) — instalação da gem rolify e configuração do model Role.
**Problema:** Assumi que `scopify` no model Role criaria scopes dinâmicos como `Role.admin`, `Role.gestor`, etc. (padrão que aparece em exemplos da gem). Os testes falharam com `NoMethodError` — um custo de ~30min de investigação.
**Solução:** `scopify` apenas estende o model com `Rolify::Adapter::Scopes`, habilitando 3 scopes fixos: `global` (roles sem resource), `class_scoped` (resource_type sem resource_id) e `instance_scoped` (resource_type + resource_id). Se precisar de `Role.por_nome`, defina um scope explícito ou use `Role.find_by!(name:)`.
**Lição:** Antes de testar métodos/semânticas de uma gem, leia o código-fonte da versão instalada — documentação e exemplos de blogs podem descrever versões/APIs antigas.

---

### 2026-09-10 — Rota customizada para controller Devise precisa de `devise_scope`

**Contexto:** Task 23.6 (Sprint 23) — mapeamento de `DELETE /logout` para `Users::SessionsController#destroy` (Devise).
**Problema:** Uma rota plain (`delete "logout", to: "users/sessions#destroy"`) quebrou com `NoMethodError: undefined method 'name' for nil` no destroy — `DeviseController#devise_mapping` lê `request.env["devise.mapping"]`, que só é setado por rotas geradas dentro de `devise_for`/`devise_scope`.
**Solução:** Envolver a rota em `devise_scope :user do ... end` (`constraints` interno que seta o mapping no request).
**Lição:** Toda rota que aponta para um controller Devise (mesmo action herdada) deve nascer dentro de `devise_scope :scope`, senão `devise_mapping` é nil e helpers como `resource_name` explodem com `nil.name`.

---

### 2026-09-10 — Coexistência sessão legada × Warden: skip `verify_signed_out_user` no destroy

**Contexto:** Task 23.6 (Sprint 23) — transição do login admin (`session[:user_id]`) para Devise/Warden.
**Problema:** Usuário logado pelo fluxo legado (só `session[:user_id]`, Warden vazio) não conseguia deslogar: o `verify_signed_out_user` (prepend_before_action) do `Devise::SessionsController#destroy` detectava "já deslogado" (Warden vazio) e abortava ANTES de limpar `session[:user_id]`.
**Solução:** `skip_before_action :verify_signed_out_user, only: :destroy` no controller custom + sincronizar `session[:user_id]` no `create` (via `super` com bloco) para que os dois mecanismos coexistam durante a transição.
**Lição:** Ao migrar de uma sessão manual para Devise em modo coexistência, o controller custom deve ser o ponto de sincronização — `verify_signed_out_user` assume que o Warden é a única fonte de sessão e aborta o logout em sessões legadas.

---

### 2026-09-21 — Ambiente real usa Ruby 3.4.2 (mise) apesar de `.tool-versions` apontar ruby-4.0.0 (missing)

**Contexto:** Task 24.1 (Sprint 24) — `bundle install` de novas gems no `Frequencia/api-ponto`.
**Problema:** `.ruby-version`/`.tool-versions` declaram `ruby-4.0.0`, mas o mise não tem essa versão instalada (`missing`); os docs do projeto citam "Ruby 4.0.0/Rails 8.0.4". Seguir as versões declaradas levaria a tentar instalar um Ruby inexistente ou a conclusões erradas de compatibilidade.
**Solução:** Verificar o ambiente real antes de qualquer comando: `bundle env` mostra Ruby 3.4.2 (mise) e `Gem Home`/`Gem Path` em `vendor/bundle/ruby/3.4.0` (config `path` em `~/.bundle/config`). Com isso, `bundle install`/`bundle exec` usam o vendor bundle correto; o Rails resolvido no lock foi 8.0.5 (satisfaz `~> 8.0.4`), sem conflito com as 4 gems novas (pagy 9.4.0, ransack 4.4.1, simple_form 5.4.1, zutils 4.0.0).
**Lição:** Antes de instalar gems, rodar testes ou avaliar compatibilidade no Frequencia, confira `bundle env` (Ruby real e Gem Home) — `.ruby-version`, `.tool-versions` e versões citadas nos docs podem estar defasados em relação ao ambiente executável.

---

### 2026-09-21 — `bundle exec rails` falha neste ambiente — usar os binstubs `bin/*`

**Contexto:** Task 23.10 (Sprint 23) — execução da suíte no `Frequencia/api-ponto` (Ruby 3.4.2 via mise, vendor bundle em `vendor/bundle/ruby/3.4.0`).
**Problema:** `bundle exec rails test`/`ruby -e` falham com `invalid switch in RUBYOPT: -e` (RuntimeError vindo do shim do mise/RubyGems wrapper), enquanto a lição anterior orientava usar `bundle exec`. `bundle env`, `bundle exec true` e `bundle exec rake` funcionam; o problema atinge o re-exec do `rails`/`ruby` pelo bundler.
**Solução:** Usar diretamente os binstubs do projeto: `bin/rails test`, `bin/rubocop <arquivos>`, `bin/rake` — todos funcionam e resolvem o bundle correto (`Bundler.setup` interno). Para validações pontuais de Ruby, evitar `bundle exec ruby -e` (falha) e rodar o script via `bin/rails runner` quando precisar do bundle.
**Lição:** No Frequencia, prefira SEMPRE `bin/*` (binstubs versionados no repo) a `bundle exec`; se um comando `bundle exec X` falhar com `invalid switch in RUBYOPT`, não investigue o shim — troque para `bin/X` e siga.

---

### 2026-09-23 — No ransack 4.4.x, os métodos `ransackable_*` são métodos de CLASSE, não de instância

**Contexto:** Task 24.6 (Sprint 24) — smoke test de carga conjunta das 4 gems; verificação de que a whitelist `ransackable_attributes` permanecia na gem (RN04 — whitelist real é escopo da Sprint 25).
**Problema:** `User.instance_method(:ransackable_attributes)` lançou `undefined method` erroneamente sugerindo que o método nem existia — na verdade ele existe, mas como método de classe (definido em `class << self` no `Ransack::Adapters::ActiveRecord::Base::ClassMethods`, `lib/ransack/adapters/active_record/base.rb`, com memoização `@ransackable_attributes ||=`).
**Solução:** Usar `User.method(:ransackable_attributes).source_location` para provar que a implementação vem da gem (e não de `app/models/`). Para a lista de atributos buscáveis: `User.ransackable_attributes` (sem instância).
**Lição:** Ao escrever testes de contrato sobre `ransackable_*` (whitelist, Sprint 25), consulte-os via método de classe (`Model.method(:ransackable_attributes)`/`Model.ransackable_attributes`), nunca `instance_method` — e lembre que a sobrescrita de whitelist também é em nível de classe.

---

### 2026-09-23 — Timing side-channel em endpoint `paranoid` do Devise: equalizar queries com phantom work, não tempo artificial

**Contexto:** Bug 10 (Sprint 23, 4ª rodada Bug Finder) — `POST /u/password` com `config.paranoid = true` e ActionMailer desmontado: email conhecido executa 5 queries e levanta/captura `NameError`; email desconhecido executa 1 query (SELECT miss). Delta de ~1-2ms permite enumerar contas por timing, mesmo com status/flash idênticos (B8/Bug 9).
**Problema:** Corrigir "dormindo" um tempo fixo (constant-time com `sleep`) adicionaria latência artificial a TODOS os requests legítimos e não replica a assinatura de I/O; a assinatura observável é o número/tipo de queries, não um tempo absoluto.
**Solução:** Phantom work no caminho mais barato: `Devise.token_generator.generate` (replica o SELECT por `reset_password_token` do caminho conhecido) + `transaction(requires_new: true)` com `update_all` em registro inexistente (`id = -1` → UPDATE de 0 linhas, SAVEPOINT/UPDATE/RELEASE). Resultado: mesma contagem de queries (5 = 5), zero dados alterados, sem latência artificial. Teste trava a invariante contando `sql.active_record` via `ActiveSupport::Notifications`.
**Lição:** Para neutralizar timing side-channel em endpoints paranoid, iguale a ASSINATURA DE I/O (queries), não o tempo com `sleep`; UPDATE em `id` inexistente é o "dummy write" inócuo perfeito (0 linhas, mesmas queries de transação). O custo do raise/rescue que não é replicado fica documentado como delta residual de µs.

---
---

### 2026-09-25 — Binstub `bin/brakeman` com `--ensure-latest` sai 0 sem escanear

**Contexto:** Tarefa 29.1 (Sprint 29) — validação de segurança registrada como "Brakeman OK" em três rodadas.
**Problema:** O binstub força `--ensure-latest`; com a gem instalada abaixo da última versão publicada, o Brakeman imprime só o aviso de versão e sai com código 0 **sem executar o scan** (nem `-o arquivo` é criado). O gate parece verde, mas não faz nada.
**Solução:** Até o chore de pipeline corrigir o binstub, validar com `RUBYOPT= bundle exec brakeman` (ou conferir que o relatório foi gerado) e registrar a contagem real de warnings (baseline: 4 pré-existentes).
**Lição:** Um gate de segurança só vale como evidência se produzir saída de scan (relatório/contagem de warnings); "exit 0" sozinho não prova execução.

---

### 2026-09-25 — Copiar trechos do schema.rb do Pessoas2 (Rails 6) para o Frequencia (Rails 8)

**Contexto:** Task 29.0 (Sprint 29), schema de teste do espelho Pessoas (ADR-0006).
**Problema:** Os `add_foreign_key` copiados literalmente falharam com `column "tipos_vinculo_id" referenced in foreign key constraint does not exist`. O `schema.rb` do Pessoas2 omite `column:` quando a coluna segue as inflexões **dele** (`tipos_vinculo` → `tipo_vinculo_id`); o Frequencia não tem essas inflexões e infere outro nome. Além disso, sem `ActiveRecord::Schema[6.0]` o Rails 8 cria `datetime` com precisão 6, diferente do banco real.
**Solução:** `column:` explícito em todas as FKs copiadas e `ActiveRecord::Schema[6.0].define`. O teste de divergência compara os blocos `create_table` byte a byte e as FKs por tabela e coluna.
**Lição:** Schema copiado entre apps com Rails e inflexões diferentes não é portável literalmente: fixe a versão de compatibilidade do `Schema[...]` e torne explícito tudo o que depende de inflexão. Obs.: o projeto usa Minitest 6, sem `minitest/mock` (`Object#stub` não existe); prefira dados reais ou injeção de dependência.

---

### 2026-09-29 — `bin/rails runner` em `RAILS_ENV=test` deixa lixo no banco de teste e falsifica o mutation testing

**Contexto:** Tarefa 29.2 (Sprint 29) — verificação manual independente do Bug 12 (`valid?` do model × `insert_all!` no banco) via `bin/rails runner` em `RAILS_ENV=test`.
**Problema:** O runner **não** roda dentro da transação do teste, então os registros criados persistem em `api_ponto_test`. `gestores_individuais` e `gestor_individual_gerenciados` **não têm arquivo de fixture**, logo `fixtures :all` (que faz DELETE + insert apenas das tabelas com fixture) não as limpa. O resultado foi 1 gestor e 2 vínculos órfãos apontando para `user_id=1` (os `users` de fixture são recriados com outros ids). Pior: na rodada de mutation testing seguinte, **todos** os testes falharam com `RuntimeError: Foreign key violations found in your fixture data` — 17 e 21 **erros** com 0 assertions, que pareciam mutações mortas mas eram só o banco sujo. Um mutation testing que "mata" a mutação por erro de carga não prova nada.
**Solução:** Limpar as tabelas sem fixture (`DELETE FROM` direto) antes de rodar a suíte; e, ao fazer mutation testing, **provar o baseline verde imediatamente antes de mutar** — uma mutação "pega" aparece como **1 falha limpa** (com assertions contadas), não como erro em massa com 0 assertions. Preferir `bin/rails test` com um teste dedicado (dentro da transação) a `bin/rails runner` para verificação de comportamento; se usar o runner, limpar depois.
**Lição:** Tabela sem arquivo de fixture não é limpa por `fixtures :all` — é estado persistente no banco de teste. Antes de confiar num resultado negativo de mutation testing, confira que o baseline estava verde e que a falha é `Failure` (com assertions), não `Error` de carga: sujeira de banco imita mutação morta.

---

### 2026-09-29 — `uniqueness` com `conditions:` valida o registro NOVO por inteiro: não espelha índice UNIQUE parcial

**Contexto:** Tarefa 29.2 (Sprint 29) — índice UNIQUE **parcial** em `(gestor_individual_id, user_id) WHERE ativo` (decidido para permitir histórico de re-vínculo) acompanhado da validação equivalente no model.
**Problema:** `validates :user_id, uniqueness: { scope: :gestor_individual_id, conditions: -> { where(ativo: true) } }` — o `conditions` filtra as linhas **existentes** na query, mas a validação continua rodando para **qualquer** registro novo, inclusive um que seja ele próprio inativo. Resultado: um vínculo novo `ativo: false` (histórico legado) era barrado com "User já está em uso" quando o par já tinha um ativo — **embora o índice parcial do banco o aceitasse** (`insert_all!` passava). Validação e constraint discordavam num quadrante, e os testes não cobriam esse lado (só testavam criar inativo quando *não* havia ativo).
**Solução:** `if: :ativo?` na validação, para que ela só rode quando o próprio registro é ativo — espelhando o predicado do índice. Cobrir os **4 quadrantes** pelos **dois lados** (validação Rails e `insert_all!`): ativo/ativo (barra), ativo/inativo (passa), inativo/ativo (passa — era o furo), inativo/inativo (passa).
**Lição:** Ao reproduzir um índice UNIQUE **parcial** em validação de model, o predicado do índice tem de valer para **ambos** os lados da comparação. `conditions:` só restringe o conjunto de linhas consultadas; quem decide *se* a validação roda é o `if:`/`unless:`. Índice parcial sem validação espelhada (ou vice-versa) gera divergência silenciosa que só aparece no quadrante não testado.

---

### 2026-09-29 — Validação de invariante deve rodar no EVENTO, não em todo save (senão "algema" o registro)

**Contexto:** Tarefa 29.2 (Sprint 29) — `validate :gestor_user_nao_e_gerido_ativo` em `GestorIndividual`, guardando o invariante "o login do gestor não pode ser um gerido ativo dele" (Bug 15).
**Problema:** a validação rodava em **todo** `save`. Quando um vínculo de auto-gerência "tardia" já estava persistido (criado por upsert/`insert_all!`, o caminho documentado da importação), o gestor virava um registro **inoperante**: `update!(nome:)`/`update!(orgao:)` e até `desativar!` (que usa `update!`) levantavam `RecordInvalid`, deixando `ativo=true` para sempre. O estado era **auto-perpetuante** — não havia caminho de recuperação pela aplicação (só `update_column`/SQL escapo). Um único dado ruim transformava o registro em intocável.
**Solução:** restringir o gatilho ao evento que muda o invariante: `validate :gestor_user_nao_e_gerido_ativo, if: -> { new_record? || will_save_change_to_gestor_user_id? }`. Renomear um gestor não cria nem desfaz auto-gerência, logo não deve revalidar. Efeito colateral positivo: elimina o `+1 SELECT` que a validação custava em todo save (o `exists?` só roda quando o login é (re)definido).
**Lição:** validação que depende de estado externo (outra tabela, associação) deve ser **event-scoped** (`will_save_change_to_X?` / `new_record?`). Rodá-la em todo save cria um modo de falha pior que o bug original: o registro fica impossível de corrigir pela própria aplicação. Sempre dê um caminho de recuperação in-app (aqui, `desativar!` precisava continuar funcionando) e teste explicitamente "edição de campo irrelevante ao invariante deve passar".

---

### 2026-09-29 — Invariante cruzando duas tabelas: os DOIS lados devem concordar sobre os 4 quadrantes de `ativo`

**Contexto:** Tarefa 29.2 (Sprint 29) — invariante de auto-gerência guardado em dois models (`GestorIndividual` e `GestorIndividualGerenciado`), porque um `CHECK` no Postgres não pode consultar outra tabela. O concern `Desativavel` centralizou `desativar!`/`ativo?`/`scope :ativos`, mas **não** alcança as validações de invariante — a regra ficou duplicada.
**Problema:** a correção do Bug 12 (`if: :ativo?` na validação de **par**) foi aplicada só de um lado. A validação de **auto-gerência do vínculo** ficou sem o filtro, então os dois lados **discordavam** sobre o mesmo vínculo inativo: o lado do gestor o ignorava (promover ex-gerido é legítimo desde o Bug 15) e o índice do banco também, mas o lado do vínculo o **barrava** — a importação da 29.3 falharia ao reconciliar o vínculo histórico via ActiveRecord, embora o banco o aceitasse (`insert_all!` OK). Três rodadas seguidas de Bug Finder acharam a mesma classe de bug, cada vez num eixo diferente (par, auto-gerência, agora entre os dois lados).
**Solução:** aplicar o mesmo `if: :ativo?` no lado do vínculo, fixando o invariante como *"nenhum vínculo ATIVO liga o gestor a si mesmo"* — idêntico nos dois models e no índice. Testar os **4 quadrantes de `ativo`** (ativo/ativo, ativo/inativo, inativo/ativo, inativo/inativo) **pelos dois lados** (validação Rails de cada model + `insert_all!` no banco).
**Lição:** ao guardar um invariante em mais de um ponto (validação de model A, validação de model B, constraint de banco), o único jeito de não gerar divergência silenciosa é declarar a regra **uma vez** e cobrir a matriz inteira nos dois lados. Divergência aparece sempre no quadrante que ninguém testou — e o caminho que falha é o da importação, não o do usuário.

---

### 2026-09-29 — `RecordInvalid#message` consulta `activerecord.errors.messages.record_invalid`, não `errors.messages.record_invalid`

**Contexto:** Tarefa 29.2 (Sprint 29), Bug 8 do Bug Finder — `e.message` de qualquer `ActiveRecord::RecordInvalid` do app saía como `"Translation missing: pt-BR.activerecord.errors.messages.record_invalid"`. O CTO promoveu a blocker da 29.3 (é a mensagem que o operador verá quando o upsert da importação falhar).
**Problema:** o palpite natural foi adicionar `record_invalid` em `errors.messages` (o bloco que o `pt-BR.yml` já tinha, com `blank`, `invalid`, `taken` etc.). Um teste que consultava `I18n.t("activerecord.errors.messages.record_invalid", default: nil)` **refutou o palpite**: retornava `nil`. O `ActiveRecord::RecordInvalid` consulta o namespace **`activerecord.`**; o `errors.messages.record_invalid` é apenas fallback do `ActiveModel`, e só funciona se o namespace específico não tiver a chave.
**Solução:** definir a chave **nos dois caminhos** para que concordem independentemente de qual seja consultado — `errors.messages.record_invalid` e `activerecord.errors.messages.record_invalid` (mais `restrict_dependent_destroy`, usada pelo `dependent: :restrict_with_exception`). Verificado em runtime: `e.message` passou a ser `"1 erro impediu este registro de ser salvo: Nome não pode ficar em branco"`.
**Lição:** ao consertar tradução "Translation missing", **não adivinhe o caminho da chave — leia-o da própria mensagem de erro** (ela imprime o caminho completo procurado) e **prove por teste** que a chave resolve com `I18n.t(caminho, default: nil)`. Namespaces de i18n têm fallback em cascata (`activerecord.` → `errors.`), e acertar só o fallback parece funcionar em uns pontos e falhar em outros.

---

---

### 2026-09-29 — Callback de validação NUNCA deve chamar `reload` na instância do chamador

**Contexto:** Tarefa 29.2-D7 (Sprint 29). O Code Reviewer achou que a validação de auto-gerência lia `gestor_individual.gestor_user_id` de uma instância possivelmente **stale** (carregada antes de outra instância salvar o login): `GestorIndividualGerenciado.new(gestor_individual: stale, ...)` gravava auto-gerência. O fix aplicado foi `gestor = gestor.reload if gestor.persisted?` dentro do callback.
**Problema:** o `reload` **muta o objeto do chamador** (`vinculo.gestor_individual.equal?(g) == true`) e **descarta mudanças pendentes**. No caminho normal de escrita (carregar o gestor → resolver o login **sem salvar** → gravar o vínculo — exatamente o fluxo da importação), o `reload` apagava o `gestor_user` recém-atribuído, a validação lia `nil` do banco e o código **gravava um vínculo de auto-gerência ATIVA**: `vinculo.save => true`, `g.changed == []`, auto-gerência no banco. O fix de um falso-positivo criou um falso-negativo **pior** — auto-autorização persistida na cascata da 29.4/29.5. Efeito colateral adicional: atributos pendentes (`nome`, `orgao`) também eram perdidos silenciosamente.
**Solução:** ler o valor do outro lado **sem recarregar a instância** — somar o valor **em memória** (`gestor.gestor_user_id`, cobre o login pendente do chamador) e o valor **no banco** via `Model.where(id:).pick(:coluna)` (cobre o login salvo por outra instância; `pick` não instancia nem muta nada). Custo: 1 query por validação, o mesmo do `reload`. Brinde: `pick` devolve `nil` para registro ausente, eliminando um `ActiveRecord::RecordNotFound` cru que o `reload` levantava quando o gestor fora apagado por outra sessão.
**Lição:** **`reload` dentro de callback de validação é sempre suspeito.** Validação deve ser observadora — não pode mutar o objeto que está sendo validado nem os que recebeu. Quando o invariante precisa "ver o outro lado atualizado", leia o valor com uma query pontual (`pick`/`where(...).exists?`) em vez de recarregar a instância. Testar sempre os dois cenários opostos: valor **pendente em memória** e valor **salvo por outra instância** — um fix que resolve só um dos lados troca o bug de sinal.

---

---

### 2026-09-29 — Config lida só de credentials quebra em CI limpo (o `master.key` não é versionado)

**Contexto:** Tarefa 29.2 (Sprint 29), débito B1 do review final. O CI precisa do banco do espelho `frequencia_pessoas_espelho_test`, e o bloco `pessoas` do `config/database.yml` lia `Rails.application.credentials.dig(:pessoas_db, ...)` para host/usuário/senha/porta.
**Problema:** o `credentials.yml.enc` é versionado, mas o `master.key` **não** (corretamente ignorado). Em CI limpo — ou em qualquer máquina sem a chave — `credentials.dig(:pessoas_db, :username)` devolve `nil`, o Postgres recebe **usuário vazio** e a conexão falha **antes de qualquer teste rodar**, com um erro que parece problema de banco e não de configuração. O bloco `pessoas` era o único do arquivo sem fallback por ENV.
**Solução:** `ENV.fetch("PESSOAS_DB_*", Rails.application.credentials.dig(...))` — ENV com precedência, credentials como fallback. Mesmo padrão que o próprio arquivo já usava no bloco `intranet_*` (produção). Verificado nos dois sentidos: sem ENV conecta como o usuário das credentials; com ENV, o usuário passa a ser o da variável (a sobreposição funciona).
**Lição:** **credencial que só existe em `credentials.yml.enc` é um beco sem saída em CI.** Todo bloco de `database.yml` que precise rodar em runner limpo deve aceitar override por ENV (`ENV.fetch("X", credentials...)`). Ao adicionar um serviço externo à suíte, teste o caminho "sem `master.key`" — é o cenário do CI, e ele falha de um jeito que se disfarça de problema de banco.

---

### 2026-09-29 — Suíte que depende de banco auxiliar não preparado: `skip` explícito em vez de erro de conexão

**Contexto:** Tarefa 29.2 (Sprint 29). Os testes do espelho Pessoas (`test/support/pessoas_espelho_helper.rb` e 3 arquivos que o incluem) leem um banco separado (`frequencia_pessoas_espelho_test`) com schema carregado à parte (`RAILS_ENV=test bin/rails test:pessoas_schema:load`).
**Problema:** sem esse banco — CI limpo, máquina nova, clone recém-feito — os testes explodiam com `PG::UndefinedTable`, **19 erros** que pareciam falha de código. Um erro de conexão esconde o problema real ("falta um passo de setup") e polui o sinal da suíte; um amigo desenvolvedor conclui que "a suíte está quebrada".
**Solução:** guarda `skip_sem_espelho!` chamada no `setup` dos testes afetados: se a conexão falhar ou as tabelas não existirem, `skip` com o comando exato do setup na mensagem. Verificado: com as tabelas removidas → **19 skips, 0 erros**; com o banco → roda normalmente, **0 skips**. O `skip` mantém o sinal honesto de cobertura.
**Lição:** teste que depende de banco/serviço auxiliar deve detectar a ausência e **pular com o motivo**, nunca estourar erro de infraestrutura. `skip` aparece no relatório e diz o que fazer; `PG::UndefinedTable` parece bug. Combine com o preparo correto no CI — o skip é rede de segurança, não substituto do setup.

---

### 2026-09-29 — Validação de auth do Postgres em CI tem de rodar no CONTAINER: o `pg_hba` local (`trust`) engana

**Contexto:** Bloco de esteira da Sprint 29 — passo "Create the Pessoas mirror test database" do `ci.yml` + bloco `pessoas` de test do `database.yml`. A "correção do falso-verde" havia sido validada **na máquina do dev**, onde "com ENV o usuário passou a ser o da variável" foi tido como prova suficiente de que o setup funcionaria no runner.
**Problema:** a validação no dev usou o `.pg_hba.conf` **local**, que tem `trust` no loopback e **não exercita** a rota de rede nem a auth do runner. A imagem oficial do Postgres (`postgres`/`postgres:17`) aplica, após o entrypoint, `host all all all scram-sha-256` — as linhas `trust` de loopback do initdb são substituídas. Conexões do runner chegam pelo bridge como `172.17.0.1` (comprovado com `inet_client_addr()`), ou seja, caem na regra **scram**. Resultado: a role `app.frequencia` criada **sem senha** (`CREATE ROLE ... LOGIN`, `rolpassword = NULL`) + `PESSOAS_DB_PASSWORD: ""` faziam o `test:pessoas_schema:load` abortar com `fe_sendauth: no password supplied` (**EXIT=1**). O CI estava **vermelho como escrito** e a falha só apareceria no primeiro push — a etapa "antes" nunca tinha sido executada num runner.
**Solução:** re-validar a sequência (`CREATE ROLE` → `createdb` → `test:pessoas_schema:load`) **dentro de um container `postgres:17` oficial**, com o env exato do CI. A correção escolhida foi a de menor superfície: dar senha explícita à role (`CREATE ROLE "app.frequencia" LOGIN PASSWORD 'app'`) e passar a mesma em `PESSOAS_DB_PASSWORD`. Após a correção: `db:test:prepare` EXIT=0, `test:pessoas_schema:load` EXIT=0 e os testes do espelho **19 runs/68 assertions/0 skips** contra o container. `POSTGRES_HOST_AUTH_METHOD: trust` também resolveria, mas trocar a auth do cluster inteiro é superfície maior que a senha de uma role.
**Lição:** **a máquina do dev não é o CI.** Validação de esteira que dependa de auth de Postgres, rota de rede ou preparo de banco auxiliar deve ser executada num container oficial **equivalente ao `services:` do workflow** (mesma imagem, mesmas ENV), lendo as conexões pelo bridge — o `trust` do loopback local esconde exatamente o caso `scram-sha-256` que o runner impõe. Corrija a auth preferindo a mudança de menor superfície (senha da role, não a auth do cluster) e mantenha o gate `psql ... | grep -q 1` sem `|| true` — ele é o que impede o CI de ficar verde sem preparar o banco.

---

### 2026-09-29 — Código de saída de ferramenta com precedência interna pode MASCARAR a checagem que você ligou (Brakeman: exit 3 esconde 8/9)

**Contexto:** Chore do fork do CI (Sprint 29). O ruling M2 ligou as flags anti-drift `--ensure-ignore-notes` (exit 8) e `--ensure-no-obsolete-ignore-entries` (exit 9) no `bin/brakeman` para tornar o ledger `config/brakeman.ignore` um registro auditável. As flags estavam **corretamente injetadas** e provadas funcionais — em isolation.
**Problema:** no Brakeman 8.0.5, `Commandline#regular_report` avalia `exit_on_warn` (exit 3) **antes** das checagens anti-drift (`commandline.rb:150` vs `:158`/`:163`). Com **qualquer** warning não-ignorado vivo (o `Medium` EOLRails, time bomb do bump), o processo **sempre** sai 3 — e o sinal da política some: nota vazia → 3 (esperado 8), entrada obsoleta → 3 (esperado 9). As **mensagens** eram impressas, só o **código** era mascarado. Efeito: um ledger com nota faltando ou entrada obsoleta **passava despercebido** — a salvaguarda ficava cega exatamente por causa do warning que ela não deveria silenciar. Isso só apareceu **após** dar sinal aos exits manualmente (mutando o ledger e medindo o código); a leitura do código do binstub não bastava.
**Solução:** o binstub passou a capturar a saída, reemití-la verbatim e promover o exit ao código **prescrito** (8/9) quando detecta o padrão de falha de política — sem remover o EOLRails do scan (`-x`/`--no-exit-on-warn` seriam silenciadores). Cuidado de implementação crítico: o `ensure` do wrapper não pode engolir exceção — a primeira versão capturava só `SystemExit` e um crash inesperado cairia no `ensure` com `exit(real_exit=0)`, virando **verde-por-engano** (o anti-padrão da sprint); a versão final tem `rescue StandardError => real_exit=1`.
**Lição:** **flag ligada ≠ flag com sinal.** Antes de confiar num código de saída como gate, **mutar a condição que ele detecta e medir o exit real** — não inferir da leitura do código. Quando uma ferramenta tem precedência interna entre códigos de saída, códigos de menor prioridade ficam inalcançáveis justamente no estado normal (com outros warnings presentes). Ao escrever um wrapper que reatribui exit codes, garanta que o caminho de exceção **preserve fail-safe** (nunca 0).

---

### 2026-09-29 — Fork de CI para outro provedor: medir o registry/imagem alvo, e não criar a branch de `develop` cegamente quando o fork depende de trabalho não-mergado

**Contexto:** Chore de fork do CI do Frequencia (GitHub Actions → GitLab, remote de produção). Dois tropeços concretos.
**Problema 1 (imagem):** o modelo `pessoas2/.gitlab-ci.yml` usa `registry.gitlab.tjpi.jus.br/...`, mas o registry institucional **não resolve fora da rede da instituição** (`Could not resolve host`, medido) e não havia imagem publicada para a versão real do Ruby do projeto. Copiar o modelo cegamente daria um CI que não baixa a imagem.
**Problema 2 (branch base):** o protocolo AGILE manda criar a chore a partir de `develop`. Mas o `.gitlab-ci.yml` referencia flags (`--ensure-ignore-notes`), o ledger `config/brakeman.ignore`, o passo do banco espelho no `ci.yml` e o `ENV.fetch` do bloco `pessoas` — **tudo isso só existe** na branch de feature da sprint (19 commits à frente de `develop`; `develop` não tem nenhum). Criar de `develop` geraria um CI que chama flags/arquivos inexistentes.
**Solução:** (1) documentar a imagem real como dívida e usar `ruby:3.3.8-slim` (versão **medida**, não a `.ruby-version` que dizia `4.0.0` inexistente); (2) criar a branch a partir do HEAD da feature e **registrar o desvio** com o merge target correto (`feature/demanda-29-...`, não `develop`). Também: o fork **torna visível** o débito pré-existente de lint (RuboCop exit 1, 77 offenses em 17 arquivos) — não mascarar com `|| true`; registrar como débito.
**Lição:** ao fork-ar CI entre provedores, **valide a imagem/registry de destino por execução** (não por cópia do modelo) e **verifique a base da branch** contra o que o artefato referencia — um fork é acoplado a tudo que ele invoca. Se o protocolo manda `develop` mas a dependência não está lá, o desvio é a decisão correta, **desde que registrado** (merge target explícito). E um fork que ativa gates adormecidos revela débito pré-existente: o certo é **torná-lo visível e rastrear**, nunca silenciar.

---

### 2026-09-29 — Fork de CI: um gate vermelho num stage ANTERIOR impede o stage seguinte de rodar (fail-fast do GitLab)

**Contexto:** Chore do fork do CI (Sprint 29). O `.gitlab-ci.yml` tinha 3 stages sequenciais `security` (Brakeman, exit 3 por design — `Medium` EOLRails) → `quality` (RuboCop, exit 1 por 77 offenses pré-existentes) → `test` (o OBJETIVO da chore: criar o banco espelho + rodar a suíte).
**Problema:** por default o GitLab é **fail-fast** — "if any job fails, the pipeline is marked as failed and jobs in later stages do not start". Como os dois primeiros saem vermelhos (débito pré-existente que o próprio fork tornou visível), o stage **`test` NUNCA executava**. O pipeline ficava vermelho e o passo que a chore existia para entregar nem rodava: o objetivo declarado **não era atendido**, e o modo de falha era invisível ("parece que o CI existe, mas o test não roda"). Antes de existir `.gitlab-ci.yml`, o problema também não aparecia — foi o fork que o criou.
**Solução:** `allow_failure: true` em `security` e `quality` (o job RODA, a saída fica no log, só não bloqueia a esteira), com DONO + PRAZO + critério binário de remoção registrados. **Verificado nos dois sentidos** com `gitlab-ci-local@4.75.1` (engine que implementa a semântica do GitLab): com `allow_failure` → `test` executa (marker presente, pipeline 0); sem → `test` não executa (pipeline 1). O arquivo real passou no `json schema validated`.
**Lição:** **ao projetar um pipeline multi-stage, o estado de saída dos jobs ANTERIORES é parte do contrato do job que você quer garantir.** Um gate vermelho "conhecido" num stage inicial não é só um vermelho a mais: ele **desliga silenciosamente** todos os stages seguintes. Ao criar/forçar um CI que ativa gates adormecidos, sempre pergunte "o que roda DEPOIS dos gates que vão falhar, e ele ainda roda?" — e prove com a semântica de fail-fast (ou por `allow_failure` consciente, ou por `needs: []`). `allow_failure` num scan de segurança só é honesto com dono, prazo e critério de remoção explícitos; senão vira papel de parede.

---

### 2026-09-29 — Fork de CI: `localhost` NÃO alcança o `services:` no executor docker do GitLab (services resolvem por ALIAS; não há forwarding de porta)

**Contexto:** Chore do fork do CI (Sprint 29). O `.gitlab-ci.yml` foi adaptado do `ci.yml` de GitHub e manteve `localhost` em `pg_isready`, `psql` e `createdb`. O `ci.yml` de GitHub funciona com `localhost` porque declara `ports: 5432:5432` no service — **é a publicação de porta que faz `localhost` funcionar lá**. Essa linha **não foi carregada** para o GitLab.
**Problema:** no executor docker do GitLab, os `services:` são publicados na rede do runner e resolvidos por **hostname/alias** (a diretiva `alias:`), **sem forwarding de porta para `localhost`**. No primeiro job real, `until pg_isready -h localhost` **pendura o job até o timeout** e o `test` nunca roda — o exato objetivo da chore. O `alias: postgres` estava declarado e **não usado**. Junto disso, faltavam `DATABASE_URL` (o `test.primary` não tem host/usuário no `database.yml`; sem a URL o `db:test:prepare` falha EXIT=1) e `PGPASSWORD` (contra a imagem oficial `scram-sha-256`, `createdb` trava no prompt e `psql` nega).
**Solução:** usar o **alias** (`-h postgres`, `DATABASE_URL=...@postgres:5432`, `PESSOAS_DB_HOST=postgres`) e trazer `DATABASE_URL` + `PGPASSWORD` do `ci.yml`. **Provado com Docker real**: rede própria + `--network-alias postgres` + `postgres:17` **sem publicar porta** + container `ruby:3.3.8-slim` na mesma rede → `localhost:5432` recusado (`pg_isready` EXIT=2), `postgres:5432` ok (EXIT=0). A sequência completa do job (`pg_isready` → role → `createdb` → `grep -q 1` → `db:test:prepare` → `test:pessoas_schema:load` → espelho 19/68/0) ficou toda verde por alias.
**Lição (duas):**
1. **`gitlab-ci-local` NÃO expõe este bug** — ele publica as portas em `localhost`, semântica divergente do executor docker real. A prova anterior passou e **não valia** para este aspecto. Para semântica de rede de services, a prova tem de ser **Docker real com rede própria e sem publicar porta**.
2. Ao fork-ar CI entre provedores, **cada suposição de rede/ambiente do arquivo original precisa ser re-verificada, não herdada** — `ports:` de um provedor vira `alias` no outro; variáveis como `DATABASE_URL`/`PGPASSWORD` que "funcionavam" podem não ter sido percebidas por estarem num job que nunca rodou. E **um comentário que afirma uma garantia falsa é pior que nenhum**: o comentário dizia que o `|| true` do `CREATE ROLE` cobria a falha de auth, quando ele usa o MESMO caminho de autenticação e falharia junto — a cobertura real era `PGPASSWORD` + `until pg_isready` + o `createdb -O` em cascata.

---

### 2026-09-30 — Monorepo: o GitLab só lê `.gitlab-ci.yml` na RAIZ do repo (validar conteúdo ≠ validar que a ferramenta o encontraria)

**Contexto:** Chore do fork do CI (Sprint 29). O `.gitlab-ci.yml` foi criado em `api-ponto/.gitlab-ci.yml`, seguindo o modelo `pessoas2/.gitlab-ci.yml`. Validamos o YAML, o schema do GitLab (`gitlab-ci-local`), a sequência do job `test` em container, o fail-fast, etc.
**Problema:** o repositório `Frequencia` é um **MONOREPO** — a raiz git contém `api-ponto/` (app Rails), `docs/`, `PRD-*.md`, `SPRINT-PLAN.md`. O **GitLab só lê o `.gitlab-ci.yml` na raiz do repositório**; **não há descoberta automática em subpasta**. Logo o pipeline **nunca foi criado**: o stage `test` não "falhou" — **não existia**. Toda a validação de conteúdo era real, mas o arquivo não era lido pela ferramenta. O modelo `pessoas2` **não se aplicava**: é um app Rails **único na raiz** (não é monorepo), com o arquivo na raiz e sem `cd`.
**Solução:** mover para a raiz (`Frequencia/.gitlab-ci.yml`) + **`cd api-ponto` no `before_script` global** (o `before_script` e o `script` rodam no mesmo shell, então o `cd` persiste e todos os comandos relativos a `api-ponto/` continuam válidos). Provado: sem `cd`, `bin/brakeman`/`bin/rails` da raiz → **EXIT=127**; com `cd`, a sequência do `test` roda (db:test:prepare EXIT=0, load EXIT=0, espelho 19/68/0). Comentário no topo do arquivo explica o monorepo e o `cd`.
**Lição (a mais importante da sessão):** **validar o CONTEÚDO de um artefato não é validar que a ferramenta o LERIA no lugar certo.** Esta foi a **quarta variação do mesmo erro de método** nesta sessão, e todas passaram pelo mesmo furo: a validação media algo *parecido* com a condição real, mas não a condição real.
1. Validar a auth do Postgres **no dev** (loopback `trust`) em vez de no container `scram`.
2. Validar o job no **`gitlab-ci-local`**, que publica porta em `localhost` (semântica divergente do executor real) — a prova passou e não valia.
3. Confiar no **`--ensure-latest`** que saía 0 **sem escanear** (gate que passa sem executar).
4. Validar um **arquivo que o GitLab não lê** (subpasta de monorepo).
> Regra prática: antes de "provar" o funcionamento, pergunte **"esta prova exercita a MESMA condição do ambiente real — inclusive ONDE a ferramenta procura o artefato e COMO ela resolve a rede?"**. Se não, é uma prova de conteúdo, não de integração. Para arquivos de configuração de ferramenta, a primeira verificação é de **descoberta/localização**, não de sintaxe. E: **um modelo copiado de outro projeto só vale se a ESTRUTURA do repositório for a mesma** (monorepo ≠ app único na raiz).

---

### 2026-09-30 — Governança: raiz de documentação ambígua (D4) — ponteiro de caminho absoluto é um acoplamento a vencer pelo git, não por uma árvore "espelho"

**Contexto:** O `AGENTS.md` da raiz do workspace (acima da raiz git `Frequencia/`) declarava como "Fonte de verdade" o caminho `workspace_integração/docs/`. Existiam **três** árvores de `docs/` ao mesmo tempo: `workspace_integracao/docs/` (parada em 2026-09-21, não versionada, vive ACIMA da raiz git), `Frequencia/docs/` (viva, versionada, 97 arquivos rastreados) e `pessoas2/docs/` (projeto irmão, outra taxonomia).
**Problema:** um agente que seguisse o `AGENTS.md` ao pé da letra lia e regenerava documentação **morta** (sem commit, invisível para o time), agravando a defasagem da árvore viva. Já ocorreu na sessão: um `/summarize` foi iniciado com a taxonomia errada. A árvore morta sequer é versionada — nenhuma mudança nela chega ao repositório, o que a torna uma armadilha silenciosa: parece correta, mas evaporaria.
**Solução:** repontar o `AGENTS.md` (11 ocorrências: linhas 7/27/36/37/45/66–71) para `Frequencia/docs/` e corrigir a taxonomia da Seção 4 (o layout vivo é numerado `00-contexto/`…`12-plano-implementacao/` + `adr/`/`specs/`/`quality/`/`governance/`/`progress/` — **não** `inception/`/`analysis/`/`knowledge/`, que são do `pessoas2`). Neutralizar a árvore morta fica **proposto** (regra do usuário: não apagar sem aprovação explícita).
**Lição:** (a) **um caminho absoluto num arquivo de governança é uma dependência de configuração como qualquer outra** — quando ele aponta para fora da raiz git, o alvo pode divergir sem que o git avise, porque não há versionamento que acuse o drift; a primeira verificação ao carregar contexto é **confirmar que a raiz apontada é a versionada** (medida: `git ls-files docs | wc -l > 0`). (b) **Duas cópias de uma mesma árvore de docs são uma armadilha de método, não uma redundância inofensiva**: cedo ou tarde um agente lê a cópia parada; a única cópia saudável é a versionada, e a morta deve virar **ponteiro/symlink** (ou ser removida, com aprovação), nunca coexistir. (c) **`AGENTS.md` acima da raiz git é, por construção, não versionado** — o próprio arquivo manda mantê-lo "na raiz do repositório"; se o time depende dele, ele precisa migrar para dentro do repo (`Frequencia/AGENTS.md`) para que suas mudanças sejam revisáveis e propagadas com o código.

---

### 2026-09-30 — GitHub Actions em monorepo: mover o workflow para a raiz NÃO basta — `defaults.run` não cobre `uses:`, e um step pré-checkout quebra com `working-directory`

**Contexto:** Chore `chore/github-workflows-root` (CC). O `api-ponto/.github/workflows/ci.yml` (GitHub Actions) vivia em subpasta de um **MONOREPO** (raiz git = `Frequencia/`, app Rails em `api-ponto/`) — mesmo defeito de monorepo já corrigido no `.gitlab-ci.yml` (`7db515c`): o GitHub só descobre workflows em `.github/workflows/` na **RAIZ**, então ele **nunca executou** (não falhava: não existia). A correção "mover para a raiz" foi óbvia; o que **não** é óbvio é o que o `working-directory` cobre.
**Problema:** a estratégia espelhada do GitLab (`cd api-ponto`→`defaults.run.working-directory: api-ponto`) cobre **só steps `run:`**. Duas armadilhas que o `defaults` sozinho NÃO resolve e que produziriam um workflow que **parece** correto e quebra no runner:
1. **`ruby/setup-ruby` é um step `uses:`** — não é afetado pelo `defaults.run`. Sem o input próprio `working-directory: api-ponto`, o `bundler-cache` procura `Gemfile.lock`/`.ruby-version`/`.tool-versions` na **raiz** e não os acha (a app é em `api-ponto/`); com `.ruby-version` da raiz ausente, o `bundler` cai no default e o cache falha silenciosamente.
2. **Um step `run:` que roda ANTES do `actions/checkout`** (o "Install packages" do job `test`) — o runner resolve o cwd ANTES de `api-ponto/` existir e falha com "working directory does not exist". É preciso sobrescrever com `working-directory: .` (a raiz existe sempre).
   Achado colateral do mesmo defeito: o **`.github/dependabot.yml`** também estava em `api-ponto/` (GitHub só lê da raiz) — movido para a raiz, com `directory: "/api-ponto"` no ecossistema `bundler` (o `directory` do Dependabot é relativo à **raiz do repo**, não ao local do arquivo).
**Solução:** `defaults.run.working-directory: api-ponto` para os 5 `run:` + `working-directory: api-ponto` no input do `setup-ruby` (×3) + `working-directory: .` no step pré-checkout. Provado por **descoberta** (actionlint em Docker): na raiz → `Detected project`, 0 erros (EXIT=0); na subpasta (estado antigo) → `no project was found` (EXIT=3). Controle positivo do linter (erro injetado) → detectado (EXIT=1). Comandos: raiz → EXIT=127 nos 3 (`bin/brakeman`/`bin/rubocop`/`bin/rails`); `api-ponto/` → 3/1/0.
**Lição (três):**
1. **`defaults.run.working-directory` é do `run:`, não do workflow.** Em monorepo, todo `uses:` que resolve caminho relativo (checkout, setup-ruby/bundler-cache, cache, upload-artifact) tem de receber o diretório **pelo input próprio**, não pelo `defaults`. Verifique a doc do input de cada action — não presuma que o `defaults` a alcança.
2. **A posição do step no job importa quando o cwd é a app em subpasta:** um passo que precisa rodar antes do checkout (instalar pacotes de sistema) não pode herdar o `working-directory` da app — ele precisa do diretório que existe **sempre** (a raiz).
3. Isso é mais uma instância da lição da sessão: **"mover para o lugar certo" resolve a DESCOBERTA, não a EXECUÇÃO.** O caso #4 ensinou que a ferramenta precisa **achar** o arquivo; este ensina que, achado o arquivo, cada caminho interno ainda precisa **resolver** a partir do novo cwd — e nem todo mecanismo de "diretório padrão" alcança todo tipo de step.

---

---

### 2026-09-30 — Stub de método de classe em teste: `remove_method` no teardown APAGA o método real e envenena os testes seguintes (e um teste pode passar por não exercitar a condição real)

**Contexto:** Tarefa 29.3 (Sprint 29), testes novos do serviço/job/rake de importação. Os testes precisavam stubar métodos de classe reais (`ResolverCpfPorMatriculaService.mais_recente`, `ImportarGestoresIndividuaisService.call`, `SticapiClient::Intranet.gestores_individuais`). O padrão vigente no repositório é `define_singleton_method` + `singleton_class.remove_method` no `ensure`.
**Problema (dois, ambos só apareceram ao medir):**
1. **Vazamento entre arquivos.** `remove_method` no teardown não "desfaz" o stub — ele remove a definição no singleton e deixa o método cair para a definição da superclasse, **apagando a implementação de classe real**. Rodando os 3 arquivos juntos, o primeiro `ensure` removeu `ImportarGestoresIndividuaisService.call` de verdade e os 26 testes seguintes quebraram com `NoMethodError: undefined method 'call'`. O mesmo defeito é **pré-existente** em `test/controllers/dashboard_controller_test.rb` (o teardown remove `Pessoas::Vinculo.ativos`), e numa ordem de seed específica o `PessoasEspelhoHelperTest` recebe `undefined method 'ativos'` — foi a "13ª falha" que apareceu na suíte completa da 29.3 e que **reproduzi sem nenhum arquivo meu** (`dashboard_controller_test.rb` + `pessoas_espelho_helper_test.rb`, sozinhos). É flaky por ordem, não regressão.
2. **Mutação sobrevivente por prova fraca.** A mutação "trocar `errors.full_messages` por `e.message` no serviço" (que é o Bug 8, *load-bearing* da task) **não matou nenhum teste**: o locale pt-BR já corrigido faz `e.message` conter "inválido", então a asserção `assert_includes motivo, "inválido"` passava nas duas formas. Só ao **mutar e medir** ficou claro que o teste não exercitava a condição real ("usa `full_messages`, não `e.message`"). O discriminante é o **wrapper** que só o `e.message` carrega (`Validation failed:` / `1 erro impediu este registro de ser salvo:`).
**Solução:** (a) trocar o par `define_singleton_method`+`remove_method` por **salvar o método original (`klass.method(:x)`) e restaurá-lo no `ensure`** — o gem Minitest 6 não traz mais `Object#stub`, então o helper foi escrito à mão (`com_stub_de_classe`); zero vazamento. (b) Fortalecer o teste do Bug 8 com `refute_match(/erro impediu este registro|Validation failed/, motivo)`, que **distingue as duas implementações**; com ele a mutação é morta (verificado: baseline verde, mutado vermelho, restaurado verde).
**Lição:** ao stubar método de classe em Minitest, **nunca** use `remove_method` no teardown isolado — salve e restaure o `Method` original. E a regra da sessão vale para o próprio teste: **rode a mutação e veja o teste ficar vermelho** antes de declarar a cobertura; uma asserção que passa tanto na implementação certa quanto na errada não prova nada (aqui, asserir a presença do texto "inválido" passava nas duas — o wrapper do `e.message` é o que discrimina). Um teste que quebra sozinho em certa ordem de seed **não é regressão nova** até ser reproduzido sem os arquivos da mudança.

---

### 2026-09-30 — Consumir um payload externo por *dump* exercita a SUA cópia das chaves, não as chaves REAIS

**Contexto:** Tarefa 29.3 (Sprint 29). A importação lê `SticapiClient::Intranet.gestores_individuais`. Nos testes, o
payload é injetado (`registros:`) com chaves **snake_case** (`data_criacao`, `data_exclusao`), exatamente como a doc da
gem (`sticapi_client/lib/sticapi_client/intranet.rb:42`). O serviço lê `linha[:data_criacao]` / `linha[:data_exclusao]`;
a suíte passa verde.

**Problema:** o **único consumidor conhecido em produção** do mesmo endpoint, o Pessoas2, lê `json["dataCriacao"]` /
`json["dataExclusao"]` — **camelCase** (`pessoas2/app/models/gestao_individual.rb:23`). Dois consumidores reais do mesmo
endpoint divergem no *casing* da chave; pelo menos um está errado. Como o serviço **nunca** viu um payload real (o parse
é stubbed tanto na unidade quanto no repo), o teste mediu o formato que **nós** escolhemos, não o que o servidor envia.
Se a chave real for camelCase, `momento_exclusao` é sempre `nil` ⇒ **todo registro excluído no legado entra ATIVO sem
`data_exclusao`** — a corrupção mais silenciosa possível de um campo de auditoria, com a suíte 100% verde.

**Lições:**
1. **Um dump de entrada só prova o parser contra as chaves que VOCÊ escreveu.** Antes de consumir payload de terceiro
   em produção, a primeira verificação é de **contrato de dados**: capture **uma amostra real** (ou o código do endpoint)
   e confirme os nomes/formatos das chaves. Vale o mesmo raciocínio da lição do monorepo: **validar o conteúdo que você
   controla ≠ validar o artefato/contrato real.**
2. **Dois consumidores do mesmo endpoint são evidência de contrato, e divergência entre eles é um SINAL, não ruído.**
   Antes de assumir um formato, compare com quem já consome a mesma API (aqui, `pessoas2`); a divergência aponta para
   um defeito real de um dos lados.
3. **Normalizar na borda é defesa em profundidade, não preciosismo:** aceitar ambos os casings (`linha[:data_criacao] ||
   linha["dataCriacao"]`) transforma um risco de corrupção silenciosa em robustez por alguns caracteres.

---

### 2026-09-30 — Medir a suíte num git worktree sem os artefatos NÃO versionados produz centenas de "falhas" que não são regressão

**Contexto:** Complemento 29.3-D1..D4 (Sprint 29). A tarefa foi executada num **git worktree** isolado
(`wt-29.3-d1-d4`) — decisão correta, para não colidir com o `Frequencia/` e o `wt-29.3` (um acidente anterior
aconteceu por agentes compartilharem diretório). O worktree tinha o código, mas **não** tinha dois artefatos de
execução: o `vendor/bundle` (dependências) e o `app/assets/builds/application.css` (saída do pipeline de assets).
**Problema:** a primeira medição de `test/models test/controllers/admin` deu `518 runs / 1156 assertions / 110
errors` — contra o baseline conhecido `518/1800/0`. Os 110 errors eram **todos**
`ActionView::Template::Error: The asset 'application.css' was not found in the load path` (o layout `admin` o
referencia). Na suíte completa, o mesmo defeito inflou para **174 errors**. Ambos os artefatos são gitignored
(`api-ponto/log/`+`api-ponto/tmp/` e `app/assets/builds/`), então `git status` ficava **limpo** e nada no worktree
denunciava a ausência — o número parecia uma regressão grave introduzida pelo patch. (O bundle foi resolvido com
`BUNDLE_PATH` apontando ao checkout principal, que tem `vendor/bundle/ruby/3.3.0`; o `application.css` foi copiado
temporariamente do principal e removido após a medição.)
**Lição (duas):**
1. **Um worktree é um checkout limpo: tudo que é gitignored NÃO existe lá.** Antes de rodar a suíte, um worktree
   novo precisa de **estado de execução** além do código — bundle e assets compilados. Se o número divergir do
   baseline, a **primeira** hipótese é artefato ausente, não regressão: classifique as mensagens de erro por
   **assinatura** (`grep | sort | uniq -c`) antes de atribuir a causa ao diff. Aqui `110× a mesma mensagem de
   asset` foi a pista que descartou a regressão em segundos.
2. **Isso é a mesma lição central da sessão numa terceira roupagem:** o baseline "923/12 pré-existentes" só vale
   para o **ambiente em que foi medido**. Reproduzir a medição fora dele mede o ambiente, não o código. A regra
   prática: **reproduza primeiro o baseline conhecido no ambiente novo** (aqui, `518/1800/0`) — se ele não
   reproduz, o ambiente não é comparável.

---

### 2026-09-30 — Uma verificação de contrato que passa "se ALGUMA pista aparecer" não protege o campo de pior risco

**Contexto:** Complemento 29.3-D4 (Sprint 29), achado 🟡1 do Code Reviewer. Para o risco de *casing* das chaves
de data do payload do Intranet, o serviço ganhou um `verificar_contrato!` que abortava se **nenhuma** linha
trouxesse **nenhum** dos casings conhecidos — expresso como
`linhas.any? { |l| l.key?(:data_criacao) || l.key?(:dataCriacao) || l.key?(:data_exclusao) || l.key?(:dataExclusao) }`.

**Problema:** o predicado era um `any?` sobre a **linha inteira** (e outro sobre a **lista**). Bastava que **uma**
das quatro chaves casasse para a linha ser "perdoada". Medido: um payload com `data_criacao` reconhecida **e** a
**exclusão** num terceiro casing (`dataExclusao2`) passava em silêncio e o vínculo entrava **ATIVO sem
`data_exclusao`** — a corrupção que o próprio contrato existia para impedir. O `any?` sobre a lista era o segundo
furo: uma linha 100% reconhecida "protegia" as demais. A suíte (35 testes do serviço) estava 100% verde.

**Lição (duas):**
1. **Um contrato deve ser por CAMPO crítico e por LINHA, nunca por "alguma chave conhecida apareceu".** Se o risco
   é a perda silenciosa do campo X, o predicado tem de falar **de X** — `linha.key?(:x) || linha.key?(:x_camel)`
   para **cada** linha —, não de um OR de campos onde a presença de outro campo "perdoa". O OR de campos é uma
   verificação decorativa: ela *parece* verificar e não verifica a condição que importa.
2. **Distinguir "campo ausente de verdade" de "campo presente num formato desconhecido" — pela CHAVE, não pelo
   valor.** Endurecer sem falso positivo exige separar dois casos que um `key?` simples confunde: ausência
   legítima (nem todo vínculo tem exclusão) e variante de casing (chave `dataExclusao2`/`data_exclusao_legado`).
   A discriminação é reconhecer que a chave **parece** com o campo (mesma palavra distintiva após normalizar
   casing/separadores) sem **ser** o casing conhecido → falha ALTO; se não há nenhuma chave parecida, é ausência
   real → passa. **Prove sempre os dois sentidos** (o caso que deve falhar e o payload válido que deve passar).

---

### 2026-10-01 — `remove_method` num scope Rails destrói o scope de negócio para o PROCESSO inteiro

**Contexto:** Chore `chore/suite-stub-nao-destrutivo` (Sprint 29), achado 🟠1 do Code Reviewer. Um teste
(`dashboard_controller_test.rb`) stubbava `Pessoas::Vinculo.ativos` com
`remove_method(:ativos)` + `define_singleton_method(:ativos) { lista }`, e no `teardown` outro
`remove_method(:ativos)` "para limpar". A suíte exibia, de forma intermitente, `NoMethodError: undefined
method 'ativos' for class Pessoas::Vinculo` em arquivos **sem nenhuma relação** com o dashboard.

**Causa:** no Rails, scopes SÃO definidos como `singleton_class.define_method(name)`
(`activerecord/lib/active_record/scoping/named.rb`). Logo o `remove_method` do `teardown` **não removia um
stub — removia o próprio scope de negócio**, e não o reinstalava. Como o arquivo de teste compartilha a
VM, o scope ficava morto para **todo** arquivo rodado depois dele — falsificando, por *skip*/erro, os
testes de outros (contaminação **order-dependent**; o mesmo arquivo passava sozinho).

**Solução:** par **capturar/restaurar** o `UnboundMethod` real — captura no load
(`singleton_class.instance_method(:ativos) if respond_to?(:ativos)`) e reinstalação no `teardown`
(`singleton_class.send(:define_method, :ativos, real)`, que roda inclusive sob falha). O stub passa a
**redefinir** sem remover. (O `stub` do Minitest **não** é alternativa aqui: no Minitest 6.0.6 do bundle
não existe `minitest/mock` nem `Object#stub` — medido.)

**Lição (três):**
1. **No Rails, mexer no método de um scope é mexer no MODEL, não num mock.** Nunca `remove_method` num
   método definido pelo framework; capture o `UnboundMethod` e reinstale-o. Um stub que "limpa" com
   `remove_method` mata código de produção no processo de teste inteiro.
2. **Contaminação de teste é order-dependent — uma execução verde não prova nada.** O modo honesto de
   provar é: probe determinístico (ex. `Minitest.after_run` inspecionando `respond_to?`/`source_location`
   do método depois de rodar o arquivo **sozinho**) + A/B por seeds no **menor conjunto que discrimina**
   (< limiar de paralelização, para a ordem ser a única variável). A suíte completa paraleliza por arquivo
   e pode **mascarar** a varíola.
3. **`source_location` distingue "stub" de "scope real"** onde `Method#owner` não distingue (o stub também
   é singleton). Use `source_location` para provar que o método restaurado é o do framework, não uma cópia
   do teste.

---

### 2026-10-01 — `def self.` de produção também morre com `remove_method`; só método HERDADO é seguro

**Contexto:** Chore `chore/auditoria-stubs-destrutivos` (Sprint 29). A lição anterior (mesmo dia) dizia
que "os outros `remove_method` são seguros porque stubam métodos PRÓPRIOS, não scopes Rails". **Medido:
estava errado por ordem de magnitude.** Há **8 arquivos** que vazavam métodos de produção.

**Causa:** a fronteira de segurança **não** é "scope vs. não-scope" — é **own method vs. herdado**. No
Ruby, `define_singleton_method(:m)` + `remove_method(:m)` mata qualquer método definido **na própria
classe** (um `scope` Rails OU um `def self.m` de model/service), e só é inócuo para métodos **herdados**
(ex.: `find_by` do ActiveRecord), onde o `remove_method` desfaz o stub e a busca cai de volta no ancestral.
Como o processo de teste é compartilhado (mesmo com `parallelize`, cada worker roda vários arquivos em
sequência), o método morto quebra todo arquivo seguinte — de forma **order-dependent**.

**Medição (determinística, `Minitest.after_run`):** com o padrão real dos testes, some:
`Pessoas::Vinculo.frequentadores_ativos`, `.unidades_por_vinculo`, `.orgaos_em_uso`, `.cpfs_por_orgao`,
`.cpfs_por_nome`, `Pessoas::CategoriaTrabalhador.em_uso` (scope), `Pessoas::GestorhContrachequeMirror
.pares_matricula_cpf_para`; **sobrevivem** `Pessoas::{Pessoa,Unidade}.find_by` (ancestral).
**A/B discriminador (live victim):** sem fix → `NoMethodError`/`MORTO`; com fix → verde.

**Solução:** helper compartilhado `test/support/class_method_stub_helper.rb` (incluído na base) —
`com_metodo_de_classe_stubado(owner, metodo, corpo) { ... }` / a variante múltipla — capturando o
`UnboundMethod` real e restaurando no `ensure`. Para métodos herdados do ORM, mantém-se o
`define_singleton_method`/`remove_method` local (seguro, e não há `UnboundMethod` próprio a capturar).

**Lição (duas, além das três anteriores):**
1. **Own method, não "scope": é essa a fronteira.** `def self.` de produção é tão destrutível quanto um
   scope. Não classifique por intuição ("é só um método próprio") — **meça**
   (`singleton_class.instance_method(m).source_location` + `method_defined?(m, false)`).
2. **Um `ensure` que reinstala um WRAPPER (`{ |*a| original.call(*a) }`) não é restauração.** O método
   volta, mas fica um override permanente apontando para o arquivo de teste (`source_location` no teste).
   Restaure o **`UnboundMethod` original** — aí `source_location` volta a `app/...`. Prove pela origem.

### 2026-10-02 — Um relato de agente propaga como fato: "está em produção" ≠ "está exposto"

**O erro.** A coordenação afirmou que a tarefa 29.5 alteraria "o comportamento de
autorização de um fluxo **já em produção**" e que critério errado "**ampliaria**
autorização". Repassou isso ao CTO, que o transcreveu na §Decisão D5 do
`iteration_29.md` — e a partir daí o erro passou a ter **aparência de registro
documental medido**. Duas rodadas depois, um `grep` de 10 segundos derrubou a
afirmação: **nenhum controller, rota ou view chama `desconsiderar!`**; os únicos
callers estão em testes. Não havia ponto de entrada, logo não havia autorização a
ampliar.

**A forma do erro — não é "não verifiquei", é pior.** Eu *verifiquei* algo: que os
arquivos `time_record.rb`/`intervencao_frequencia.rb`/`registro_manual_...rb`
**existem**. Isso era verdade. Mas "o arquivo existe" não implica "o fluxo está
exposto" — e eu não fiz a pergunta seguinte. **Um fato verdadeiro usado para
sustentar uma conclusão que ele não sustenta** é mais perigoso que uma afirmação
sem base, porque passa por qualquer checagem superficial e vira premissa aceita.

**Por que propagou.** O relato veio de quem coordena (autoridade percebida), foi
para quem tem autoridade de ruling (CTO), e foi escrito na fonte de verdade do
projeto. Cada degrau **aumentou** a confiança sem **adicionar** verificação — o
inverso do que deveria acontecer. Uma afirmação não fica mais verdadeira por ter
sido repetida por alguém mais sênior.

**Regra prática.** Antes de registrar um impacto na **fonte de verdade**:
1. Separe **"o código existe"** de **"o código tem caminho de entrada"** — são
   perguntas diferentes, com evidências diferentes (`grep` em `app/controllers/`,
   `app/views/`, `config/routes.rb`).
2. Quando o impacto é de **segurança/autorização**, prove o **caminho de
   entrada** (rota + controller + guard), não a existência do método.
3. Ao transcrever o impacto de outrem para um documento de ruling, **meça** — não
   herde. O CTO registrou corretamente *o que lhe foi dito*; o defeito estava na
   origem e no repasse sem checagem.

**Custo concreto:** o gate humano levantado ("é risco de autorização em
produção") estava mal justificado e poderia ter barrado a 29.5 por um motivo
inexistente. A pergunta correta é de **priorização** (implementar sem caller
agora, ou quando a 29.7 expuser o fluxo), não de segurança.

### 2026-10-02 — Um `refute` que não pode falhar: o gate que "prova" pela condição errada

**Contexto.** Task 29.5 (Sprint 29). Escrevi um teste para provar que o auto-bloqueio por
**Frequentador** funciona (acionador e alvo são `User` DIFERENTES que resolvem para o mesmo
`FrequentadorCache`, via stub de `find_by`). O teste era `refute pode_desconsiderar?(alvo)` — verde.
Ao mutar o código (trocar a identidade por Frequentador por uma comparação de CPF-string), **a
mutação sobreviveu**: o `refute` continuava verde. O gate não provava nada.

**Causa (a armadilha).** O cenário do teste tinha o acionador **sem** hierarquia sobre o alvo — então
`pode_desconsiderar?` retornava `false` de qualquer jeito, pela cláusula 6 (não é gestor do órgão).
O `refute` passava **pela condição errada**. É a mesma classe de erro que a lição de 2026-10-02 (o
relato "existe ⇒ está exposto"): **um negativo que não pode falhar não prova a cláusula que você
acha que ele prova**.

**Solução.** Todo teste de bloqueio precisa de um **controle positivo ao lado** — o mesmo cenário
com a condição sob teste **neutralizada** deve **liberar**:
```ruby
# CONTROLE: sem o frequentador compartilhado, a hierarquia sozinha LIBERA.
assert elegivel(acionador).pode_desconsiderar?(alvo, DATA)
# SOB TESTE: com o frequentador compartilhado (stub), bloqueia.
com_metodo_de_classe_stubado(FrequentadorCache, :find_by, ->(**_k){ frequentador }) do
  refute elegivel(acionador).pode_desconsiderar?(alvo, DATA)
end
```
Assim, se a cláusula de identidade for removida, o `refute` falha **naquele** cenário (o controle
já provou que a hierarquia sozinha libera) — a mutação morre. Com o controle, as duas mutações
(CPF-string e remoção do nível Frequentador) morreram.

**Lição.**
1. **Um `refute`/`assert_not` só prova a cláusula certa se houver um caminho em que o resultado
   seria `true` sem ela.** Sempre emparelhe o negativo com um controle positivo do **mesmo** cenário.
2. Ao mutar para validar um teste, mutar o ramo **sob teste**, não só um ramo qualquer — e confirmar
   que a mutação morre **pela asserção certa** (a mensagem do controle aparece?).
3. Aplique a pergunta da lição anterior a cada assert: **"esta prova exercita a MESMA condição do
   ambiente real, ou passa por acaso?"** Um teste que passa por outro motivo é indistinguível de um
   teste que passa — até você mutar.

---

### 2026-10-02 — `NOT (predicado)` em SQL com NULL não é o complemento de `predicado`: 3-valued logic

**Contexto.** Débito D2 (pré-29.7), `FrequentadoresVisiveis#ids_unidades_inelegiveis_como_gestor`.
Para "a cadeia tem gestor INELEGÍVEL E NÃO tem gestor ELEGÍVEL" (a negação que o PORO loga como
`unidade_inelegivel`), escrevi `WHERE A AND NOT B`, com `B = (self_elegível) OR (path_valido AND
EXISTS(ancestral elegível))`.

**Problema.** A query devolvia **vazio** no cenário exato que devia casar. Debug: `A` = `true`, `B` =
`nil` (NULL), e **`NOT NULL` = NULL** → a linha era **excluída** pelo `AND`. Causa medida: `B`
continha `gestor_match` = `a.gestor_id IN (...) OR a.gestor_substituto_id IN (...) OR
a.gestor_excepcional_id IN (...)`. Numa unidade em que o usuário **não** é gestor, os três `IN`
retornam `false`, `NULL`, `NULL` (comparar coluna NULL com uma lista devolve NULL, não false) — e
`false OR NULL OR NULL` = **NULL**. Logo `B` não era `false`: era `NULL`, e `NOT NULL` = `NULL`. O
ponto geral: **um predicado SQL que pode ser NULL não tem complemento por `NOT`** — `NOT NULL` é
`NULL`, nunca `true`, e uma linha com `WHERE ... NULL` é descartada.

**Solução.** `AND NOT COALESCE(B, FALSE)` — fixa o "não-elegível" quando o predicado é NULL. Provado
por mutação: sem o `COALESCE`, o teste do evento agregado falha; com ele, passa. E o fix não podia ser
um `COALESCE` genérico que virasse `true`: `COALESCE(B, TRUE)` teria invertido o sentido e liberado a
unidade errada.

**Lição.**
1. Em SQL, **`NOT (p)` só é o complemento de `p` se `p` for 2-valued**. Predicado que pode ser NULL
   (`coluna IN (lista)` com coluna nulável, comparações com NULL, `OR` de predicados NULL) precisa de
   `COALESCE` explícito — e a escolha do default (`FALSE` vs `TRUE`) é uma decisão de segurança, não
   de estilo: `FALSE` no `NOT` = "na dúvida, o lado positivo é falso" (fail-closed do lado do bloqueio).
2. O sintoma não aparece na leitura do código, só no resultado: um `WHERE ... AND NOT ...` que
   **nunca casa** é indistinguível de "não há caso" até você rodar o SQL do cenário real. Ao portar um
   `if` do Ruby (2-valued) para SQL, **teste o cenário que DEVE casar** — não só o que deve negar.

---

### 2026-10-02 — Um `Proc` passado a `define_singleton_method` REBINDA o `self`: variável de instância do teste vira `nil` dentro do stub

**Contexto.** Task 29.7 (Sprint 29). Num teste de controller usei
`com_metodo_de_classe_stubado(Pessoas::Vinculo, :cpfs_frequentadores_visiveis, ->(_u) { [ @oculto.cpf ] })`.
O stub levantou `NoMethodError: undefined method 'cpf' for nil` — como se `@oculto` não existisse.

**Causa (medida).** `define_singleton_method(:m, corpo)` **redefine `self`** para o receiver (aqui, a
própria `Pessoas::Vinculo`) quando o `corpo` é um `Proc`/lambda. Dentro do lambda, uma variável de
INSTÂNCIA (`@oculto`) resolve contra ESSE `self` (a classe), não contra a instância do teste — donde
`nil`. Variáveis LOCAIS são capturadas pelo closure e **não** dependem do `self`; portanto funcionam.

**Solução.** No bloco do stub, capture o valor em uma **variável local** antes de montar o lambda:
```ruby
cpf_oculto = @oculto.cpf
com_metodo_de_classe_stubado(Pessoas::Vinculo, :cpfs_frequentadores_visiveis, ->(_u) { [ cpf_oculto ] }) do
```
(Mesma família do cuidado com `self`/implicit-receiver já registrada na causa-raiz dos 11 Devise
`redirect_to` — lá, dentro de `super do` o receiver deixava de ser o controller.)

**Lição.** Ao stubar com um `Proc`, trate o corpo como um **método da classe**: `self` é a classe-alvo,
não o teste. Não use `@instance_vars` do teste dentro dele — capture em locais. Se um stub de classe
"não enxerga" um dado do teste (`nil` inesperado), a causa provável é o rebind de `self`, não o dado.

---

### 2026-10-02 — Um teste de integração exercita a CAMADA de produção, não a camada que você mutou

**Contexto.** Task 29.8 (Sprint 29), matriz de aceite. A matriz é um teste de controller que exercita a
cascata ponta a ponta. Ao mutar o PORO `AutorizacaoFrequencia` (passo 4 — gestor individual — ignorar
`.ativos`, de modo que um vínculo INATIVO passasse a liberar), **a matriz continuou verde**. Pela lição
de 2026-10-02, um sobrevivente à mutação significa "teste degenerado" — mas aqui era o contrário: o teste
estava certo, o **alvo da mutação** estava errado.

**Causa (medida).** A CASCATA existe em DUAS implementações equivalentes: o PORO `AutorizacaoFrequencia`
(`pode_ver?` por alvo, 29.4) e o scope SQL `FrequentadoresVisiveis` (a LISTA, 29.6). A **listagem** dos
controllers (`restringir_frequencia`) filtra pelo **scope SQL** — o PORO, ali, só fornece o `motivo` do
log de auditoria. Logo mutar o PORO não muda o que a listagem mostra e a matriz (que assere a listagem)
não pode matá-la. Mutar o **scope** (`FrequentadoresVisiveis#geridos_user_ids` ignorando `.ativos`) matou
a matriz imediatamente (1 failure).

**Lição.**
1. Antes de declarar uma mutação "sobrevivente ⇒ teste fraco", confirme **por qual implementação passa o
   caminho do teste**. Quando a mesma regra tem gêmeos (Ruby × SQL), cada teste cobre UM gêmeo.
2. Rastreie o fluxo (`controller → método chamado → query`) **antes** de escolher o alvo da mutação. Mutar
   a camada errada produz um falso "teste degenerado" e desperdiça a rodada.
3. Corolário do projeto: a matriz de aceite (integração/listagem) prova o **scope SQL**; a suíte da 29.4
   prova o **PORO**. Um verde na matriz **não** é evidência sobre o PORO — e vice-versa.

---

### 2026-10-05 — Brakeman SQL: `Arel.sql` NÃO silencia; `sanitize_sql_array` SIM (Weak→Medium pela interpolação)

**Contexto.** Chore `chore/bump-rails-8.1` (Sprint 29). O bump do Rails para 8.1.4 removeu o
`EOLRails` Medium, mas restava um `SQL Injection` Medium em `frequentadores_visiveis.rb`
(interpolação `#{ESTADO_ATIVO}` numa query de `select_values`). O plano do CTO sugeria
`sanitize_sql_array` **ou** `Arel.sql` consciente.

**Problema (medido no fonte do Brakeman 8.0.5).** São caminhos DIFERENTES no `check_sql.rb`:
- `Arel.sql(...)` é avaliado por `safe_value?` → `ignore_call?` → `arel?`, que exige um método na
  allowlist `AREL_METHODS` (`:where`,`:all`,`:eq`,`:in`…) e/ou um target que já seja Arel
  (`arel_table`) — `Arel.sql` **puro não está** na lista nem tem target Arel, então **não** é
  considerado seguro. Usar `Arel.sql` consciente **manteria o warning** (e o exit 3).
- `sanitize_sql_array([sql, valor])` está em `IGNORE_METHODS_IN_SQL`: o `find_dangerous_value` no
  nó da chamada retorna cedo, a string montada nunca é percorrida e o warning **some na raiz**
  (sem `-x`, sem ledger).

**Solução.** `ve.nome = '#{ESTADO_ATIVO}'` (2 pontos) → bind `?`, aplicado por
`Pessoas::Unidade.sanitize_sql_array([ sql, ESTADO_ATIVO, ESTADO_ATIVO ])`. Os `#{}` restantes
(aliases/ids/fragmentos) são SQL estrutural interno, não parametrizável — documentados no código.
Resultado: `bin/brakeman` = EXIT 0, `security_warnings=0`, ledger intocado.

**Lição.** A expressão "troque por `AreL.sql`/`sanitize_sql_array`" não é intercambiável: **só o
segundo zera o check** no Brakeman. Antes de escolher a "forma que o scanner aceita", leia
`find_dangerous_value`/`safe_value?` da versão instalada — as allowlists (`IGNORE_METHODS_IN_SQL`
vs `AREL_METHODS`) decidem o resultado. Prova por execução do gate (`bin/brakeman` = 0), não por
intenção.
