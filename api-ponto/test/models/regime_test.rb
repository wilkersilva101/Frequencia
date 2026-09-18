require "test_helper"

class RegimeTest < ActiveSupport::TestCase
  test "valid with nome" do
    regime = Regime.new(nome: "Jornada Padrão", modalidade: "HORAS", resumo: "8h/dia", meta_semanal: "40h")
    assert regime.valid?
  end

  test "resumo_exibicao usa o campo resumo quando presente" do
    regime = Regime.new(resumo: "8h/dia", expediente: [ { "dias" => "SEG,TER", "inicio" => "08:00", "fim" => "16:00" } ])
    assert_equal [ "8h/dia" ], regime.resumo_exibicao
  end

  test "resumo_exibicao computa dias/horas do expediente quando resumo esta em branco" do
    regime = Regime.new(expediente: [
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "07:00", "fim" => "13:00" }
    ])
    assert_equal [ "SEG,TER,QUA,QUI,SEX, de 07:00 às 13:00" ], regime.resumo_exibicao
  end

  test "resumo_exibicao lista um item por periodo do expediente" do
    regime = Regime.new(expediente: [
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "08:00", "fim" => "12:00" },
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "14:00", "fim" => "18:00" }
    ])
    assert_equal [
      "SEG,TER,QUA,QUI,SEX, de 08:00 às 12:00",
      "SEG,TER,QUA,QUI,SEX, de 14:00 às 18:00"
    ], regime.resumo_exibicao
  end

  test "resumo_exibicao retorna vazio quando nao ha resumo nem expediente" do
    regime = Regime.new
    assert_equal [], regime.resumo_exibicao
  end

  test "invalid without nome" do
    regime = Regime.new
    assert_not regime.valid?
    assert_includes regime.errors[:nome], "não pode ficar em branco"
  end

  test "invalid with modalidade fora das disponiveis" do
    regime = Regime.new(nome: "Jornada Padrão", modalidade: "Presencial")
    assert_not regime.valid?
    assert_includes regime.errors[:modalidade], "não está incluído na lista"
  end

  test "valid sem modalidade (allow_nil)" do
    regime = Regime.new(nome: "Jornada Padrão", modalidade: nil)
    assert regime.valid?
  end

  test "Regime::MODALIDADES_LABELS cobre todos os valores de MODALIDADES_DISPONIVEIS" do
    assert_equal Regime::MODALIDADES_DISPONIVEIS.sort, Regime::MODALIDADES_LABELS.keys.sort
  end

  test "Regime::MODALIDADES_LABELS tem os textos exatos pedidos" do
    assert_equal "Horas", Regime::MODALIDADES_LABELS["HORAS"]
    assert_equal "Horas com intervalo", Regime::MODALIDADES_LABELS["HORAS_COM_INTERVALO"]
    assert_equal "Ocorrências", Regime::MODALIDADES_LABELS["OCORRENCIAS"]
  end

  test "has many regime_frequentadores e users through" do
    regime = Regime.create!(nome: "Jornada Padrão")
    user = User.create!(nome_completo: "Fulano", password: "123456")
    RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: Time.current)

    assert_includes regime.users, user
  end

  test "restrict_with_exception impede excluir regime com regime_frequentadores vinculados" do
    regime = Regime.create!(nome: "Jornada Padrão")
    user = User.create!(nome_completo: "Fulano", password: "123456")
    RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: Time.current)

    assert_raises(ActiveRecord::DeleteRestrictionError) { regime.destroy }
  end

  test "categorias= cria regime_categorias associadas" do
    regime = Regime.create!(nome: "Jornada Padrão", categorias: [ "SERVIDOR_CARREIRA", "AUXILIAR_DA_JUSTICA" ])

    assert_equal [ "SERVIDOR_CARREIRA", "AUXILIAR_DA_JUSTICA" ], regime.reload.categorias
  end

  test "categorias= substitui as categorias existentes (nao acumula)" do
    regime = Regime.create!(nome: "Jornada Padrão", categorias: [ "SERVIDOR_CARREIRA" ])
    regime.update!(categorias: [ "ESTAGIARIO" ])

    assert_equal [ "ESTAGIARIO" ], regime.reload.categorias
  end

  test "categorias= ignora valores em branco" do
    regime = Regime.create!(nome: "Jornada Padrão", categorias: [ "SERVIDOR_CARREIRA", "", nil ])

    assert_equal [ "SERVIDOR_CARREIRA" ], regime.reload.categorias
  end

  test "categorias vazio por padrao" do
    regime = Regime.create!(nome: "Jornada Padrão")
    assert_equal [], regime.categorias
  end

  test "belongs_to anterior e padrao (auto-referencia opcional)" do
    regime_base = Regime.create!(nome: "Jornada Base")
    regime_novo = Regime.create!(nome: "Jornada Nova", anterior: regime_base, padrao: regime_base)

    assert_equal regime_base, regime_novo.anterior
    assert_equal regime_base, regime_novo.padrao
  end

  test "expediente aceita array de horarios em jsonb" do
    horario = { "inicio" => "08:00", "fim" => "12:00", "dias" => "SEG,TER,QUA,QUI,SEX" }
    regime = Regime.create!(nome: "Jornada Padrão", expediente: [ horario ])

    assert_equal [ horario ], regime.reload.expediente
  end

  # --- meta_semanal_em_minutos --------------------------------------------

  test "meta_semanal_em_minutos soma minutos por dia x quantidade de dias, modalidade HORAS, periodo unico" do
    regime = Regime.new(modalidade: "HORAS", expediente: [
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "07:00", "fim" => "13:00" }
    ])

    assert_equal 1800, regime.meta_semanal_em_minutos # 6h (360min) x 5 dias
  end

  test "meta_semanal_em_minutos soma multiplos periodos, modalidade HORAS" do
    regime = Regime.new(modalidade: "HORAS", expediente: [
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "08:00", "fim" => "12:00" },
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "14:00", "fim" => "18:00" }
    ])

    assert_equal 2400, regime.meta_semanal_em_minutos # (240 + 240) min x 5 dias
  end

  test "meta_semanal_em_minutos modalidade OCORRENCIAS conta dias, nao minutos" do
    regime = Regime.new(modalidade: "OCORRENCIAS", expediente: [
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "07:00", "fim" => "13:00" }
    ])

    assert_equal 5, regime.meta_semanal_em_minutos
  end

  test "meta_semanal_em_minutos modalidade HORAS_COM_INTERVALO conta dias, nao minutos" do
    regime = Regime.new(modalidade: "HORAS_COM_INTERVALO", expediente: [
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "07:00", "fim" => "13:00" }
    ])

    assert_equal 5, regime.meta_semanal_em_minutos
  end

  test "meta_semanal_em_minutos retorna 0 quando expediente vazio" do
    regime = Regime.new(modalidade: "HORAS", expediente: [])

    assert_equal 0, regime.meta_semanal_em_minutos
  end

  # --- meta_semanal_em_milissegundos --------------------------------------

  test "meta_semanal_em_milissegundos converte a versao em minutos calculada como HORAS" do
    regime = Regime.new(modalidade: "OCORRENCIAS", expediente: [
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "07:00", "fim" => "13:00" }
    ])

    assert_equal 1_800 * 60 * 1000, regime.meta_semanal_em_milissegundos
  end

  # --- meta_semanal_formatada ----------------------------------------------

  test "meta_semanal_formatada sem casa decimal" do
    regime = Regime.new(modalidade: "HORAS", expediente: [
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "07:00", "fim" => "13:00" }
    ])

    assert_equal "30h", regime.meta_semanal_formatada
  end

  test "meta_semanal_formatada com casa decimal" do
    regime = Regime.new(modalidade: "HORAS", expediente: [
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "07:00", "fim" => "13:30" }
    ])

    assert_equal "32,5h", regime.meta_semanal_formatada
  end

  test "meta_semanal_formatada modalidade OCORRENCIAS retorna so o numero, sem sufixo h" do
    regime = Regime.new(modalidade: "OCORRENCIAS", expediente: [
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "07:00", "fim" => "13:00" }
    ])

    assert_equal "5", regime.meta_semanal_formatada
  end

  test "meta_semanal_formatada retorna 0h quando expediente vazio" do
    regime = Regime.new(modalidade: "HORAS", expediente: [])

    assert_equal "0h", regime.meta_semanal_formatada
  end

  # --- periodos_por_dia_da_semana ------------------------------------------

  test "periodos_por_dia_da_semana agrupa periodos por dia, um periodo cobrindo varios dias" do
    regime = Regime.new(expediente: [
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "07:00", "fim" => "13:00" }
    ])

    periodos = regime.periodos_por_dia_da_semana

    assert_equal [ { "inicio" => "07:00", "fim" => "13:00" } ], periodos[1] # segunda
    assert_equal [ { "inicio" => "07:00", "fim" => "13:00" } ], periodos[5] # sexta
    assert_empty periodos[0] # domingo nao tem periodo
    assert_empty periodos[6] # sabado nao tem periodo
  end

  test "periodos_por_dia_da_semana agrupa multiplos horarios no mesmo dia" do
    regime = Regime.new(expediente: [
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "08:00", "fim" => "12:00" },
      { "dias" => "SEG,TER,QUA,QUI,SEX,", "inicio" => "14:00", "fim" => "18:00" }
    ])

    periodos = regime.periodos_por_dia_da_semana

    assert_equal [
      { "inicio" => "08:00", "fim" => "12:00" },
      { "inicio" => "14:00", "fim" => "18:00" }
    ], periodos[1]
  end

  test "periodos_por_dia_da_semana suporta dias diferentes em periodos diferentes" do
    regime = Regime.new(expediente: [
      { "dias" => "SEG,QUA,SEX,", "inicio" => "08:00", "fim" => "12:00" },
      { "dias" => "SAB,", "inicio" => "08:00", "fim" => "12:00" }
    ])

    periodos = regime.periodos_por_dia_da_semana

    assert_equal [ { "inicio" => "08:00", "fim" => "12:00" } ], periodos[1] # segunda
    assert_equal [ { "inicio" => "08:00", "fim" => "12:00" } ], periodos[3] # quarta
    assert_equal [ { "inicio" => "08:00", "fim" => "12:00" } ], periodos[5] # sexta
    assert_equal [ { "inicio" => "08:00", "fim" => "12:00" } ], periodos[6] # sabado
    assert_empty periodos[2] # terca nao tem periodo
  end

  test "periodos_por_dia_da_semana retorna vazio quando nao ha expediente" do
    regime = Regime.new(expediente: [])

    assert_equal({}, regime.periodos_por_dia_da_semana)
  end
end
