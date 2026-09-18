require "test_helper"

class RegimeCategoriaTest < ActiveSupport::TestCase
  test "valid with categoria dentro das disponiveis" do
    regime = Regime.create!(nome: "Jornada Padrão")
    rc = RegimeCategoria.new(regime: regime, categoria: "SERVIDOR_CARREIRA")
    assert rc.valid?
  end

  test "invalid sem categoria" do
    regime = Regime.create!(nome: "Jornada Padrão")
    rc = RegimeCategoria.new(regime: regime, categoria: nil)
    assert_not rc.valid?
  end

  test "invalid com categoria fora da lista" do
    regime = Regime.create!(nome: "Jornada Padrão")
    rc = RegimeCategoria.new(regime: regime, categoria: "Categoria Inventada")
    assert_not rc.valid?
    assert_includes rc.errors[:categoria], "não está incluído na lista"
  end

  test "invalid sem regime" do
    rc = RegimeCategoria.new(categoria: "SERVIDOR_CARREIRA")
    assert_not rc.valid?
  end

  test "invalid com rotulo em portugues antigo (nao e mais um codigo valido)" do
    regime = Regime.create!(nome: "Jornada Padrão")
    rc = RegimeCategoria.new(regime: regime, categoria: "Servidor Efetivo")
    assert_not rc.valid?
  end

  test "Regime::CATEGORIAS_LABELS cobre todos os codigos de CATEGORIAS_DISPONIVEIS" do
    assert_equal Regime::CATEGORIAS_DISPONIVEIS.sort, Regime::CATEGORIAS_LABELS.keys.sort
  end
end
