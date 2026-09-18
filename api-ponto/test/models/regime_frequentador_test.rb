require "test_helper"

class RegimeFrequentadorTest < ActiveSupport::TestCase
  test "valid with user, regime e momento_inicial" do
    regime = Regime.create!(nome: "Jornada Padrão")
    user = User.create!(nome_completo: "Fulano", password: "123456")

    rf = RegimeFrequentador.new(user: user, regime: regime, momento_inicial: Time.current, tipo: "principal")
    assert rf.valid?
  end

  test "invalid without momento_inicial" do
    regime = Regime.create!(nome: "Jornada Padrão")
    user = User.create!(nome_completo: "Fulano", password: "123456")

    rf = RegimeFrequentador.new(user: user, regime: regime)
    assert_not rf.valid?
    assert_includes rf.errors[:momento_inicial], "não pode ficar em branco"
  end

  test "invalid sem user" do
    regime = Regime.create!(nome: "Jornada Padrão")
    rf = RegimeFrequentador.new(regime: regime, momento_inicial: Time.current)
    assert_not rf.valid?
  end

  test "invalid sem regime" do
    user = User.create!(nome_completo: "Fulano", password: "123456")
    rf = RegimeFrequentador.new(user: user, momento_inicial: Time.current)
    assert_not rf.valid?
  end

  # --- Precedência (Sprint 16, task 16.3) ---------------------------------

  test "vigente_para retorna TEMPORARIO quando ha sobreposicao com DIFERENCIADO e OFICIAL" do
    regime = Regime.create!(nome: "Jornada Padrão")
    user = User.create!(nome_completo: "Fulano", password: "123456")
    data = Date.new(2026, 9, 7)

    RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: data - 30, tipo: RegimeFrequentador::OFICIAL)
    diferenciado = RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: data - 10, tipo: RegimeFrequentador::DIFERENCIADO)
    temporario = RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: data - 5, tipo: RegimeFrequentador::TEMPORARIO)

    assert_equal temporario, RegimeFrequentador.vigente_para(user, data)
    assert_not_equal diferenciado, RegimeFrequentador.vigente_para(user, data)
  end

  test "vigente_para retorna DIFERENCIADO quando vence OFICIAL na mesma data" do
    regime = Regime.create!(nome: "Jornada Padrão")
    user = User.create!(nome_completo: "Fulano", password: "123456")
    data = Date.new(2026, 9, 7)

    RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: data - 30, tipo: RegimeFrequentador::OFICIAL)
    diferenciado = RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: data - 10, tipo: RegimeFrequentador::DIFERENCIADO)

    assert_equal diferenciado, RegimeFrequentador.vigente_para(user, data)
  end

  test "vigente_para faz fallback pro OFICIAL quando so ele existe" do
    regime = Regime.create!(nome: "Jornada Padrão")
    user = User.create!(nome_completo: "Fulano", password: "123456")
    data = Date.new(2026, 9, 7)

    oficial = RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: data - 30, tipo: RegimeFrequentador::OFICIAL)

    assert_equal oficial, RegimeFrequentador.vigente_para(user, data)
  end

  test "vigente_para retorna nil quando nao ha regime vigente na data" do
    regime = Regime.create!(nome: "Jornada Padrão")
    user = User.create!(nome_completo: "Fulano", password: "123456")
    data = Date.new(2026, 9, 7)

    RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: data + 5, tipo: RegimeFrequentador::OFICIAL)

    assert_nil RegimeFrequentador.vigente_para(user, data)
  end

  test "vigente_para respeita momento_final quando presente" do
    regime = Regime.create!(nome: "Jornada Padrão")
    user = User.create!(nome_completo: "Fulano", password: "123456")
    data = Date.new(2026, 9, 7)

    RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: data - 30, momento_final: data - 1, tipo: RegimeFrequentador::OFICIAL)

    assert_nil RegimeFrequentador.vigente_para(user, data)
  end

  test "vigente_para trata tipo desconhecido/ausente como menor precedencia que OFICIAL" do
    regime = Regime.create!(nome: "Jornada Padrão")
    user = User.create!(nome_completo: "Fulano", password: "123456")
    data = Date.new(2026, 9, 7)

    RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: data - 30, tipo: nil)
    oficial = RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: data - 10, tipo: RegimeFrequentador::OFICIAL)

    assert_equal oficial, RegimeFrequentador.vigente_para(user, data)
  end

  test "vigente_para nao mistura regimes de outro usuario" do
    regime = Regime.create!(nome: "Jornada Padrão")
    user = User.create!(nome_completo: "Fulano", password: "123456")
    outro_user = User.create!(nome_completo: "Ciclano", password: "123456")
    data = Date.new(2026, 9, 7)

    RegimeFrequentador.create!(user: outro_user, regime: regime, momento_inicial: data - 30, tipo: RegimeFrequentador::TEMPORARIO)

    assert_nil RegimeFrequentador.vigente_para(user, data)
  end
end
