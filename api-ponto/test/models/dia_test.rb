require "test_helper"

class DiaTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
    @data = Date.new(2026, 7, 22)
  end

  # --- Construcao (Sprint 16, task 16.1) ---

  test "para constroi um Dia para o usuario e data informados" do
    dia = Dia.para(@user, @data)

    assert_equal @user, dia.user
    assert_equal @data, dia.data
  end

  test "aceita Time/DateTime e normaliza para Date" do
    dia = Dia.para(@user, @data.midday)

    assert_equal @data, dia.data
  end

  # --- Agregacao de registros (equivalente a RegistroFrequencia/TimeRecord) ---

  test "registros agrega os TimeRecords do usuario na data, ordenados por horario" do
    saida = TimeRecord.create!(
      user: @user, raw_data: "saida", punched_at: @data.midday + 8.hours,
      authentication_mode: "biometric", punch_type: "exit"
    )
    entrada = TimeRecord.create!(
      user: @user, raw_data: "entrada", punched_at: @data.midday,
      authentication_mode: "biometric", punch_type: "entry"
    )

    dia = Dia.para(@user, @data)

    assert_equal [ entrada, saida ], dia.registros.to_a
  end

  test "registros nao inclui batidas de outro dia" do
    TimeRecord.create!(
      user: @user, raw_data: "outro dia", punched_at: @data.tomorrow.midday,
      authentication_mode: "biometric"
    )

    dia = Dia.para(@user, @data)

    assert_empty dia.registros
  end

  test "registros nao inclui batidas de outro usuario" do
    outro_user = users(:two)
    TimeRecord.create!(
      user: outro_user, raw_data: "outro usuario", punched_at: @data.midday,
      authentication_mode: "biometric"
    )

    dia = Dia.para(@user, @data)

    assert_empty dia.registros
  end

  test "registros retorna vazio quando nao ha batidas no dia" do
    dia = Dia.para(@user, @data)

    assert_empty dia.registros
  end

  # --- Calculo diario (Sprint 16, task 16.1 — so estrutura, sem logica) ---

  test "calculo eh nil quando o motor de calculo ainda nao rodou para o dia" do
    dia = Dia.para(@user, @data)

    assert_nil dia.calculo
  end

  test "calculo expõe o CalculoDiario existente para o usuario e data" do
    calculo_diario = CalculoDiario.create!(user: @user, data: @data)

    dia = Dia.para(@user, @data)

    assert_equal calculo_diario, dia.calculo
  end

  test "calculo nao populado nao possui nenhum valor de horas calculado" do
    CalculoDiario.create!(user: @user, data: @data)

    dia = Dia.para(@user, @data)

    assert_nil dia.calculo.total_segundos
    assert_nil dia.calculo.meta_segundos
  end
end
