require "test_helper"

# Tarefa 29.7 (Sprint 29) — testes da feature flag `FREQUENCIA_AUTORIZACAO_CASCATA`
# (Decisão D3 do CTO, 2026-10-02) e do log do modo shadow.
#
# ⚠️ A variável de ambiente é ESTADO GLOBAL do processo. `parallelize` roda
# vários arquivos no MESMO worker em sequência — um `ENV[...]` deixado para trás
# contaminaria os testes seguintes (é o mesmo vetor das lições de stub de classe
# em docs/governance/lessons.md). Por isso TODO teste aqui usa o helper
# `com_flag`, que restaura o valor anterior no `ensure`.
class FrequenciaAutorizacaoCascataTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------- parsing

  test "ausente e desconhecido caem em :off (default de producao)" do
    com_flag(nil) { assert_equal :off, FrequenciaAutorizacaoCascata.modo }
    com_flag("") { assert_equal :off, FrequenciaAutorizacaoCascata.modo }
    com_flag("desligada") { assert_equal :off, FrequenciaAutorizacaoCascata.modo }
    com_flag("off") { assert_equal :off, FrequenciaAutorizacaoCascata.modo }
  end

  test "valores de ligada ativam :on e ligada?" do
    %w[on 1 true ligada ON Ligada].each do |valor|
      com_flag(valor) do
        assert_equal :on, FrequenciaAutorizacaoCascata.modo, "valor #{valor.inspect}"
        assert FrequenciaAutorizacaoCascata.ligada?
        refute FrequenciaAutorizacaoCascata.shadow?
      end
    end
  end

  test "valores de shadow ativam :shadow sem negar (ligada? falso)" do
    %w[shadow sombra SHADOW].each do |valor|
      com_flag(valor) do
        assert_equal :shadow, FrequenciaAutorizacaoCascata.modo, "valor #{valor.inspect}"
        assert FrequenciaAutorizacaoCascata.shadow?
        refute FrequenciaAutorizacaoCascata.ligada?
      end
    end
  end

  # ------------------------------------------------------------- log shadow

  test "log_shadow emite usuario, alvo, motivo e decisao apenas no modo shadow" do
    usuario = User.new(nome_completo: "Gestor Shadow")
    alvo = User.new(id: 42, nome_completo: "Alvo Shadow", cpf: "111.222.333-44")

    logger = RecordingLogger.new

    com_flag("shadow") do
      with_logger(logger) do
        FrequenciaAutorizacaoCascata.log_shadow(
          usuario: usuario, alvo: alvo, motivo: :negado, decisao: :negaria
        )
      end
    end

    entrada = logger.entradas.find { |e| e[:evento] == "frequencia_autorizacao_cascata.shadow" }
    assert entrada, "deveria ter logado o evento de shadow"
    assert_equal :negado, entrada[:motivo]
    assert_equal :negaria, entrada[:decisao]
    assert_equal 42, entrada[:alvo_id]
    assert_equal "11122233344", entrada[:alvo_cpf], "CPF do alvo normalizado no log"
    assert_equal "User", entrada[:alvo_tipo]
  end

  test "log_shadow NAO emite com a flag off nem on (so observa em shadow)" do
    usuario = User.new(nome_completo: "Gestor")
    alvo = User.new(id: 7)

    %w[__unset__ on].each do |valor|
      logger = RecordingLogger.new
      com_flag(valor == "__unset__" ? nil : valor) do
        with_logger(logger) do
          FrequenciaAutorizacaoCascata.log_shadow(usuario: usuario, alvo: alvo, motivo: :negado, decisao: :negaria)
        end
      end
      assert_empty logger.entradas, "nao deveria logar shadow com a flag #{valor.inspect}"
    end
  end

  # ------------------------------------------------------------- log negacao (:on)

  test "log_negacao emite o evento de negacao apenas com a flag on" do
    usuario = User.new(nome_completo: "Gestor On")
    alvo = User.new(id: 42, nome_completo: "Alvo On", cpf: "111.222.333-44")

    logger = RecordingLogger.new
    com_flag("on") do
      with_logger(logger) do
        FrequenciaAutorizacaoCascata.log_negacao(
          usuario: usuario, alvo: alvo, motivo: :negado, decisao: :negaria
        )
      end
    end

    entrada = logger.entradas.find { |e| e[:evento] == "frequencia_autorizacao_cascata.negacao" }
    assert entrada, "deveria ter logado o evento de negacao no modo on"
    assert_equal :negado, entrada[:motivo]
    assert_equal :negaria, entrada[:decisao]
    assert_equal 42, entrada[:alvo_id]
    assert_equal "11122233344", entrada[:alvo_cpf], "CPF do alvo normalizado no log"
    assert_equal "User", entrada[:alvo_tipo]
  end

  test "log_negacao NAO emite com a flag off nem shadow" do
    usuario = User.new(nome_completo: "Gestor")
    alvo = User.new(id: 7)

    %w[__unset__ shadow].each do |valor|
      logger = RecordingLogger.new
      com_flag(valor == "__unset__" ? nil : valor) do
        with_logger(logger) do
          FrequenciaAutorizacaoCascata.log_negacao(usuario: usuario, alvo: alvo, motivo: :negado)
        end
      end
      assert_empty logger.entradas, "nao deveria logar negacao com a flag #{valor.inspect}"
    end
  end

  test "shadow e on usam eventos DISTINTOS (comparaveis linha a linha)" do
    usuario = User.new(nome_completo: "Gestor")
    alvo = User.new(id: 7)

    logger = RecordingLogger.new
    with_logger(logger) do
      com_flag("shadow") do
        FrequenciaAutorizacaoCascata.log_shadow(usuario: usuario, alvo: alvo, motivo: :negado, decisao: :negaria)
      end
      com_flag("on") do
        FrequenciaAutorizacaoCascata.log_negacao(usuario: usuario, alvo: alvo, motivo: :negado)
      end
    end

    eventos = logger.entradas.map { |e| e[:evento] }
    assert_includes eventos, "frequencia_autorizacao_cascata.shadow"
    assert_includes eventos, "frequencia_autorizacao_cascata.negacao"
    refute_equal FrequenciaAutorizacaoCascata::EVENTO_SHADOW, FrequenciaAutorizacaoCascata::EVENTO_NEGACAO
  end

  private

  # Executa o bloco com `FREQUENCIA_AUTORIZACAO_CASCATA` = `valor` e restaura o
  # valor anterior (inclusive `nil`) no `ensure` — nunca vaza para outros testes
  # do mesmo worker.
  def com_flag(valor)
    anterior = ENV[FrequenciaAutorizacaoCascata::VARIAVEL]
    if valor.nil?
      ENV.delete(FrequenciaAutorizacaoCascata::VARIAVEL)
    else
      ENV[FrequenciaAutorizacaoCascata::VARIAVEL] = valor
    end
    yield
  ensure
    if anterior.nil?
      ENV.delete(FrequenciaAutorizacaoCascata::VARIAVEL)
    else
      ENV[FrequenciaAutorizacaoCascata::VARIAVEL] = anterior
    end
  end

  # Troca o `Rails.logger` por um coletor e restaura no `ensure`.
  def with_logger(logger)
    anterior = Rails.logger
    Rails.logger = logger
    yield
  ensure
    Rails.logger = anterior
  end

  # Logger mínimo que guarda os payloads (hash) passados a `info`.
  class RecordingLogger
    def initialize
      @entradas = []
    end

    def info(payload = nil)
      @entradas << payload if payload.is_a?(Hash)
    end

    def warn(*); end
    def debug(*); end
    def error(*); end
    def fatal(*); end
    def level(*); end

    def entradas
      @entradas
    end
  end
end
