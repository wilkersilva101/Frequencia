require "test_helper"

# Roda contra o schema real do espelho (ADR-0006): `bin/rails test:pessoas_schema:load`.
# Casos de `ancestry` malformado usam `Pessoas::Unidade.new` sem persistir
# (lógica pura, sem consulta), o que a ADR-0006 permite.
class PessoasUnidadeTest < ActiveSupport::TestCase
  include PessoasEspelhoHelper

  # Débito B1: em CI/máquina limpos sem o schema do espelho, PULA em vez de
  # explodir com PG::UndefinedTable (ver `skip_sem_espelho!`).
  setup { skip_sem_espelho! }

  test "exposes the three optional gestor associations with explicit keys" do
    {
      gestor: "gestor_id",
      gestor_substituto: "gestor_substituto_id",
      gestor_excepcional: "gestor_excepcional_id"
    }.each do |association, foreign_key|
      reflection = Pessoas::Unidade.reflect_on_association(association)

      assert_equal "Pessoas::Pessoa", reflection.class_name
      assert_equal foreign_key, reflection.foreign_key
      assert_equal "id", reflection.active_record_primary_key
      assert reflection.options[:optional]
    end
  end

  test "remains readonly" do
    unidade = criar_unidade

    assert unidade.readonly?
    assert_raises(ActiveRecord::ReadOnlyRecord) { unidade.update!(descricao: "Alterada") }
  end

  test "loads each gestor association from its own column" do
    gestor = criar_pessoa
    substituto = criar_pessoa
    excepcional = criar_pessoa
    unidade = criar_unidade(gestor_id: gestor.id, gestor_substituto_id: substituto.id,
                            gestor_excepcional_id: excepcional.id)

    assert_equal gestor, unidade.gestor
    assert_equal substituto, unidade.gestor_substituto
    assert_equal excepcional, unidade.gestor_excepcional
  end

  test "identifies a person as one of the three unit gestores" do
    pessoa = criar_pessoa

    assert criar_unidade(gestor_id: pessoa.id).gestor?(pessoa)
    assert criar_unidade(gestor_substituto_id: pessoa.id).gestor?(pessoa)
    assert criar_unidade(gestor_excepcional_id: pessoa.id).gestor?(pessoa)
    assert_not criar_unidade.gestor?(pessoa)
  end

  test "does not identify nil as a unit gestor" do
    assert_not criar_unidade.gestor?(nil)
  end

  test "does not identify a different person as a unit gestor" do
    gestor = criar_pessoa
    outra_pessoa = criar_pessoa
    unidade = criar_unidade(gestor_id: gestor.id, gestor_substituto_id: gestor.id,
                            gestor_excepcional_id: gestor.id)

    assert_not unidade.gestor?(outra_pessoa)
  end

  test "identifies distinct instances with the same id as the same person" do
    gestor = criar_pessoa
    mesma_pessoa = Pessoas::Pessoa.find(gestor.id)
    unidade = criar_unidade(gestor_id: gestor.id)

    refute_same unidade.gestor, mesma_pessoa
    assert unidade.gestor?(mesma_pessoa)
  end

  test "returns the leaf, parent and root units in ascending order with one query" do
    arvore = criar_arvore_unidades
    folha = arvore[:folha]

    assert_equal "#{arvore[:raiz].id}/#{arvore[:intermediaria].id}", folha.ancestry

    cadeia = assert_queries_count(1) { folha.cadeia_ascendente }

    assert_equal [ folha, arvore[:intermediaria], arvore[:raiz] ], cadeia
  end

  test "returns only the unit when ancestry is empty and does not query" do
    unidade = criar_unidade

    assert_no_queries do
      assert_equal [ unidade ], unidade.cadeia_ascendente
    end
  end

  test "fails closed without querying when ancestry references the unit itself" do
    unidade = Pessoas::Unidade.new(id: 3, ancestry: "1/3")

    assert_no_queries do
      assert_equal [ unidade ], unidade.cadeia_ascendente
    end
  end

  test "fails closed without querying when ancestry is corrupted" do
    [ "invalido", "1/invalido", "1//2", "/1", "1/" ].each do |ancestry|
      unidade = Pessoas::Unidade.new(id: 3, ancestry: ancestry)

      assert_no_queries do
        assert_equal [ unidade ], unidade.cadeia_ascendente, "ancestry #{ancestry.inspect}"
      end
    end
  end

  test "keeps existing ancestors when one path id is missing" do
    raiz = criar_unidade(descricao: "Raiz")
    id_inexistente = raiz.id + 1_000_000
    folha = criar_unidade(descricao: "Folha", ancestry: "#{raiz.id}/#{id_inexistente}")

    assert_equal [ folha, raiz ], folha.cadeia_ascendente
  end

  # --- Bug 1 do Bug Finder da 29.1 ------------------------------------------
  #
  # A checagem de auto-referência comparava strings ("05" != "5"), então um id
  # com zero à esquerda (dado corrompido por edição manual) escapava e a própria
  # unidade reaparecia na cadeia. Corrigido comparando DEPOIS do `to_i`.
  test "fails closed without querying on self-reference with a leading zero" do
    unidade = Pessoas::Unidade.new(id: 5, ancestry: "1/05")

    assert_no_queries do
      assert_equal [ unidade ], unidade.cadeia_ascendente
    end
  end

  # --- Bug 2 do Bug Finder da 29.1 ------------------------------------------
  #
  # Ids repetidos no path não existem na gem `ancestry` — é corrupção. Antes
  # devolvia o ancestral duplicado; agora é fail-closed sem consulta.
  test "fails closed without querying when the path repeats an id" do
    unidade = Pessoas::Unidade.new(id: 5, ancestry: "1/1")

    assert_no_queries do
      assert_equal [ unidade ], unidade.cadeia_ascendente
    end
  end

  # Controle negativo dos Bugs 1/2: um path LEGÍTIMO com ids distintos não pode
  # ser confundido com corrupção — prova nos dois sentidos.
  test "does not fail closed for a legitimate path with distinct ids" do
    raiz = criar_unidade(descricao: "Raiz")
    meio = criar_unidade(descricao: "Meio", parent: raiz)
    folha = criar_unidade(descricao: "Folha", parent: meio)

    assert_equal [ folha, meio, raiz ], folha.cadeia_ascendente
  end

  # --- Regra D6: elegibilidade da unidade (inativa/extinta não libera) ------

  test "is eligible when active and not extinguished" do
    assert criar_unidade(active: true).elegivel?
  end

  test "is not eligible when active is false" do
    assert_not criar_unidade(active: false).elegivel?
  end

  test "is not eligible when active is nil" do
    assert_not criar_unidade(active: nil).elegivel?
  end

  test "is not eligible when the serventia was extinguished today or earlier" do
    assert_not criar_unidade(active: true, data_extincao_serventia: Date.current).elegivel?
    assert_not criar_unidade(active: true, data_extincao_serventia: Date.current - 1).elegivel?
  end

  test "is eligible when the extinction date is in the future" do
    assert criar_unidade(active: true, data_extincao_serventia: Date.current + 1).elegivel?
  end
end
