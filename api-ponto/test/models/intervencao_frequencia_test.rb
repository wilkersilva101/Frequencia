require "test_helper"

class IntervencaoFrequenciaTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @responsavel = users(:two)
  end

  test "valid batida_manual with time_record" do
    time_record = TimeRecord.create!(user: @user, punched_at: Time.zone.now, raw_data: "x", authentication_mode: "manual")

    intervencao = IntervencaoFrequencia.new(
      user: @user,
      responsavel: @responsavel,
      tipo: "batida_manual",
      justificativa: "Esqueceu de bater o ponto",
      momento: Time.zone.now,
      punch_type: "entry",
      time_record: time_record,
      status: "registrado"
    )

    assert intervencao.valid?
  end

  test "valid errata without time_record" do
    intervencao = IntervencaoFrequencia.new(
      user: @user,
      responsavel: @responsavel,
      tipo: "errata",
      justificativa: "Horário registrado errado",
      momento: Time.zone.now,
      status: "pendente"
    )

    assert intervencao.valid?
  end

  test "invalid without justificativa" do
    intervencao = IntervencaoFrequencia.new(
      user: @user,
      responsavel: @responsavel,
      tipo: "errata",
      momento: Time.zone.now,
      status: "pendente"
    )

    assert_not intervencao.valid?
    assert_includes intervencao.errors[:justificativa], "não pode ficar em branco"
  end

  test "invalid with tipo outside allowed list" do
    intervencao = IntervencaoFrequencia.new(
      user: @user,
      responsavel: @responsavel,
      tipo: "outro",
      justificativa: "x",
      momento: Time.zone.now,
      status: "pendente"
    )

    assert_not intervencao.valid?
    assert_includes intervencao.errors[:tipo], "não está incluído na lista"
  end

  test "invalid batida_manual without time_record" do
    intervencao = IntervencaoFrequencia.new(
      user: @user,
      responsavel: @responsavel,
      tipo: "batida_manual",
      justificativa: "x",
      momento: Time.zone.now,
      status: "registrado"
    )

    assert_not intervencao.valid?
    assert_includes intervencao.errors[:time_record], "não pode ficar em branco"
  end

  test "invalid errata with time_record present" do
    time_record = TimeRecord.create!(user: @user, punched_at: Time.zone.now, raw_data: "x", authentication_mode: "manual")

    intervencao = IntervencaoFrequencia.new(
      user: @user,
      responsavel: @responsavel,
      tipo: "errata",
      justificativa: "x",
      momento: Time.zone.now,
      time_record: time_record,
      status: "pendente"
    )

    assert_not intervencao.valid?
    assert_includes intervencao.errors[:time_record], "deve ficar em branco"
  end

  # --- Sprint 19, task 19.2 (UC-09) — desconsiderar/reconsiderar ---

  test "valid desconsideracao_ponto with time_record and justificativa" do
    time_record = TimeRecord.create!(user: @user, punched_at: Time.zone.now, raw_data: "x", authentication_mode: "biometric")

    intervencao = IntervencaoFrequencia.new(
      user: @user,
      responsavel: @responsavel,
      tipo: "desconsideracao_ponto",
      justificativa: "Batida duplicada por falha na estação",
      momento: time_record.punched_at,
      time_record: time_record,
      status: "registrado"
    )

    assert intervencao.valid?
  end

  test "invalid desconsideracao_ponto without time_record" do
    intervencao = IntervencaoFrequencia.new(
      user: @user,
      responsavel: @responsavel,
      tipo: "desconsideracao_ponto",
      justificativa: "x",
      momento: Time.zone.now,
      status: "registrado"
    )

    assert_not intervencao.valid?
    assert_includes intervencao.errors[:time_record], "não pode ficar em branco"
  end

  test "invalid desconsideracao_ponto without justificativa" do
    time_record = TimeRecord.create!(user: @user, punched_at: Time.zone.now, raw_data: "x", authentication_mode: "biometric")

    intervencao = IntervencaoFrequencia.new(
      user: @user,
      responsavel: @responsavel,
      tipo: "desconsideracao_ponto",
      momento: time_record.punched_at,
      time_record: time_record,
      status: "registrado"
    )

    assert_not intervencao.valid?
    assert_includes intervencao.errors[:justificativa], "não pode ficar em branco"
  end

  test "valid reconsideracao_ponto with time_record and without justificativa" do
    time_record = TimeRecord.create!(user: @user, punched_at: Time.zone.now, raw_data: "x", authentication_mode: "biometric")

    intervencao = IntervencaoFrequencia.new(
      user: @user,
      responsavel: @responsavel,
      tipo: "reconsideracao_ponto",
      momento: time_record.punched_at,
      time_record: time_record,
      status: "registrado"
    )

    assert intervencao.valid?
  end

  test "invalid reconsideracao_ponto without time_record" do
    intervencao = IntervencaoFrequencia.new(
      user: @user,
      responsavel: @responsavel,
      tipo: "reconsideracao_ponto",
      momento: Time.zone.now,
      status: "registrado"
    )

    assert_not intervencao.valid?
    assert_includes intervencao.errors[:time_record], "não pode ficar em branco"
  end

  # --- Sprint 19, task 19.3 (UC-10) — autorizar horas extras ---

  test "solicitar_autorizacao_horas_extras cria pedido pendente sem responsavel/justificativa" do
    time_record = TimeRecord.create!(user: @user, punched_at: Time.zone.now, raw_data: "x",
                                      authentication_mode: "biometric", punch_type: "exit")

    intervencao = IntervencaoFrequencia.solicitar_autorizacao_horas_extras(time_record)

    assert intervencao.persisted?
    assert_equal "pendente", intervencao.status
    assert_equal "acumulo_horas_extras", intervencao.tipo
    assert_equal time_record, intervencao.time_record
    assert_nil intervencao.responsavel
    assert_nil intervencao.justificativa
  end

  test "solicitar_autorizacao_horas_extras exige time_record" do
    assert_raises(ActiveRecord::RecordInvalid) do
      IntervencaoFrequencia.solicitar_autorizacao_horas_extras(TimeRecord.new(user: @user))
    end
  end

  test "deferir! marca status aprovado e registra resolvido_por" do
    time_record = TimeRecord.create!(user: @user, punched_at: Time.zone.now, raw_data: "x",
                                      authentication_mode: "biometric", punch_type: "exit")
    intervencao = IntervencaoFrequencia.solicitar_autorizacao_horas_extras(time_record)

    intervencao.deferir!(responsavel: @responsavel)

    assert_equal "aprovado", intervencao.status
    assert_equal @responsavel, intervencao.resolvido_por
  end

  test "indeferir! marca status indeferido e registra resolvido_por" do
    time_record = TimeRecord.create!(user: @user, punched_at: Time.zone.now, raw_data: "x",
                                      authentication_mode: "biometric", punch_type: "exit")
    intervencao = IntervencaoFrequencia.solicitar_autorizacao_horas_extras(time_record)

    intervencao.indeferir!(responsavel: @responsavel)

    assert_equal "indeferido", intervencao.status
    assert_equal @responsavel, intervencao.resolvido_por
  end

  test "deferir! levanta erro claro quando intervencao ja foi resolvida" do
    time_record = TimeRecord.create!(user: @user, punched_at: Time.zone.now, raw_data: "x",
                                      authentication_mode: "biometric", punch_type: "exit")
    intervencao = IntervencaoFrequencia.solicitar_autorizacao_horas_extras(time_record)
    intervencao.deferir!(responsavel: @responsavel)

    assert_raises(IntervencaoFrequencia::ResolucaoInvalidaError) do
      intervencao.indeferir!(responsavel: @responsavel)
    end
  end

  test "deferir! levanta erro claro para intervencao que nunca foi pendente" do
    time_record = TimeRecord.create!(user: @user, punched_at: Time.zone.now, raw_data: "x", authentication_mode: "manual")
    intervencao = IntervencaoFrequencia.create!(
      user: @user,
      responsavel: @responsavel,
      tipo: "batida_manual",
      justificativa: "Esqueceu de bater o ponto",
      momento: Time.zone.now,
      punch_type: "entry",
      time_record: time_record,
      status: "registrado"
    )

    assert_raises(IntervencaoFrequencia::ResolucaoInvalidaError) do
      intervencao.deferir!(responsavel: @responsavel)
    end
  end

  test "invalid acumulo_horas_extras without time_record" do
    intervencao = IntervencaoFrequencia.new(
      user: @user,
      tipo: "acumulo_horas_extras",
      momento: Time.zone.now,
      status: "pendente"
    )

    assert_not intervencao.valid?
    assert_includes intervencao.errors[:time_record], "não pode ficar em branco"
  end

  # --- Sprint 19, task 19.4 (UC-11) — autorizar batida em prédio não permitido ---

  test "solicitar_autorizacao_predio cria pedido pendente sem responsavel/justificativa" do
    estacao = estacoes_ponto(:one)
    time_record = TimeRecord.create!(user: @user, punched_at: Time.zone.now, raw_data: "x",
                                      authentication_mode: "biometric", punch_type: "entry",
                                      estacao_ponto: estacao)

    intervencao = IntervencaoFrequencia.solicitar_autorizacao_predio(time_record, estacao_ponto: estacao)

    assert intervencao.persisted?
    assert_equal "pendente", intervencao.status
    assert_equal "autorizacao_predio", intervencao.tipo
    assert_equal time_record, intervencao.time_record
    assert_nil intervencao.responsavel
    assert_nil intervencao.justificativa
  end

  test "solicitar_autorizacao_predio exige time_record" do
    estacao = estacoes_ponto(:one)

    assert_raises(ActiveRecord::RecordInvalid) do
      IntervencaoFrequencia.solicitar_autorizacao_predio(TimeRecord.new(user: @user), estacao_ponto: estacao)
    end
  end

  test "deferir!/indeferir! funcionam sem alteração pra autorizacao_predio" do
    estacao = estacoes_ponto(:one)
    time_record = TimeRecord.create!(user: @user, punched_at: Time.zone.now, raw_data: "x",
                                      authentication_mode: "biometric", punch_type: "entry",
                                      estacao_ponto: estacao)
    intervencao = IntervencaoFrequencia.solicitar_autorizacao_predio(time_record, estacao_ponto: estacao)

    intervencao.deferir!(responsavel: @responsavel)
    assert_equal "aprovado", intervencao.status
    assert_equal @responsavel, intervencao.resolvido_por

    outra = IntervencaoFrequencia.solicitar_autorizacao_predio(
      TimeRecord.create!(user: @user, punched_at: Time.zone.now, raw_data: "y",
                          authentication_mode: "biometric", punch_type: "entry", estacao_ponto: estacao),
      estacao_ponto: estacao
    )
    outra.indeferir!(responsavel: @responsavel)
    assert_equal "indeferido", outra.status
    assert_equal @responsavel, outra.resolvido_por
  end

  test "invalid desconsideracao_predio without time_record" do
    intervencao = IntervencaoFrequencia.new(
      user: @user,
      responsavel: @responsavel,
      tipo: "desconsideracao_predio",
      justificativa: "x",
      momento: Time.zone.now,
      status: "registrado"
    )

    assert_not intervencao.valid?
    assert_includes intervencao.errors[:time_record], "não pode ficar em branco"
  end

  test "invalid autorizacao_predio without time_record" do
    intervencao = IntervencaoFrequencia.new(
      user: @user,
      tipo: "autorizacao_predio",
      momento: Time.zone.now,
      status: "pendente"
    )

    assert_not intervencao.valid?
    assert_includes intervencao.errors[:time_record], "não pode ficar em branco"
  end
end
