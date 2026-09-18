require "test_helper"

class RegistroMensalFrequenciaTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  test "válido com ano/mes/user e datas de início/fim" do
    registro = RegistroMensalFrequencia.new(
      user: @user, ano: 2026, mes: 9,
      data_inicio: Date.new(2026, 9, 1), data_fim: Date.new(2026, 9, 30)
    )

    assert registro.valid?
  end

  test "mes fora de 1..12 é inválido" do
    registro = RegistroMensalFrequencia.new(
      user: @user, ano: 2026, mes: 13,
      data_inicio: Date.new(2026, 9, 1), data_fim: Date.new(2026, 9, 30)
    )

    assert_not registro.valid?
    assert_includes registro.errors[:mes], "não está incluído na lista"
  end

  test "não permite dois registros do mesmo usuário/ano/mes" do
    RegistroMensalFrequencia.create!(
      user: @user, ano: 2026, mes: 9,
      data_inicio: Date.new(2026, 9, 1), data_fim: Date.new(2026, 9, 30)
    )

    duplicado = RegistroMensalFrequencia.new(
      user: @user, ano: 2026, mes: 9,
      data_inicio: Date.new(2026, 9, 1), data_fim: Date.new(2026, 9, 30)
    )

    assert_not duplicado.valid?
    assert_includes duplicado.errors[:mes], "já está em uso"
  end

  # --- Task 17.2 — finalizar!/reabrir! -------------------------------------

  test "nasce com finalizado false por padrão" do
    registro = RegistroMensalFrequencia.create!(
      user: @user, ano: 2026, mes: 9,
      data_inicio: Date.new(2026, 9, 1), data_fim: Date.new(2026, 9, 30)
    )

    assert_not registro.finalizado?
  end

  test "finalizar! marca finalizado true e persiste" do
    registro = RegistroMensalFrequencia.create!(
      user: @user, ano: 2026, mes: 9,
      data_inicio: Date.new(2026, 9, 1), data_fim: Date.new(2026, 9, 30)
    )

    registro.finalizar!

    assert registro.finalizado?
    assert registro.reload.finalizado?
  end

  test "reabrir! marca finalizado false e persiste" do
    registro = RegistroMensalFrequencia.create!(
      user: @user, ano: 2026, mes: 9,
      data_inicio: Date.new(2026, 9, 1), data_fim: Date.new(2026, 9, 30),
      finalizado: true
    )

    registro.reabrir!

    assert_not registro.finalizado?
    assert_not registro.reload.finalizado?
  end
end
