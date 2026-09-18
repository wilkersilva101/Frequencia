require "test_helper"

class AfastamentoCacheTest < ActiveSupport::TestCase
  test "valid with afastamento_id_pessoas e cpf" do
    afastamento = AfastamentoCache.new(afastamento_id_pessoas: 1, cpf: "11122233344", tipo: "Férias")
    assert afastamento.valid?
  end

  test "invalid sem afastamento_id_pessoas" do
    afastamento = AfastamentoCache.new(cpf: "11122233344")
    assert_not afastamento.valid?
    assert_includes afastamento.errors[:afastamento_id_pessoas], "não pode ficar em branco"
  end

  test "invalid sem cpf" do
    afastamento = AfastamentoCache.new(afastamento_id_pessoas: 1)
    assert_not afastamento.valid?
    assert_includes afastamento.errors[:cpf], "não pode ficar em branco"
  end

  test "invalid com afastamento_id_pessoas duplicado" do
    AfastamentoCache.create!(afastamento_id_pessoas: 1, cpf: "11122233344")
    duplicado = AfastamentoCache.new(afastamento_id_pessoas: 1, cpf: "55566677788")

    assert_not duplicado.valid?
    assert_includes duplicado.errors[:afastamento_id_pessoas], "já está em uso"
  end

  test "belongs_to frequentador_cache via cpf" do
    cache = FrequentadorCache.create!(cpf: "11122233344", nome: "Fulano de Tal")
    afastamento = AfastamentoCache.create!(afastamento_id_pessoas: 1, cpf: "11122233344")

    assert_equal cache, afastamento.frequentador_cache
  end

  test "frequentador_cache fica nil quando nao ha cache correspondente" do
    afastamento = AfastamentoCache.create!(afastamento_id_pessoas: 1, cpf: "99988877766")
    assert_nil afastamento.frequentador_cache
  end

  test "FrequentadorCache tem many afastamento_caches" do
    cache = FrequentadorCache.create!(cpf: "11122233344", nome: "Fulano de Tal")
    afastamento1 = AfastamentoCache.create!(afastamento_id_pessoas: 1, cpf: "11122233344")
    afastamento2 = AfastamentoCache.create!(afastamento_id_pessoas: 2, cpf: "11122233344")

    assert_equal [ afastamento1, afastamento2 ].sort_by(&:id), cache.afastamento_caches.sort_by(&:id)
  end
end
