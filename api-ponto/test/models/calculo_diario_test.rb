require "test_helper"

class CalculoDiarioTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  # --- Estrutura (Sprint 16, task 16.1) ---

  test "belongs_to user" do
    calculo = CalculoDiario.new(user: @user, data: Date.new(2026, 9, 1))
    assert_equal @user, calculo.user
  end

  test "requer data" do
    calculo = CalculoDiario.new(user: @user)
    assert_not calculo.valid?
    assert_includes calculo.errors[:data], "não pode ficar em branco"
  end

  test "eh unico por usuario e data" do
    CalculoDiario.create!(user: @user, data: Date.new(2026, 9, 1))
    duplicado = CalculoDiario.new(user: @user, data: Date.new(2026, 9, 1))

    assert_not duplicado.valid?
  end

  test "permite mesma data para usuarios diferentes" do
    outro_user = users(:two)
    CalculoDiario.create!(user: @user, data: Date.new(2026, 9, 1))
    calculo_outro = CalculoDiario.new(user: outro_user, data: Date.new(2026, 9, 1))

    assert calculo_outro.valid?
  end

  test "permite mesmo usuario em datas diferentes" do
    CalculoDiario.create!(user: @user, data: Date.new(2026, 9, 1))
    calculo_outra_data = CalculoDiario.new(user: @user, data: Date.new(2026, 9, 2))

    assert calculo_outra_data.valid?
  end

  # --- Campos de resultado do calculo (Sprint 16, task 16.1) ---
  # Escopo estrito: so estrutura. Nenhuma logica de calculo populou esses
  # campos ainda (fica para 16.2/16.3) — aqui so provamos que a coluna
  # existe e comeca vazia/no default.

  test "campos numericos de resultado comecam nil" do
    calculo = CalculoDiario.create!(user: @user, data: Date.new(2026, 9, 1))

    assert_nil calculo.normal_segundos
    assert_nil calculo.excepcional_segundos
    assert_nil calculo.total_segundos
    assert_nil calculo.meta_segundos
  end

  test "flags de estado comecam false por default" do
    calculo = CalculoDiario.create!(user: @user, data: Date.new(2026, 9, 1))

    assert_equal false, calculo.aberto
    assert_equal false, calculo.ausencia
    assert_equal false, calculo.falta
    assert_equal false, calculo.falta_a_descontar
    assert_equal false, calculo.falta_compensada
    assert_equal false, calculo.descontado_em_folha
  end

  test "informacao aceita texto livre e nil" do
    calculo = CalculoDiario.create!(user: @user, data: Date.new(2026, 9, 1))
    assert_nil calculo.informacao

    calculo.update!(informacao: "nota de teste")
    assert_equal "nota de teste", calculo.reload.informacao
  end
end
