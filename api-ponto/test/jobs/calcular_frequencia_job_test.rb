require "test_helper"

class CalcularFrequenciaJobTest < ActiveJob::TestCase
  # `CalculoDiarioService.calcular` é um método real (`def self.calcular`),
  # então `remove_method` depois de um `define_singleton_method` o apagaria
  # de vez em vez de restaurar a definição original. Salvamos o método
  # original e o restauramos via `define_singleton_method` no `ensure`.
  def com_calcular_stub(stub)
    original = CalculoDiarioService.method(:calcular)
    CalculoDiarioService.define_singleton_method(:calcular, &stub)
    yield
  ensure
    CalculoDiarioService.define_singleton_method(:calcular) { |*args| original.call(*args) }
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

  def vincular(user, regime, data:)
    RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: data - 60, tipo: RegimeFrequentador::OFICIAL)
  end

  def bater(user, momento)
    TimeRecord.create!(user: user, punched_at: momento, raw_data: "x", authentication_mode: "manual")
  end

  test "roda sem erro para usuario sem nenhum TimeRecord" do
    user = User.create!(nome_completo: "Sem Marcacao", password: "123456", cpf: "11122233344")

    assert_nothing_raised { CalcularFrequenciaJob.perform_now(user.id) }

    assert_equal 3, CalculoDiario.where(user: user).count
  end

  test "recalcula CalculoDiario dos ultimos 3 dias e consolida o mes corrente" do
    hoje = Date.new(2026, 9, 15)
    user = User.create!(nome_completo: "Fulano", password: "123456", cpf: "11122233344")
    regime = criar_regime
    vincular(user, regime, data: hoje)

    travel_to(hoje.to_time.change(hour: 18)) do
      bater(user, hoje.to_time.change(hour: 8))
      bater(user, hoje.to_time.change(hour: 12))
      bater(user, (hoje - 1).to_time.change(hour: 8))
      bater(user, (hoje - 1).to_time.change(hour: 12))

      CalcularFrequenciaJob.perform_now(user.id)
    end

    [ hoje, hoje - 1, hoje - 2 ].each do |data|
      assert CalculoDiario.exists?(user: user, data: data), "esperava CalculoDiario para #{data}"
    end

    calculo_hoje = CalculoDiario.find_by(user: user, data: hoje)
    assert_equal 4 * 3600, calculo_hoje.total_segundos

    registro = RegistroMensalFrequencia.find_by(user: user, ano: hoje.year, mes: hoje.month)
    assert registro.present?
    assert_equal 8 * 3600, registro.trabalhado
  end

  test "pula silenciosamente usuario com mes ja finalizado, sem interromper os demais" do
    hoje = Date.new(2026, 9, 15)
    user_finalizado = User.create!(nome_completo: "Mes Fechado", password: "123456", cpf: "11122233344")
    user_normal = User.create!(nome_completo: "Mes Aberto", password: "123456", cpf: "55566677788")

    regime = criar_regime
    vincular(user_finalizado, regime, data: hoje)
    vincular(user_normal, regime, data: hoje)

    travel_to(hoje.to_time.change(hour: 18)) do
      ConsolidacaoMensalService.consolidar(user_finalizado, hoje.year, hoje.month)
      ConsolidacaoMensalService.finalizar(user_finalizado, hoje.year, hoje.month)

      bater(user_normal, hoje.to_time.change(hour: 8))
      bater(user_normal, hoje.to_time.change(hour: 12))

      assert_nothing_raised { CalcularFrequenciaJob.perform_now }
    end

    registro_normal = RegistroMensalFrequencia.find_by(user: user_normal, ano: hoje.year, mes: hoje.month)
    assert registro_normal.present?
    assert_equal 4 * 3600, registro_normal.trabalhado
  end

  test "erro generico em um usuario nao impede o processamento dos demais" do
    user1 = User.create!(nome_completo: "Vai Falhar", password: "123456", cpf: "11122233344")
    user2 = User.create!(nome_completo: "Vai Funcionar", password: "123456", cpf: "55566677788")

    original_calcular = CalculoDiarioService.method(:calcular)
    stub_calcular = lambda do |user, data|
      raise "falha simulada" if user.cpf == "11122233344"

      original_calcular.call(user, data)
    end

    com_calcular_stub(stub_calcular) do
      assert_nothing_raised { CalcularFrequenciaJob.perform_now }
    end

    assert_equal 0, CalculoDiario.where(user: user1).count
    assert_equal 3, CalculoDiario.where(user: user2).count
  end

  test "nao executa quando o lock ja esta adquirido por outra execucao" do
    user = User.create!(nome_completo: "Fulano", password: "123456", cpf: "11122233344")
    chamou = false
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    outra_conexao = PG.connect(host: config[:host], port: config[:port], dbname: config[:database], user: config[:username], password: config[:password])

    begin
      outra_conexao.exec("SELECT pg_try_advisory_lock(#{CalcularFrequenciaJob::LOCK_KEY})")

      com_calcular_stub(->(*_args) { chamou = true }) do
        CalcularFrequenciaJob.perform_now(user.id)
      end

      assert_not chamou
    ensure
      outra_conexao.exec("SELECT pg_advisory_unlock(#{CalcularFrequenciaJob::LOCK_KEY})")
      outra_conexao.close
    end
  end
end
