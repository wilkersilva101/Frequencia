require "test_helper"

class FrequentadorCacheTest < ActiveSupport::TestCase
  test "valid with cpf" do
    cache = FrequentadorCache.new(cpf: "11122233344", nome: "Fulano de Tal")
    assert cache.valid?
  end

  test "invalid without cpf" do
    cache = FrequentadorCache.new(nome: "Sem Cpf")
    assert_not cache.valid?
    assert_includes cache.errors[:cpf], "não pode ficar em branco"
  end

  test "invalid with cpf in wrong format" do
    cache = FrequentadorCache.new(cpf: "123", nome: "Cpf Invalido")
    assert_not cache.valid?
    assert_includes cache.errors[:cpf], "é inválido"
  end

  test "invalid with duplicated cpf" do
    FrequentadorCache.create!(cpf: "11122233344", nome: "Primeiro")
    duplicado = FrequentadorCache.new(cpf: "11122233344", nome: "Segundo")

    assert_not duplicado.valid?
    assert_includes duplicado.errors[:cpf], "já está em uso"
  end

  test "find_by_user retorna o cache pelo cpf do usuario" do
    cache = FrequentadorCache.create!(cpf: "11122233344", nome: "Fulano de Tal")
    user = User.create!(nome_completo: "Fulano de Tal", password: "123456", cpf: "11122233344")

    assert_equal cache, FrequentadorCache.find_by_user(user)
  end

  test "find_by_user retorna nil quando nao ha cache correspondente" do
    user = User.create!(nome_completo: "Sem Cache", password: "123456", cpf: "99988877766")

    assert_nil FrequentadorCache.find_by_user(user)
  end

  test "associacao user aponta para o User com o mesmo cpf" do
    user = User.create!(nome_completo: "Fulano de Tal", password: "123456", cpf: "11122233344")
    cache = FrequentadorCache.create!(cpf: "11122233344", nome: "Fulano de Tal")

    assert_equal user, cache.reload.user
  end

  test "associacao user fica nil quando nenhum User tem esse cpf" do
    cache = FrequentadorCache.create!(cpf: "11122233344", nome: "Fulano de Tal")

    assert_nil cache.user
  end
end
