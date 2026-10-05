class AddLegacyFieldsToGestoresIndividuais < ActiveRecord::Migration[8.0]
  # Tarefa 29.2 — prepara `gestores_individuais` para receber o dado real do
  # Intranet (PRD §2.5). A Intranet será descomissionada; a fonte de verdade
  # do vínculo de gestão individual passa a ser o Frequencia, alimentado pela
  # importação idempotente da Tarefa 29.3.
  #
  # Migration ADITIVA (sem drop/rename): os registros locais já cadastrados
  # pela tela `admin/gestores_individuais` (Fase A, "popular o front")
  # continuam válidos e aparecendo — apenas ficam com `id_legado` nulo, que é
  # o que distingue importado-de-Intranet de cadastro local.
  #
  # `atualizado_em_legado` não existe: o retorno de
  # `SticapiClient::Intranet.gestores_individuais` só traz
  # `id, data_criacao, data_exclusao, observacao, id_vinculo_gestor,
  # matricula_gestor, id_vinculo_gerido, matricula_gerido` (ver comentário do
  # model `GestorIndividual`), sem timestamp de atualização.
  #
  # ⚠️ FORWARD-ONLY a partir da importação (Bug 1 do Bug Finder da 29.2, 🟠):
  # o `change` é reversível no *schema*, mas NÃO nos dados — o `remove_column`
  # do rollback apaga `id_legado`, `gestor_cpf`, `gestor_user_id`,
  # `data_criacao_legado`, `ativo` e `data_exclusao` de TODAS as linhas, e o
  # re-migrate recria as colunas vazias (re-marcando `ativo=true`). Como o
  # Intranet (fonte original) será descomissionado, um rollback acidental
  # descarta o único registro do vínculo legado — irrecuperável. **Antes de
  # qualquer `db:rollback` desta migration sobre dados reais, exigir snapshot
  # da tabela** (`pg_dump -t gestores_individuais -t gestor_individual_gerenciados`).
  def change
    # --- gestores_individuais ---------------------------------------------
    # `unique: true` em `id_legado` é a chave de upsert da 29.3 ("segunda
    # execução = 0 criações") e a rastreabilidade pós-desligamento do legado.
    # No Postgres, índice UNIQUE admite múltiplos NULL, então os registros
    # locais (id_legado nulo) convivem normalmente.
    add_column :gestores_individuais, :id_legado, :bigint
    add_column :gestores_individuais, :gestor_cpf, :string
    add_column :gestores_individuais, :observacao, :text
    add_column :gestores_individuais, :ativo, :boolean, null: false, default: true
    add_column :gestores_individuais, :data_exclusao, :datetime
    # `data_criacao_legado` é datetime (e não date) porque `data_criacao` do
    # legado é um timestamp; guardar só a data perderia informação e
    # dificultaria a conferência com o backup do Intranet.
    add_column :gestores_individuais, :data_criacao_legado, :datetime

    add_index :gestores_individuais, :id_legado, unique: true

    # FK opcional: o gestor individual pode não ter login local (o legado o
    # identifica por vínculo em Pessoas), então a coluna anula sem prejuízo.
    # `to_table` explícito para a FK — a tramitação da migration geradora já
    # documenta que o plural real da tabela não é o inferido pelo Rails.
    add_reference :gestores_individuais, :gestor_user,
                  foreign_key: { to_table: :users }, null: true

    # --- gestor_individual_gerenciados (vínculos gestor → gerido) ---------
    # Mesma lógica de `id_legado`: cada vínculo importado precisa de chave
    # estável, senão a reimportação duplica o vínculo — o que inflaria a
    # contagem "Gerenciados" da tela e faria a cascata da 29.4/29.6 listar o
    # mesmo gerido mais de uma vez. Desvio consciente do critério (que só
    # marcava "unique" para gestores_individuais); registrado na entrega.
    add_column :gestor_individual_gerenciados, :id_legado, :bigint
    add_column :gestor_individual_gerenciados, :ativo, :boolean, null: false, default: true
    add_column :gestor_individual_gerenciados, :data_exclusao, :datetime

    add_index :gestor_individual_gerenciados, :id_legado, unique: true
  end
end
