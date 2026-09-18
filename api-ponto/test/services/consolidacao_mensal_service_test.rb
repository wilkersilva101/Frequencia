require "test_helper"

class ConsolidacaoMensalServiceTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  def criar_regime(limite_credito: 10, limite_debito: 10)
    Regime.create!(
      nome: "Jornada",
      modalidade: "HORAS",
      limite_credito: limite_credito,
      limite_debito: limite_debito,
      expediente: [ { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "08:00", "fim" => "12:00" } ]
    )
  end

  def vincular(regime, data: Date.new(2026, 9, 1))
    RegimeFrequentador.create!(user: @user, regime: regime, momento_inicial: data - 30, tipo: RegimeFrequentador::OFICIAL)
  end

  def criar_calculo(data:, meta_segundos: 0, normal_segundos: 0, total_segundos: 0, falta: false, aberto: false)
    CalculoDiario.create!(
      user: @user, data: data,
      meta_segundos: meta_segundos, normal_segundos: normal_segundos,
      total_segundos: total_segundos, excepcional_segundos: 0,
      falta: falta, aberto: aberto
    )
  end

  def bater(momento)
    TimeRecord.create!(user: @user, punched_at: momento, raw_data: "x", authentication_mode: "manual")
  end

  # --- Agregação simples ---------------------------------------------------

  test "agrega trabalhado/meta_mensal/faltas/trabalhado_dias somados de vários dias" do
    regime = criar_regime
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600, normal_segundos: 4 * 3600)
    criar_calculo(data: Date.new(2026, 9, 2), meta_segundos: 4 * 3600, total_segundos: 0, falta: true)
    criar_calculo(data: Date.new(2026, 9, 3), meta_segundos: 4 * 3600, total_segundos: 4 * 3600, normal_segundos: 4 * 3600)

    hoje = Date.new(2026, 9, 30)
    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: hoje)

    assert_equal 8 * 3600, registro.trabalhado
    assert_equal 8 * 3600, registro.trabalhado_normal
    assert_equal 12 * 3600, registro.meta_mensal
    assert_equal 1, registro.faltas
    assert_equal 2, registro.trabalhado_dias
    assert_equal 3, registro.meta_mensal_dias
  end

  test "cria o registro mensal quando não existe e reaproveita quando já existe (recálculo)" do
    regime = criar_regime
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600)

    assert_difference -> { RegistroMensalFrequencia.count }, 1 do
      ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))
    end

    assert_no_difference -> { RegistroMensalFrequencia.count } do
      registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))
      assert_equal 4 * 3600, registro.trabalhado
    end
  end

  # --- meta_atual vs meta_mensal com dia futuro ----------------------------

  test "meta_atual não conta dia futuro, mas meta_mensal conta" do
    regime = criar_regime
    vincular(regime)
    hoje = Date.new(2026, 9, 10)

    criar_calculo(data: Date.new(2026, 9, 5), meta_segundos: 4 * 3600, total_segundos: 4 * 3600, normal_segundos: 4 * 3600)
    criar_calculo(data: Date.new(2026, 9, 20), meta_segundos: 4 * 3600, total_segundos: 0)

    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: hoje)

    assert_equal 8 * 3600, registro.meta_mensal
    # `meta_mensal_dias` é incrementado só dentro do bloco `pode_calcular?`
    # no legado (linhas 134-137, mesmo bloco de `meta_atual_dias`) — apesar
    # do nome sugerir "todos os dias do mês", só conta dias computáveis,
    # igual a `meta_atual_dias`. Portado com fidelidade ao legado.
    assert_equal 1, registro.meta_mensal_dias
    assert_equal 4 * 3600, registro.meta_atual
    assert_equal 1, registro.meta_atual_dias
  end

  test "dia de hoje conta na meta_atual quando não está mais aberto e teve algo trabalhado" do
    regime = criar_regime
    vincular(regime)
    hoje = Date.new(2026, 9, 10)

    criar_calculo(data: hoje, meta_segundos: 4 * 3600, total_segundos: 4 * 3600, aberto: false)

    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: hoje)

    assert_equal 4 * 3600, registro.meta_atual
    assert_equal 1, registro.meta_atual_dias
  end

  test "dia de hoje ainda aberto não conta na meta_atual" do
    regime = criar_regime
    vincular(regime)
    hoje = Date.new(2026, 9, 10)

    criar_calculo(data: hoje, meta_segundos: 4 * 3600, total_segundos: 4 * 3600, aberto: true)

    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: hoje)

    assert_equal 0, registro.meta_atual
    assert_equal 0, registro.meta_atual_dias
    assert_equal 1, registro.dias_em_aberto
  end

  # --- Saldo / banco de horas ----------------------------------------------

  test "saldo líquido simples sem exceder limite" do
    regime = criar_regime(limite_credito: 10, limite_debito: 10)
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 5 * 3600, normal_segundos: 5 * 3600)

    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))

    assert_equal 1 * 3600, registro.saldo_liquido
    assert_equal 0, registro.retido
    assert_equal 1 * 3600, registro.acumulado
  end

  test "saldo excedendo limite de crédito gera retido positivo e acumulado travado no limite" do
    regime = criar_regime(limite_credito: 2, limite_debito: 10)
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 0, total_segundos: 5 * 3600, normal_segundos: 5 * 3600)

    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))

    assert_equal 5 * 3600, registro.saldo_liquido
    assert_equal 3 * 3600, registro.retido
    assert_equal 2 * 3600, registro.acumulado
  end

  test "saldo excedendo limite de débito gera retido negativo e acumulado travado no limite negativo" do
    regime = criar_regime(limite_credito: 10, limite_debito: 2)
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 5 * 3600, total_segundos: 0)

    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))

    assert_equal(-5 * 3600, registro.saldo_liquido)
    assert_equal(-3 * 3600, registro.retido)
    assert_equal(-2 * 3600, registro.acumulado)
  end

  test "herda o acumulado do mês anterior quando existe registro anterior" do
    regime = criar_regime(limite_credito: 10, limite_debito: 10)
    vincular(regime, data: Date.new(2026, 8, 1))

    criar_calculo(data: Date.new(2026, 8, 1), meta_segundos: 0, total_segundos: 3 * 3600, normal_segundos: 3 * 3600)
    ConsolidacaoMensalService.consolidar(@user, 2026, 8, hoje: Date.new(2026, 8, 31))

    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600, normal_segundos: 4 * 3600)
    registro_setembro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))

    assert_equal 3 * 3600, registro_setembro.saldo_liquido
    assert_equal 0, registro_setembro.retido
    assert_equal 3 * 3600, registro_setembro.acumulado
  end

  test "saldo do mês anterior é 0 quando não existe registro anterior" do
    regime = criar_regime
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600, normal_segundos: 4 * 3600)

    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))

    assert_equal 0, registro.saldo_liquido
  end

  test "sem regime vigente no fim do mês não calcula saldo/banco de horas" do
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600, normal_segundos: 4 * 3600)

    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))

    assert_equal 4 * 3600, registro.trabalhado
    assert_equal 0, registro.saldo_liquido
    assert_equal 0, registro.acumulado
  end

  # --- Task 17.2 — congelamento (finalizado) --------------------------------

  test "recalcula normalmente quando o mês não está finalizado" do
    regime = criar_regime
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600)

    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))
    assert_equal 4 * 3600, registro.trabalhado
    assert_not registro.finalizado?
  end

  test "recusa recalcular um mês já finalizado, levantando MesFinalizadoError, sem alterar os campos calculados" do
    regime = criar_regime
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600)
    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))
    registro.finalizar!

    # Depois de finalizado, mais um dia de trabalho é lançado — se a trava
    # falhar (bug do legado reproduzido), esse dia seria contabilizado no
    # recálculo.
    criar_calculo(data: Date.new(2026, 9, 2), meta_segundos: 4 * 3600, total_segundos: 4 * 3600)

    assert_raises(ConsolidacaoMensalService::MesFinalizadoError) do
      ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))
    end

    registro.reload
    assert_equal 4 * 3600, registro.trabalhado
    assert registro.finalizado?
  end

  test "ConsolidacaoMensalService.finalizar marca finalizado true num registro existente" do
    regime = criar_regime
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600)
    ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))

    registro = ConsolidacaoMensalService.finalizar(@user, 2026, 9)

    assert registro.finalizado?
    assert RegistroMensalFrequencia.find_by(user: @user, ano: 2026, mes: 9).finalizado?
  end

  test "ConsolidacaoMensalService.finalizar levanta erro quando o mês nunca foi consolidado" do
    assert_raises(ActiveRecord::RecordNotFound) do
      ConsolidacaoMensalService.finalizar(@user, 2026, 9)
    end
  end

  test "reabrir! permite recalcular de novo um mês antes finalizado" do
    regime = criar_regime
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600)
    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))
    registro.finalizar!

    criar_calculo(data: Date.new(2026, 9, 2), meta_segundos: 4 * 3600, total_segundos: 4 * 3600)
    registro.reabrir!

    registro_recalculado = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))
    assert_equal 8 * 3600, registro_recalculado.trabalhado
  end

  test "um mês nunca calculado (registro novo) continua criável/calculável normalmente com a trava presente" do
    regime = criar_regime
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600)

    assert_difference -> { RegistroMensalFrequencia.count }, 1 do
      registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))
      assert_equal 4 * 3600, registro.trabalhado
      assert_not registro.finalizado?
    end
  end

  # --- Task 17.4 — auditoria de cobertura: fluxo ponta a ponta -------------
  #
  # Gap identificado: todos os testes acima (17.1/17.2) criam `CalculoDiario`
  # direto via `criar_calculo`/`create!`, nunca passando pelo
  # `CalculoDiarioService.calcular` real (Sprint 16). Isso prova a
  # consolidação isoladamente, mas não prova que as duas peças (motor diário
  # + consolidação mensal) realmente se encaixam — um teste que bata
  # `TimeRecord`s reais, rode `CalculoDiarioService.calcular` dia a dia e só
  # depois consolide é o que pegaria uma divergência de contrato entre os
  # dois services (ex: um campo que `CalculoDiarioService` grava com nome/
  # unidade diferente do que `ConsolidacaoMensalService` espera) que nenhum
  # teste unitário isolado cobriria.
  test "fluxo ponta a ponta: CalculoDiarioService dia a dia -> ConsolidacaoMensalService -> saldo bate -> finalizar -> trava efetiva" do
    regime = criar_regime(limite_credito: 10, limite_debito: 10)
    vincular(regime, data: Date.new(2026, 9, 1))

    # 2026-09-07 (segunda), 08 (terça), 09 (quarta) — dias úteis dentro do
    # expediente SEG-SEX 08:00-12:00 (meta 4h/dia) cadastrado em `criar_regime`.
    bater(Time.zone.local(2026, 9, 7, 8, 0))
    bater(Time.zone.local(2026, 9, 7, 12, 0)) # dia batido exatamente na meta: 4h

    bater(Time.zone.local(2026, 9, 8, 8, 0))
    bater(Time.zone.local(2026, 9, 8, 13, 0)) # dia com 1h além da meta: 5h

    # 2026-09-09 (quarta): nenhuma marcação -> falta (meta > 0, trabalhado 0,
    # data já passada em relação ao `hoje` usado abaixo).

    hoje = Date.new(2026, 9, 30)

    # `CalculoDiarioService#falta?` compara com `Date.current` (não recebe
    # `hoje:` injetado como `ConsolidacaoMensalService`) — `travel_to` garante
    # que 2026-09-09 seja tratado como dia já passado, reproduzindo a
    # situação real de calcular o mês depois que ele terminou.
    travel_to(hoje) do
      [ Date.new(2026, 9, 7), Date.new(2026, 9, 8), Date.new(2026, 9, 9) ].each do |data|
        CalculoDiarioService.calcular(@user, data)
      end
    end
    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: hoje)

    assert_equal 12 * 3600, registro.meta_mensal # 3 dias úteis x 4h
    assert_equal 9 * 3600, registro.trabalhado # 4h + 5h + 0h
    assert_equal 1, registro.faltas
    assert_equal 2, registro.trabalhado_dias
    # saldo líquido = trabalhado - meta_mensal = 9h - 12h = -3h; dentro do
    # limite de débito (10h), sem retenção.
    assert_equal(-3 * 3600, registro.saldo_liquido)
    assert_equal 0, registro.retido
    assert_equal(-3 * 3600, registro.acumulado)

    registro.finalizar!
    snapshot_antes = registro.reload.attributes.except("updated_at")

    # Depois de finalizado, mais um dia é batido e calculado via
    # `CalculoDiarioService` (motor real, não `criar_calculo` direto) para o
    # mesmo mês — se a trava falhar, esse dia entraria no recálculo.
    bater(Time.zone.local(2026, 9, 10, 8, 0))
    bater(Time.zone.local(2026, 9, 10, 12, 0))
    CalculoDiarioService.calcular(@user, Date.new(2026, 9, 10))

    assert_raises(ConsolidacaoMensalService::MesFinalizadoError) do
      ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: hoje)
    end

    # Trava "efetiva": absolutamente nenhum campo calculado mudou no banco,
    # não só o `trabalhado` (checado em outros testes) — comparação de
    # snapshot completo dos atributos.
    assert_equal snapshot_antes, registro.reload.attributes.except("updated_at")
    assert registro.finalizado?
  end

  # --- Task 17.4 — auditoria de cobertura: saldo acumulando mês a mês ------
  #
  # Gap identificado: o teste "herda o acumulado do mês anterior..." (17.1)
  # só cobre 2 meses e nenhum deles excede o limite de crédito/débito. Um
  # teste de 3 meses seguidos, onde o 2º mês excede o limite (gera `retido`)
  # e o 3º parte do saldo já retido/travado no limite, prova que o
  # encadeamento `acumulado` -> "saldo do mês anterior" funciona mesmo
  # cruzando a fronteira do banco de horas no meio da sequência.
  test "saldo acumula corretamente por 3 meses seguidos, inclusive cruzando o limite de crédito no meio da sequência" do
    regime = criar_regime(limite_credito: 5, limite_debito: 5)
    vincular(regime, data: Date.new(2026, 7, 1))

    # Mês 1 (julho): saldo bruto de +4h, ainda dentro do limite de 5h.
    criar_calculo(data: Date.new(2026, 7, 1), meta_segundos: 0, total_segundos: 4 * 3600, normal_segundos: 4 * 3600)
    registro_julho = ConsolidacaoMensalService.consolidar(@user, 2026, 7, hoje: Date.new(2026, 7, 31))

    assert_equal 4 * 3600, registro_julho.saldo_liquido
    assert_equal 0, registro_julho.retido
    assert_equal 4 * 3600, registro_julho.acumulado

    # Mês 2 (agosto): parte de +4h acumulado, soma +3h de saldo bruto ->
    # saldo líquido +7h, excede o limite de 5h -> retém 2h, acumulado trava em 5h.
    criar_calculo(data: Date.new(2026, 8, 1), meta_segundos: 0, total_segundos: 3 * 3600, normal_segundos: 3 * 3600)
    registro_agosto = ConsolidacaoMensalService.consolidar(@user, 2026, 8, hoje: Date.new(2026, 8, 31))

    assert_equal 7 * 3600, registro_agosto.saldo_liquido
    assert_equal 2 * 3600, registro_agosto.retido
    assert_equal 5 * 3600, registro_agosto.acumulado

    # Mês 3 (setembro): parte do acumulado já travado no limite (5h), sem
    # saldo bruto novo (trabalhado == meta) -> saldo líquido permanece 5h,
    # exatamente no limite (não excede, pois a condição é estritamente
    # "> limite"), sem retenção adicional.
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600, normal_segundos: 4 * 3600)
    registro_setembro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))

    assert_equal 5 * 3600, registro_setembro.saldo_liquido
    assert_equal 0, registro_setembro.retido
    assert_equal 5 * 3600, registro_setembro.acumulado
  end

  # --- Task 18.2 — RetificadorBancoHoras alimentando `retificado` ---------

  def criar_retificador(tipo:, segundos_a_retificar:, ano: 2026, mes: 9, excluido: false)
    RetificadorBancoHoras.create!(
      user: @user, ano: ano, mes: mes, tipo: tipo,
      segundos_a_retificar: segundos_a_retificar, excluido: excluido
    )
  end

  test "consolidar soma retificador de crédito (fator +1) em retificado e no saldo líquido" do
    regime = criar_regime
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600, normal_segundos: 4 * 3600)
    criar_retificador(tipo: RetificadorBancoHoras::CREDITO_POR_TRABALHO_EXCEPCIONAL, segundos_a_retificar: 2 * 3600)

    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))

    assert_equal 2 * 3600, registro.retificado
    assert_equal 2 * 3600, registro.saldo_liquido # saldo bruto 0 (trabalhado == meta) + retificado 2h
  end

  test "consolidar soma retificador de débito (fator -1) em retificado e no saldo líquido" do
    regime = criar_regime
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600, normal_segundos: 4 * 3600)
    criar_retificador(tipo: RetificadorBancoHoras::DEBITO_PARA_COMPENSACAO, segundos_a_retificar: 1 * 3600)

    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))

    assert_equal(-1 * 3600, registro.retificado)
    assert_equal(-1 * 3600, registro.saldo_liquido)
  end

  test "múltiplos retificadores no mesmo mês somam corretamente (não só o último)" do
    regime = criar_regime
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 0, total_segundos: 0)
    criar_retificador(tipo: RetificadorBancoHoras::CREDITO_POR_TRABALHO_EXCEPCIONAL, segundos_a_retificar: 3 * 3600)
    criar_retificador(tipo: RetificadorBancoHoras::CREDITO_POR_DEBITO_INDEVIDO, segundos_a_retificar: 1 * 3600)
    criar_retificador(tipo: RetificadorBancoHoras::DEBITO_PARA_COMPENSACAO, segundos_a_retificar: 2 * 3600)

    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))

    # +3h +1h -2h = +2h. Se houvesse o bug DUV-011 (atribuição em vez de
    # soma), o resultado seria só o último valor aplicado (-2h), não +2h.
    assert_equal 2 * 3600, registro.retificado
  end

  test "retificador excluído não entra na soma" do
    regime = criar_regime
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 0, total_segundos: 0)
    criar_retificador(tipo: RetificadorBancoHoras::CREDITO_POR_TRABALHO_EXCEPCIONAL, segundos_a_retificar: 5 * 3600, excluido: true)
    criar_retificador(tipo: RetificadorBancoHoras::CREDITO_POR_DEBITO_INDEVIDO, segundos_a_retificar: 1 * 3600)

    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))

    assert_equal 1 * 3600, registro.retificado
  end

  test "retificador de outro mês/ano não entra na soma" do
    regime = criar_regime
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 0, total_segundos: 0)
    criar_retificador(tipo: RetificadorBancoHoras::CREDITO_POR_TRABALHO_EXCEPCIONAL, segundos_a_retificar: 5 * 3600, mes: 8)
    criar_retificador(tipo: RetificadorBancoHoras::CREDITO_POR_TRABALHO_EXCEPCIONAL, segundos_a_retificar: 7 * 3600, ano: 2025)

    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))

    assert_equal 0, registro.retificado
  end

  test "aplicar_retificador recalcula retificado/saldo de um mês FINALIZADO, sem reagregar CalculoDiario" do
    regime = criar_regime(limite_credito: 10, limite_debito: 10)
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600, normal_segundos: 4 * 3600)
    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))
    registro.finalizar!

    # Lançado um dia extra de trabalho depois de finalizado, pra provar que
    # `aplicar_retificador` NÃO reagrega `CalculoDiario` (se reagregasse,
    # `trabalhado` mudaria de 4h para 8h).
    criar_calculo(data: Date.new(2026, 9, 2), meta_segundos: 4 * 3600, total_segundos: 4 * 3600)
    criar_retificador(tipo: RetificadorBancoHoras::CREDITO_POR_TRABALHO_EXCEPCIONAL, segundos_a_retificar: 3 * 3600)

    registro_retificado = ConsolidacaoMensalService.aplicar_retificador(@user, 2026, 9)

    assert registro_retificado.finalizado? # continua finalizado, não foi reaberto
    assert_equal 4 * 3600, registro_retificado.trabalhado # preservado, não reagregado
    assert_equal 3 * 3600, registro_retificado.retificado
    assert_equal 3 * 3600, registro_retificado.saldo_liquido # 0 (saldo bruto) + 3h retificado
  end

  test "aplicar_retificador levanta RecordNotFound quando o mês nunca foi consolidado" do
    assert_raises(ActiveRecord::RecordNotFound) do
      ConsolidacaoMensalService.aplicar_retificador(@user, 2026, 9)
    end
  end

  # --- Task 18.4 — auditoria de cobertura: retificação pós-fechamento -----
  #
  # Gap 1: o teste "aplicar_retificador recalcula retificado/saldo de um mês
  # FINALIZADO..." (18.2) só confirma `trabalhado` preservado — não prova
  # que TODOS os campos "congelados" da consolidação original
  # (meta_mensal/meta_atual/faltas/dias_em_aberto/trabalhado_normal/
  # trabalhado_dias) permanecem intocados, só os de saldo/banco de horas
  # (retificado/saldo_liquido/retido/acumulado) mudam. Um teste que só olha
  # `trabalhado` não pegaria uma regressão em `aplicar_retificador` que, por
  # engano, zerasse/reagregasse algum outro campo congelado.
  test "aplicar_retificador em mes finalizado muda so retificado/saldo_liquido/retido/acumulado, preserva todos os demais campos congelados" do
    regime = criar_regime(limite_credito: 10, limite_debito: 10)
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 5 * 3600, normal_segundos: 5 * 3600)
    criar_calculo(data: Date.new(2026, 9, 2), meta_segundos: 4 * 3600, total_segundos: 0, falta: true)
    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))
    registro.finalizar!

    campos_congelados_antes = registro.reload.attributes.slice(
      "trabalhado", "trabalhado_normal", "trabalhado_dias",
      "meta_mensal", "meta_mensal_dias", "meta_atual", "meta_atual_dias",
      "faltas", "dias_em_aberto"
    )

    # Lançado mais um dia de trabalho depois de finalizado — se
    # `aplicar_retificador` reagregasse `CalculoDiario` por engano, esses
    # campos "congelados" mudariam.
    criar_calculo(data: Date.new(2026, 9, 3), meta_segundos: 4 * 3600, total_segundos: 10 * 3600, normal_segundos: 10 * 3600)
    criar_retificador(tipo: RetificadorBancoHoras::CREDITO_POR_TRABALHO_EXCEPCIONAL, segundos_a_retificar: 2 * 3600)

    registro_retificado = ConsolidacaoMensalService.aplicar_retificador(@user, 2026, 9)

    # Campos congelados: idênticos, byte a byte, aos de antes da retificação.
    assert_equal campos_congelados_antes, registro_retificado.reload.attributes.slice(*campos_congelados_antes.keys)

    # Campos de saldo/banco de horas: mudaram para refletir o retificador.
    # saldo_bruto = trabalhado(5h) - meta_mensal(8h, dia 1 + dia 2 de falta)
    # = -3h; + retificado 2h = -1h. Dentro do limite de débito (10h).
    assert_equal 2 * 3600, registro_retificado.retificado
    assert_equal(-1 * 3600, registro_retificado.saldo_liquido)
    assert_equal 0, registro_retificado.retido
    assert_equal(-1 * 3600, registro_retificado.acumulado)
  end

  # Gap 2: nenhum teste existente prova que, depois de uma retificação
  # pós-fechamento (`aplicar_retificador`), o mês continua bloqueado para
  # `consolidar` (recálculo completo) — ou seja, que aplicar um retificador
  # não "reabre" o mês por engano. Sem esse teste, uma regressão que fizesse
  # `aplicar_retificador` tocar em `finalizado` (ex: um `save!` que
  # resetasse o campo) passaria despercebida.
  test "consolidar continua recusando com MesFinalizadoError mesmo depois de aplicar_retificador pos-fechamento" do
    regime = criar_regime
    vincular(regime)
    criar_calculo(data: Date.new(2026, 9, 1), meta_segundos: 4 * 3600, total_segundos: 4 * 3600)
    registro = ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))
    registro.finalizar!

    criar_retificador(tipo: RetificadorBancoHoras::CREDITO_POR_TRABALHO_EXCEPCIONAL, segundos_a_retificar: 1 * 3600)
    ConsolidacaoMensalService.aplicar_retificador(@user, 2026, 9)

    assert registro.reload.finalizado? # a retificação não reabriu o mês

    assert_raises(ConsolidacaoMensalService::MesFinalizadoError) do
      ConsolidacaoMensalService.consolidar(@user, 2026, 9, hoje: Date.new(2026, 9, 30))
    end
  end
end
