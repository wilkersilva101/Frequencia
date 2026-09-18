require "test_helper"

class GestorIndividualTest < ActiveSupport::TestCase
  test "valid with nome" do
    gestor = GestorIndividual.new(nome: "Fulano Gestor", orgao: "Vara Cível")
    assert gestor.valid?
  end

  test "invalid without nome" do
    gestor = GestorIndividual.new(orgao: "Vara Cível")
    assert_not gestor.valid?
    assert_includes gestor.errors[:nome], "não pode ficar em branco"
  end

  test "has many gerenciados through gestor_individual_gerenciados" do
    gestor = GestorIndividual.create!(nome: "Fulano Gestor")
    frequentador = User.create!(nome_completo: "Frequentador", password: "123456")
    GestorIndividualGerenciado.create!(gestor_individual: gestor, user: frequentador)

    assert_includes gestor.gerenciados, frequentador
  end

  test "gerenciados vazio por padrao" do
    gestor = GestorIndividual.create!(nome: "Fulano Gestor")
    assert_empty gestor.gerenciados
  end

  test "usa a tabela gestores_individuais" do
    assert_equal "gestores_individuais", GestorIndividual.table_name
  end
end
