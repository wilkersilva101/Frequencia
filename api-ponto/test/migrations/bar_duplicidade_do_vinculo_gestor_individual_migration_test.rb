require "test_helper"

# Bug 3 (🟡) do Bug Finder da 29.2 — o índice UNIQUE parcial
# `index_gestor_individual_gerenciados_on_par_ativo` deve impedir mais de um
# vínculo ATIVO por par gestor→gerido no banco (não só na validação Ruby), e
# ainda permitir histórico de linhas inativas do mesmo par.
class BarDuplicidadeDoVinculoGestorIndividualMigrationTest < ActiveSupport::TestCase
  def indice
    ActiveRecord::Base.connection.indexes("gestor_individual_gerenciados")
                   .find { |i| i.name == "index_gestor_individual_gerenciados_on_par_ativo" }
  end

  test "o índice de par ativo existe, é UNIQUE e cobre o par gestor+gerido" do
    assert indice, "índice de par ativo ausente"
    assert indice.unique, "o índice de par ativo deve ser UNIQUE"
    assert_equal [ "gestor_individual_id", "user_id" ], indice.columns
  end

  test "o índice é PARCIAL (where ativo) — permite histórico de inativos do mesmo par" do
    assert_equal "ativo", indice.where,
                 "o índice deve ser parcial em `ativo` para não bloquear re-vínculo"
  end

  test "o banco barra dois vínculos ATIVOS do mesmo par (insert_all! sem validação)" do
    gestor = GestorIndividual.create!(nome: "Gestor Par")
    gerido = User.create!(nome_completo: "Gerido Par", password: "123456")

    GestorIndividualGerenciado.create!(gestor_individual: gestor, user: gerido)
    agora = Time.current

    assert_raises(ActiveRecord::RecordNotUnique) do
      ActiveRecord::Base.transaction(requires_new: true) do
        GestorIndividualGerenciado.insert_all!([
          { gestor_individual_id: gestor.id, user_id: gerido.id, ativo: true,
            created_at: agora, updated_at: agora }
        ])
      end
    end
  end

  test "vínculo INATIVO do mesmo par convive com o ativo (histórico preservado)" do
    gestor = GestorIndividual.create!(nome: "Gestor Histórico")
    gerido = User.create!(nome_completo: "Gerido Histórico", password: "123456")

    antigo = GestorIndividualGerenciado.create!(gestor_individual: gestor, user: gerido)
    antigo.desativar!

    novo = GestorIndividualGerenciado.create!(gestor_individual: gestor, user: gerido)

    assert novo.persisted?, "re-vincular o mesmo par deve ser possível após desativar"
    assert_equal 2, GestorIndividualGerenciado.where(gestor_individual: gestor, user: gerido).count
    assert_equal 1, GestorIndividualGerenciado.where(
      gestor_individual: gestor, user: gerido, ativo: true
    ).count
  end

  test "vínculos de pares diferentes convivem" do
    gestor = GestorIndividual.create!(nome: "Gestor Multi")
    gerido_a = User.create!(nome_completo: "Gerido Multi A", password: "123456")
    gerido_b = User.create!(nome_completo: "Gerido Multi B", password: "123456")

    GestorIndividualGerenciado.create!(gestor_individual: gestor, user: gerido_a)
    GestorIndividualGerenciado.create!(gestor_individual: gestor, user: gerido_b)

    assert_equal 2, GestorIndividualGerenciado.where(gestor_individual: gestor).count
  end

  # O rollback da migration (remove_index + reaplicação) é verificado fora da
  # suíte, com `bin/rails db:rollback STEP=1` / `db:migrate` reais — um teste
  # que muta DDL dentro da transação do caso seria revertido ao fim e poderia
  # interferir nos workers paralelos que compartilham o banco de teste.
end
