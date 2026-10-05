require "test_helper"

# Tarefa 29.2 — valida que a migration AddLegacyFieldsToGestoresIndividuais
# é ADITIVA (nenhuma coluna anterior removida), que as colunas novas existem
# com o tipo/default corretos e que os índices UNIQUE de `id_legado` são a
# chave de upsert idempotente exigida pela importação da 29.3.
#
# Não usa `fixtures :all` para não acoplar esta verificação de schema ao
# conteúdo das fixtures: só consulta colunas/índices do banco.
class AddLegacyFieldsToGestoresIndividuaisMigrationTest < ActiveSupport::TestCase
  # Colunas que já existiam antes da migration e NÃO podem ter sido removidas.
  EXISTING_GESTORES_COLUMNS = %w[id nome orgao created_at updated_at].freeze
  EXISTING_GERENCIADOS_COLUMNS = %w[
    id gestor_individual_id user_id created_at updated_at
  ].freeze

  COLUNAS_NOVAS_GESTORES = {
    "id_legado" => :integer,
    "gestor_cpf" => :string,
    "observacao" => :text,
    "ativo" => :boolean,
    "data_exclusao" => :datetime,
    "data_criacao_legado" => :datetime,
    "gestor_user_id" => :integer
  }.freeze

  COLUNAS_NOVAS_GERENCIADOS = {
    "id_legado" => :integer,
    "ativo" => :boolean,
    "data_exclusao" => :datetime
  }.freeze

  def columns(table)
    ActiveRecord::Base.connection.columns(table)
  end

  def column_names(table)
    columns(table).map(&:name)
  end

  # --- Aditividade: nada foi removido ------------------------------------

  test "colunas originais de gestores_individuais são preservadas" do
    nomes = column_names("gestores_individuais")
    EXISTING_GESTORES_COLUMNS.each do |coluna|
      assert_includes nomes, coluna, "coluna removida pela migration: #{coluna}"
    end
  end

  test "colunas originais de gestor_individual_gerenciados são preservadas" do
    nomes = column_names("gestor_individual_gerenciados")
    EXISTING_GERENCIADOS_COLUMNS.each do |coluna|
      assert_includes nomes, coluna, "coluna removida pela migration: #{coluna}"
    end
  end

  # --- Colunas novas: existência, tipo e nulidade ------------------------

  test "colunas novas de gestores_individuais existem com o tipo correto" do
    por_nome = columns("gestores_individuais").index_by(&:name)
    COLUNAS_NOVAS_GESTORES.each do |coluna, tipo|
      definicao = por_nome[coluna]
      assert definicao, "coluna ausente: #{coluna}"
      assert_equal tipo, definicao.type, "tipo incorreto em #{coluna}"
    end
  end

  test "colunas novas de gestor_individual_gerenciados existem com o tipo correto" do
    por_nome = columns("gestor_individual_gerenciados").index_by(&:name)
    COLUNAS_NOVAS_GERENCIADOS.each do |coluna, tipo|
      definicao = por_nome[coluna]
      assert definicao, "coluna ausente: #{coluna}"
      assert_equal tipo, definicao.type, "tipo incorreto em #{coluna}"
    end
  end

  test "ativo tem default true e não aceita nulo nas duas tabelas" do
    %w[gestores_individuais gestor_individual_gerenciados].each do |tabela|
      ativo = columns(tabela).find { |c| c.name == "ativo" }
      # O adapter devolve o default de boolean como string ("true"); cast para
      # comparar com o valor lógico real.
      assert_equal true, ActiveRecord::Type::Boolean.new.cast(ativo.default),
                   "default de ativo em #{tabela}"
      assert_equal false, ativo.null, "ativo em #{tabela} deve ser NOT NULL"
    end
  end

  test "id_legado e data_exclusao aceitam nulo (registro local não tem legado)" do
    por_nome = columns("gestores_individuais").index_by(&:name)
    assert por_nome["id_legado"].null, "id_legado deve aceitar nulo"
    assert por_nome["data_exclusao"].null, "data_exclusao deve aceitar nulo"

    por_nome_gerenciados = columns("gestor_individual_gerenciados").index_by(&:name)
    assert por_nome_gerenciados["id_legado"].null, "id_legado do vínculo deve aceitar nulo"
    assert por_nome_gerenciados["data_exclusao"].null, "data_exclusao do vínculo deve aceitar nulo"
  end

  # --- Índices UNIQUE: chave de upsert da 29.3 ---------------------------

  test "id_legado tem índice UNIQUE em gestores_individuais" do
    indice = ActiveRecord::Base.connection.indexes("gestores_individuais")
                   .find { |i| i.columns == [ "id_legado" ] }
    assert indice, "índice de id_legado ausente"
    assert indice.unique, "o índice de id_legado deve ser UNIQUE (upsert da 29.3)"
  end

  test "id_legado tem índice UNIQUE em gestor_individual_gerenciados" do
    indice = ActiveRecord::Base.connection.indexes("gestor_individual_gerenciados")
                   .find { |i| i.columns == [ "id_legado" ] }
    assert indice, "índice de id_legado do vínculo ausente"
    assert indice.unique, "o índice de id_legado do vínculo deve ser UNIQUE"
  end

  # --- FK opcional do login do gestor ------------------------------------

  test "gestor_user_id referencia users e é opcional" do
    fk = ActiveRecord::Base.connection.foreign_keys("gestores_individuais")
                   .find { |f| f.column == "gestor_user_id" }
    assert fk, "FK de gestor_user_id ausente"
    assert_equal "users", fk.to_table

    definicao = columns("gestores_individuais").find { |c| c.name == "gestor_user_id" }
    assert definicao.null, "gestor_user_id deve ser opcional (gestor sem login local)"
  end

  # --- Volumes e preservação de dados ------------------------------------

  test "a tabela continua utilizável e registros locais sobrevivem (id_legado nulo)" do
    gestor = GestorIndividual.create!(nome: "Gestor Local 29.2", orgao: "Vara Cível")

    assert gestor.persisted?
    assert_nil gestor.id_legado, "registro local não deve ganhar id_legado"
    assert gestor.ativo, "registro local deve nascer ativo"
    assert_nil gestor.data_exclusao
    assert_nil gestor.gestor_user_id, "gestor sem login local continua válido"
  end

  test "id_legado duplicado é rejeitado pelo banco (upsert idempotente)" do
    GestorIndividual.create!(nome: "Importado A", id_legado: 9001)
    agora = Time.current

    # `insert_all!` pula validações do model de propósito: a intenção aqui é
    # provar que a CONSTRAINT do banco (não só a validação Ruby) barra o
    # duplicado — é dela que a importação da 29.3 depende. O savepoint
    # (`requires_new: true`) evita que a violação aborte a transação do teste.
    assert_raises(ActiveRecord::RecordNotUnique) do
      ActiveRecord::Base.transaction(requires_new: true) do
        GestorIndividual.insert_all!([
          { nome: "Importado A duplicado", id_legado: 9001, ativo: true,
            created_at: agora, updated_at: agora }
        ])
      end
    end
  end

  test "vários registros locais com id_legado nulo convivem (UNIQUE admite NULL)" do
    GestorIndividual.create!(nome: "Local 1")
    GestorIndividual.create!(nome: "Local 2")

    assert_equal 2, GestorIndividual.where(id_legado: nil, nome: [ "Local 1", "Local 2" ]).count
  end

  test "vínculo duplicado de id_legado é rejeitado e nulo convive" do
    gestor = GestorIndividual.create!(nome: "Gestor Vínculos")
    gerido = User.create!(nome_completo: "Gerido Vínculos", password: "123456")

    GestorIndividualGerenciado.create!(gestor_individual: gestor, user: gerido, id_legado: 7001)
    agora = Time.current

    assert_raises(ActiveRecord::RecordNotUnique) do
      ActiveRecord::Base.transaction(requires_new: true) do
        GestorIndividualGerenciado.insert_all!([
          { gestor_individual_id: gestor.id, user_id: gerido.id, id_legado: 7001,
            ativo: true, created_at: agora, updated_at: agora }
        ])
      end
    end

    outro = User.create!(nome_completo: "Gerido Local", password: "123456")
    vinculo_local = GestorIndividualGerenciado.create!(gestor_individual: gestor, user: outro)
    assert_nil vinculo_local.id_legado
    assert vinculo_local.ativo
  end
end
