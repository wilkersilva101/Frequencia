require "test_helper"

class RegistroManualFrequenciaServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @responsavel = users(:two)
    @momento = Time.zone.local(2026, 9, 1, 8, 0, 0)
  end

  test "batida_manual cria TimeRecord real e IntervencaoFrequencia registrada" do
    assert_difference [ "TimeRecord.count", "IntervencaoFrequencia.count" ], 1 do
      @intervencao = RegistroManualFrequenciaService.registrar(
        user: @user,
        responsavel: @responsavel,
        tipo: "batida_manual",
        momento: @momento,
        punch_type: "entry",
        justificativa: "Esqueceu de bater o ponto na maquininha"
      )
    end

    assert_equal "registrado", @intervencao.status
    assert @intervencao.time_record.present?
    assert_equal @user, @intervencao.time_record.user
    assert_equal "manual", @intervencao.time_record.authentication_mode
    assert_equal "entry", @intervencao.time_record.punch_type
    assert_equal @momento, @intervencao.time_record.punched_at
  end

  test "errata registra apenas a solicitacao pendente, sem criar TimeRecord" do
    assert_difference "IntervencaoFrequencia.count", 1 do
      assert_no_difference "TimeRecord.count" do
        @intervencao = RegistroManualFrequenciaService.registrar(
          user: @user,
          responsavel: @responsavel,
          tipo: "errata",
          momento: @momento,
          punch_type: "exit",
          justificativa: "Horário de saída registrado errado pela máquina"
        )
      end
    end

    assert_equal "pendente", @intervencao.status
    assert_nil @intervencao.time_record
  end

  test "sem justificativa levanta erro de validação" do
    assert_raises ActiveRecord::RecordInvalid do
      RegistroManualFrequenciaService.registrar(
        user: @user,
        responsavel: @responsavel,
        tipo: "errata",
        momento: @momento,
        justificativa: ""
      )
    end
  end

  test "batida_manual registra responsavel e justificativa na intervencao" do
    intervencao = RegistroManualFrequenciaService.registrar(
      user: @user,
      responsavel: @responsavel,
      tipo: "batida_manual",
      momento: @momento,
      punch_type: "entry",
      justificativa: "Máquina biométrica estava com defeito"
    )

    assert_equal @responsavel, intervencao.responsavel
    assert_equal "Máquina biométrica estava com defeito", intervencao.justificativa
  end
end
