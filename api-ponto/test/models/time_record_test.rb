require "test_helper"

class TimeRecordTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  # --- Column punch_type ---

  test "punch_type column exists and can be nil" do
    record = TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric"
    )
    assert_nil record.punch_type
  end

  test "punch_type can store entry" do
    record = TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric",
      punch_type: "entry"
    )
    assert_equal "entry", record.punch_type
  end

  test "punch_type can store exit" do
    record = TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric",
      punch_type: "exit"
    )
    assert_equal "exit", record.punch_type
  end

  # --- Validation ---

  test "validates punch_type inclusion in entry or exit" do
    record = TimeRecord.new(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric",
      punch_type: "invalid"
    )
    assert_not record.valid?
    assert_includes record.errors[:punch_type], "não está incluído na lista"
  end

  test "validates punch_type allows nil" do
    record = TimeRecord.new(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric",
      punch_type: nil
    )
    assert record.valid?
  end

  test "validates punch_type accepts entry" do
    record = TimeRecord.new(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric",
      punch_type: "entry"
    )
    assert record.valid?
  end

  test "validates punch_type accepts exit" do
    record = TimeRecord.new(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric",
      punch_type: "exit"
    )
    assert record.valid?
  end

  # --- Column punch_type_explicit (Task R.5) ---

  test "punch_type_explicit defaults to false for historical/new records" do
    record = TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric",
      punch_type: "entry"
    )
    assert_equal false, record.punch_type_explicit
  end

  test "punch_type_explicit can be set to true" do
    record = TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric",
      punch_type: "exit",
      punch_type_explicit: true
    )
    assert_equal true, record.punch_type_explicit
  end

  # --- Scope by_date ---

  test "scope by_date returns records for the given date" do
    date = Date.new(2026, 7, 22)

    TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: date.midday,
      authentication_mode: "biometric"
    )

    TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-23 08:00:00",
      punched_at: Date.new(2026, 7, 23).midday,
      authentication_mode: "biometric"
    )

    result = TimeRecord.by_date(date)
    assert_equal 1, result.count
  end

  test "scope by_date returns empty when no records match" do
    result = TimeRecord.by_date(Date.new(2025, 1, 1))
    assert_empty result
  end

  # --- Scope last_today ---

  test "scope last_today returns the most recent record for user today" do
    now = Time.zone.now
    earlier_today = now - 2.hours

    record_earlier = TimeRecord.create!(
      user: @user,
      raw_data: "earlier",
      punched_at: earlier_today,
      authentication_mode: "biometric"
    )

    record_later = TimeRecord.create!(
      user: @user,
      raw_data: "later",
      punched_at: now,
      authentication_mode: "biometric"
    )

    result = TimeRecord.last_today(@user.id)
    assert_equal record_later, result
    assert_equal "later", result.raw_data
  end

  test "scope last_today returns nil if no records exist today" do
    result = TimeRecord.last_today(@user.id)
    assert_nil result
  end

  test "scope last_today respects user_id filter" do
    user_two = users(:two)
    now = Time.zone.now

    TimeRecord.create!(
      user: user_two,
      raw_data: "user two record",
      punched_at: now,
      authentication_mode: "biometric"
    )

    result = TimeRecord.last_today(@user.id)
    assert_nil result
  end

  test "scope last_today orders by punched_at desc and created_at desc" do
    now = Time.zone.now

    first_record = TimeRecord.create!(
      user: @user,
      raw_data: "first",
      punched_at: now - 1.hour,
      authentication_mode: "biometric"
    )

    second_record = TimeRecord.create!(
      user: @user,
      raw_data: "second",
      punched_at: now,
      authentication_mode: "biometric"
    )

    result = TimeRecord.last_today(@user.id)
    assert_equal second_record, result
    assert_equal "second", result.raw_data
  end

  # --- Associação estacao_ponto (Sprint 13, task 13.1) ---

  test "belongs_to estacao_ponto e eh opcional" do
    record = TimeRecord.new(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric"
    )
    assert record.valid?
    assert_nil record.estacao_ponto
  end

  test "pode ser associado a uma estacao_ponto real" do
    estacao = estacoes_ponto(:one)

    record = TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric",
      estacao_ponto: estacao
    )

    assert_equal estacao, record.reload.estacao_ponto
  end

  # --- desconsiderar!/reconsiderar! (Sprint 19, task 19.2, UC-09) ---

  test "desconsiderar! marca desconsiderado e ressalva e cria intervencao registrada" do
    responsavel = users(:two)
    record = TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.local(2026, 7, 22, 8, 0, 0),
      authentication_mode: "biometric"
    )

    record.desconsiderar!(justificativa: "Batida duplicada por falha na estação", responsavel: responsavel)
    record.reload

    assert record.desconsiderado
    assert record.ressalva

    intervencao = IntervencaoFrequencia.find_by(time_record: record, tipo: "desconsideracao_ponto")
    assert intervencao
    assert_equal "registrado", intervencao.status
    assert_equal "Batida duplicada por falha na estação", intervencao.justificativa
    assert_equal @user, intervencao.user
    assert_equal responsavel, intervencao.responsavel
  end

  test "desconsiderar! exige justificativa" do
    record = TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric"
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      record.desconsiderar!(justificativa: nil, responsavel: users(:two))
    end

    record.reload
    assert_not record.desconsiderado
    assert_not record.ressalva
  end

  test "reconsiderar! desfaz desconsiderar! e cria intervencao propria" do
    responsavel = users(:two)
    record = TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.local(2026, 7, 22, 8, 0, 0),
      authentication_mode: "biometric"
    )
    record.desconsiderar!(justificativa: "Batida duplicada", responsavel: responsavel)

    record.reconsiderar!(responsavel: responsavel)
    record.reload

    assert_not record.desconsiderado
    assert_not record.ressalva

    intervencao = IntervencaoFrequencia.find_by(time_record: record, tipo: "reconsideracao_ponto")
    assert intervencao
    assert_equal "registrado", intervencao.status
    assert_nil intervencao.justificativa
  end

  test "reconsiderar! em registro nunca desconsiderado nao quebra" do
    record = TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric"
    )

    assert_nothing_raised do
      record.reconsiderar!(responsavel: users(:two))
    end

    record.reload
    assert_not record.desconsiderado
    assert_not record.ressalva
  end

  # --- desconsiderar_por_predio! (Sprint 19, task 19.4, UC-11) ---

  test "desconsiderar_por_predio! marca desconsiderado e ressalva e cria intervencao com justificativa padrao" do
    responsavel = users(:two)
    estacao = estacoes_ponto(:one)
    record = TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.local(2026, 7, 22, 8, 0, 0),
      authentication_mode: "biometric",
      estacao_ponto: estacao
    )

    record.desconsiderar_por_predio!(estacao_ponto: estacao, responsavel: responsavel)
    record.reload

    assert record.desconsiderado
    assert record.ressalva

    intervencao = IntervencaoFrequencia.find_by(time_record: record, tipo: "desconsideracao_predio")
    assert intervencao
    assert_equal "registrado", intervencao.status
    assert_equal "Ponto desconsiderado: servidor bateu na estação #{estacao.descricao}, prédio não autorizado",
                 intervencao.justificativa
    assert_equal @user, intervencao.user
    assert_equal responsavel, intervencao.responsavel
  end

  test "desconsiderar_por_predio! aceita justificativa customizada" do
    responsavel = users(:two)
    estacao = estacoes_ponto(:one)
    record = TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric",
      estacao_ponto: estacao
    )

    record.desconsiderar_por_predio!(estacao_ponto: estacao, responsavel: responsavel, justificativa: "Motivo customizado")

    intervencao = IntervencaoFrequencia.find_by(time_record: record, tipo: "desconsideracao_predio")
    assert_equal "Motivo customizado", intervencao.justificativa
  end

  # --- Associação intervencoes_frequencia (Sprint 19, task 19.5 — auditoria) ---
  #
  # `TimeRecord#intervencoes_frequencia` é `has_many` (não `has_one`,
  # decisão documentada no topo do model) porque um mesmo registro pode
  # acumular mais de uma intervenção ao longo do tempo (ex.: desconsiderado
  # e depois reconsiderado). Nenhum teste existente verificava a associação
  # em si (só `IntervencaoFrequencia.find_by` isolado) — este cobre o
  # acúmulo de fato.

  test "TimeRecord acumula multiplas IntervencaoFrequencia ao longo do tempo (has_many, nao has_one)" do
    responsavel = users(:two)
    record = TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.local(2026, 7, 22, 8, 0, 0),
      authentication_mode: "biometric"
    )

    record.desconsiderar!(justificativa: "Batida duplicada", responsavel: responsavel)
    record.reload.reconsiderar!(responsavel: responsavel)

    assert_equal 2, record.intervencoes_frequencia.count
    assert_equal %w[desconsideracao_ponto reconsideracao_ponto], record.intervencoes_frequencia.order(:created_at).pluck(:tipo)
  end

  test "destruir o TimeRecord anula time_record_id nas intervencoes associadas, sem apagar o historico (dependent: nullify)" do
    responsavel = users(:two)
    record = TimeRecord.create!(
      user: @user,
      raw_data: "2026-07-22 08:00:00",
      punched_at: Time.zone.now,
      authentication_mode: "biometric"
    )
    record.desconsiderar!(justificativa: "Batida duplicada", responsavel: responsavel)
    intervencao = record.intervencoes_frequencia.sole

    record.destroy!

    assert IntervencaoFrequencia.exists?(intervencao.id)
    assert_nil intervencao.reload.time_record_id
  end
end
