require "test_helper"

class CalculoDiarioServiceTest < ActiveSupport::TestCase
  # 2026-09-07 eh uma segunda-feira (wday 1) — usado como data fixa em
  # todos os testes pra bater com o expediente SEG-SEX cadastrado.
  SEGUNDA = Date.new(2026, 9, 7)

  def setup
    @user = users(:one)
  end

  def criar_regime(modalidade:, inicio: "08:00", fim: "12:00")
    Regime.create!(
      nome: "Jornada #{modalidade}",
      modalidade: modalidade,
      expediente: [ { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => inicio, "fim" => fim } ]
    )
  end

  def vincular(regime, data: SEGUNDA)
    RegimeFrequentador.create!(user: @user, regime: regime, momento_inicial: data - 30, tipo: RegimeFrequentador::OFICIAL)
  end

  def bater(momento)
    TimeRecord.create!(user: @user, punched_at: momento, raw_data: "x", authentication_mode: "manual")
  end

  # --- Orquestração --------------------------------------------------------

  test "sem regime vigente marca informacao e zera meta/trabalhado" do
    resultado = CalculoDiarioService.calcular(@user, SEGUNDA)

    assert_equal "Nenhum regime ativo nesta data", resultado.informacao
    assert_equal 0, resultado.meta_segundos
    assert_equal 0, resultado.total_segundos
    assert_equal false, resultado.falta
  end

  test "persiste o resultado em CalculoDiario via find_or_initialize_by" do
    regime = criar_regime(modalidade: "HORAS")
    vincular(regime)
    bater(Time.zone.local(2026, 9, 7, 8, 0))
    bater(Time.zone.local(2026, 9, 7, 12, 0))

    assert_difference -> { CalculoDiario.count }, 1 do
      CalculoDiarioService.calcular(@user, SEGUNDA)
    end

    calculo = CalculoDiario.find_by(user: @user, data: SEGUNDA)
    assert_equal 4 * 3600, calculo.meta_segundos
    assert_equal 4 * 3600, calculo.total_segundos

    assert_no_difference -> { CalculoDiario.count } do
      CalculoDiarioService.calcular(@user, SEGUNDA)
    end
  end

  test "despacha HORAS_COM_INTERVALO para EntradasESaidas" do
    regime = criar_regime(modalidade: "HORAS_COM_INTERVALO")
    vincular(regime)
    bater(Time.zone.local(2026, 9, 7, 8, 0))
    bater(Time.zone.local(2026, 9, 7, 10, 0))

    resultado = CalculoDiarioService.calcular(@user, SEGUNDA)
    assert_equal 2 * 3600, resultado.total_segundos
  end

  test "despacha OCORRENCIAS para Ocorrencias" do
    regime = criar_regime(modalidade: "OCORRENCIAS")
    vincular(regime)
    bater(Time.zone.local(2026, 9, 7, 8, 0))

    resultado = CalculoDiarioService.calcular(@user, SEGUNDA)
    assert_equal resultado.meta_segundos, resultado.total_segundos
  end

  # --- PrimeiraEntradaUltimaSaida (modalidade HORAS) -----------------------

  test "PrimeiraEntradaUltimaSaida: meta calculada a partir do Regime" do
    regime = criar_regime(modalidade: "HORAS", inicio: "07:00", fim: "13:00")
    estrategia = CalculoDiarioService::PrimeiraEntradaUltimaSaida.new(user: @user, data: SEGUNDA, regime: regime)

    assert_equal 6 * 3600, estrategia.calcular[:meta_segundos]
  end

  test "PrimeiraEntradaUltimaSaida: trabalhado eh a diferenca entre primeira e ultima marcacao" do
    regime = criar_regime(modalidade: "HORAS")
    bater(Time.zone.local(2026, 9, 7, 8, 0))
    bater(Time.zone.local(2026, 9, 7, 9, 30))
    bater(Time.zone.local(2026, 9, 7, 12, 15))

    estrategia = CalculoDiarioService::PrimeiraEntradaUltimaSaida.new(user: @user, data: SEGUNDA, regime: regime)
    assert_equal (4 * 3600) + (15 * 60), estrategia.calcular[:trabalhado_segundos]
  end

  test "PrimeiraEntradaUltimaSaida: dia sem marcacao nenhuma trabalha zero" do
    regime = criar_regime(modalidade: "HORAS")
    estrategia = CalculoDiarioService::PrimeiraEntradaUltimaSaida.new(user: @user, data: SEGUNDA, regime: regime)

    assert_equal 0, estrategia.calcular[:trabalhado_segundos]
  end

  # --- EntradasESaidas (modalidade HORAS_COM_INTERVALO) --------------------

  test "EntradasESaidas: soma os pares completos de entrada/saida" do
    regime = criar_regime(modalidade: "HORAS_COM_INTERVALO")
    bater(Time.zone.local(2026, 9, 7, 8, 0))
    bater(Time.zone.local(2026, 9, 7, 10, 0))
    bater(Time.zone.local(2026, 9, 7, 11, 0))
    bater(Time.zone.local(2026, 9, 7, 12, 0))

    estrategia = CalculoDiarioService::EntradasESaidas.new(user: @user, data: SEGUNDA, regime: regime)
    assert_equal 3 * 3600, estrategia.calcular[:trabalhado_segundos]
  end

  test "EntradasESaidas: marcacao impar sobrando eh ignorada" do
    regime = criar_regime(modalidade: "HORAS_COM_INTERVALO")
    bater(Time.zone.local(2026, 9, 7, 8, 0))
    bater(Time.zone.local(2026, 9, 7, 10, 0))
    bater(Time.zone.local(2026, 9, 7, 11, 0)) # entrada sem par

    estrategia = CalculoDiarioService::EntradasESaidas.new(user: @user, data: SEGUNDA, regime: regime)
    assert_equal 2 * 3600, estrategia.calcular[:trabalhado_segundos]
  end

  test "EntradasESaidas: dia sem marcacao nenhuma trabalha zero" do
    regime = criar_regime(modalidade: "HORAS_COM_INTERVALO")
    estrategia = CalculoDiarioService::EntradasESaidas.new(user: @user, data: SEGUNDA, regime: regime)

    assert_equal 0, estrategia.calcular[:trabalhado_segundos]
  end

  # --- Ocorrencias (modalidade OCORRENCIAS) --------------------------------

  test "Ocorrencias: presenca binaria - com marcacao conta a meta inteira" do
    regime = criar_regime(modalidade: "OCORRENCIAS", inicio: "07:00", fim: "13:00")
    bater(Time.zone.local(2026, 9, 7, 7, 5))

    estrategia = CalculoDiarioService::Ocorrencias.new(user: @user, data: SEGUNDA, regime: regime)
    resultado = estrategia.calcular
    assert_equal 6 * 3600, resultado[:meta_segundos]
    assert_equal resultado[:meta_segundos], resultado[:trabalhado_segundos]
  end

  test "Ocorrencias: sem marcacao nenhuma trabalha zero" do
    regime = criar_regime(modalidade: "OCORRENCIAS")
    estrategia = CalculoDiarioService::Ocorrencias.new(user: @user, data: SEGUNDA, regime: regime)

    assert_equal 0, estrategia.calcular[:trabalhado_segundos]
  end

  test "Ocorrencias: marcacao impar sobrando ainda conta como presenca" do
    regime = criar_regime(modalidade: "OCORRENCIAS")
    bater(Time.zone.local(2026, 9, 7, 8, 0))
    bater(Time.zone.local(2026, 9, 7, 9, 0))
    bater(Time.zone.local(2026, 9, 7, 10, 0))

    estrategia = CalculoDiarioService::Ocorrencias.new(user: @user, data: SEGUNDA, regime: regime)
    resultado = estrategia.calcular
    assert_equal resultado[:meta_segundos], resultado[:trabalhado_segundos]
  end

  # --- TimeRecord desconsiderado (Sprint 19, task 19.2, UC-09) -------------
  #
  # Prova que `desconsiderado: true` tem efeito real no motor de cálculo,
  # não é só uma flag decorativa — o registro continua existindo na tabela
  # (visível), mas é excluído do cálculo do dia como se não existisse.

  test "PrimeiraEntradaUltimaSaida ignora TimeRecord desconsiderado" do
    regime = criar_regime(modalidade: "HORAS")
    bater(Time.zone.local(2026, 9, 7, 8, 0))
    bater(Time.zone.local(2026, 9, 7, 12, 0))
    desconsiderada = bater(Time.zone.local(2026, 9, 7, 18, 0))
    desconsiderada.desconsiderar!(justificativa: "Batida indevida fora do expediente", responsavel: users(:two))

    estrategia = CalculoDiarioService::PrimeiraEntradaUltimaSaida.new(user: @user, data: SEGUNDA, regime: regime)
    # Sem a desconsiderada, a diferenca eh 08:00 -> 12:00 (4h), nao 08:00 -> 18:00 (10h).
    assert_equal 4 * 3600, estrategia.calcular[:trabalhado_segundos]
  end

  test "EntradasESaidas ignora TimeRecord desconsiderado" do
    regime = criar_regime(modalidade: "HORAS_COM_INTERVALO")
    bater(Time.zone.local(2026, 9, 7, 8, 0))
    saida_valida = bater(Time.zone.local(2026, 9, 7, 9, 0))
    bater(Time.zone.local(2026, 9, 7, 9, 30))
    bater(Time.zone.local(2026, 9, 7, 11, 0))

    estrategia = CalculoDiarioService::EntradasESaidas.new(user: @user, data: SEGUNDA, regime: regime)
    # Antes de desconsiderar: pares [08:00,09:00]=1h + [09:30,11:00]=1h30 = 2h30.
    assert_equal (2 * 3600) + (30 * 60), estrategia.calcular[:trabalhado_segundos]

    saida_valida.desconsiderar!(justificativa: "Saida duplicada", responsavel: users(:two))

    estrategia_depois = CalculoDiarioService::EntradasESaidas.new(user: @user, data: SEGUNDA, regime: regime)
    # Sem a 09:00, o pareamento desloca: [08:00,09:30]=1h30 e [11:00] sobra
    # sem par -> 1h30, prova que a exclusao muda o resultado de verdade.
    assert_equal (1 * 3600) + (30 * 60), estrategia_depois.calcular[:trabalhado_segundos]
  end

  test "Ocorrencias: unica marcacao do dia desconsiderada conta como sem presenca" do
    regime = criar_regime(modalidade: "OCORRENCIAS")
    unica = bater(Time.zone.local(2026, 9, 7, 8, 0))
    unica.desconsiderar!(justificativa: "Batida invalida", responsavel: users(:two))

    estrategia = CalculoDiarioService::Ocorrencias.new(user: @user, data: SEGUNDA, regime: regime)
    assert_equal 0, estrategia.calcular[:trabalhado_segundos]
  end

  test "reconsiderar! devolve o TimeRecord ao calculo" do
    regime = criar_regime(modalidade: "HORAS")
    bater(Time.zone.local(2026, 9, 7, 8, 0))
    ultima = bater(Time.zone.local(2026, 9, 7, 18, 0))
    responsavel = users(:two)
    ultima.desconsiderar!(justificativa: "Engano", responsavel: responsavel)

    estrategia = CalculoDiarioService::PrimeiraEntradaUltimaSaida.new(user: @user, data: SEGUNDA, regime: regime)
    assert_equal 0, estrategia.calcular[:trabalhado_segundos]

    ultima.reconsiderar!(responsavel: responsavel)

    estrategia_depois = CalculoDiarioService::PrimeiraEntradaUltimaSaida.new(user: @user, data: SEGUNDA, regime: regime)
    assert_equal 10 * 3600, estrategia_depois.calcular[:trabalhado_segundos]
  end

  # --- TimeRecord desconsiderado por predio (Sprint 19, task 19.4, UC-11) --
  #
  # Mesma prova de efeito real da 19.2 (não é flag decorativa), adaptada
  # pro motivo específico de "desconsideracao_predio" —
  # `desconsiderar_por_predio!` reaproveita a mesma exclusão do cálculo.

  test "PrimeiraEntradaUltimaSaida ignora TimeRecord desconsiderado por predio" do
    regime = criar_regime(modalidade: "HORAS")
    estacao = estacoes_ponto(:one)
    bater(Time.zone.local(2026, 9, 7, 8, 0))
    bater(Time.zone.local(2026, 9, 7, 12, 0))
    desconsiderada = bater(Time.zone.local(2026, 9, 7, 18, 0))
    desconsiderada.update!(estacao_ponto: estacao)
    desconsiderada.desconsiderar_por_predio!(estacao_ponto: estacao, responsavel: users(:two))

    estrategia = CalculoDiarioService::PrimeiraEntradaUltimaSaida.new(user: @user, data: SEGUNDA, regime: regime)
    # Sem a desconsiderada, a diferenca eh 08:00 -> 12:00 (4h), nao 08:00 -> 18:00 (10h).
    assert_equal 4 * 3600, estrategia.calcular[:trabalhado_segundos]
  end
end
