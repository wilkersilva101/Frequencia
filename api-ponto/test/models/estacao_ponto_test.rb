require "test_helper"

class EstacaoPontoTest < ActiveSupport::TestCase
  # --- Validations ---

  test "valid with descricao and cod_ativacao" do
    estacao = EstacaoPonto.new(descricao: "Estacao Nova", cod_ativacao: "cod-novo-001")
    assert estacao.valid?
  end

  test "invalid without descricao" do
    estacao = EstacaoPonto.new(cod_ativacao: "cod-sem-descricao")
    assert_not estacao.valid?
    assert_includes estacao.errors[:descricao], "não pode ficar em branco"
  end

  test "invalid without cod_ativacao" do
    estacao = EstacaoPonto.new(descricao: "Sem Cod Ativacao")
    assert_not estacao.valid?
    assert_includes estacao.errors[:cod_ativacao], "não pode ficar em branco"
  end

  test "invalid with duplicated cod_ativacao (case insensitive)" do
    existing = EstacaoPonto.find_by!(cod_ativacao: "poc-ativacao-001")
    estacao = EstacaoPonto.new(descricao: "Duplicada", cod_ativacao: existing.cod_ativacao.upcase)
    assert_not estacao.valid?
    assert_includes estacao.errors[:cod_ativacao], "já está em uso"
  end

  test "valid with optional fields blank" do
    estacao = EstacaoPonto.new(descricao: "Minima", cod_ativacao: "cod-minimo-001")
    assert estacao.valid?
    assert_nil estacao.versao
    assert_nil estacao.ultimo_contato
    assert_nil estacao.vnc
    assert_nil estacao.anydesk
    assert_nil estacao.teamviewer
    assert_nil estacao.observacao
  end

  # --- Persistence ---

  test "persists all grid fields" do
    estacao = EstacaoPonto.create!(
      descricao: "Estacao Completa",
      versao: "2.1.0",
      ultimo_contato: Time.zone.now,
      vnc: "10.0.0.1:5900",
      anydesk: "999 888 777",
      teamviewer: "111 000 999",
      observacao: "Observacao de teste",
      cod_ativacao: "cod-completo-001"
    )
    estacao.reload

    assert_equal "Estacao Completa", estacao.descricao
    assert_equal "2.1.0", estacao.versao
    assert_equal "10.0.0.1:5900", estacao.vnc
    assert_equal "999 888 777", estacao.anydesk
    assert_equal "111 000 999", estacao.teamviewer
    assert_equal "Observacao de teste", estacao.observacao
    assert_equal "cod-completo-001", estacao.cod_ativacao
  end

  # --- Campos replicados do legado Intranet (pedido direto, 2026-09-02) ---

  test "persists legacy structure fields" do
    estacao = EstacaoPonto.create!(
      descricao: "Estacao Legado",
      cod_ativacao: "cod-legado-001",
      codigo_unico_maquina: "AA:BB:CC:DD:EE:FF",
      momento_inicio: Date.new(2026, 1, 1),
      momento_fim: Date.new(2026, 12, 31),
      liberado_batida_manual: true
    )
    estacao.reload

    assert_equal "AA:BB:CC:DD:EE:FF", estacao.codigo_unico_maquina
    assert_equal Date.new(2026, 1, 1), estacao.momento_inicio
    assert_equal Date.new(2026, 12, 31), estacao.momento_fim
    assert estacao.liberado_batida_manual
    assert estacao.ativo
  end

  test "ativo and liberado_batida_manual default correctly" do
    estacao = EstacaoPonto.create!(descricao: "Estacao Defaults", cod_ativacao: "cod-defaults-001")

    assert estacao.ativo
    assert_not estacao.liberado_batida_manual
  end

  test "has_many registro_estacao_pontos and estacao_pings" do
    estacao = estacoes_ponto(:one)
    registro = RegistroEstacaoPonto.create!(estacao_ponto: estacao, processado: false)
    ping = EstacaoPing.create!(estacao_ponto: estacao)

    assert_includes estacao.registro_estacao_pontos, registro
    assert_includes estacao.estacao_pings, ping
  end

  # --- codigo_ativacao_valido? (Sprint 1, Task 1.4) ---

  test "codigo_ativacao_valido? is true for a registered station (case insensitive)" do
    assert EstacaoPonto.codigo_ativacao_valido?("poc-ativacao-001")
    assert EstacaoPonto.codigo_ativacao_valido?("POC-ATIVACAO-001")
  end

  test "codigo_ativacao_valido? is false for an unregistered code" do
    assert_not EstacaoPonto.codigo_ativacao_valido?("codigo-desconhecido")
  end

  test "codigo_ativacao_valido? is false for blank code" do
    assert_not EstacaoPonto.codigo_ativacao_valido?(nil)
    assert_not EstacaoPonto.codigo_ativacao_valido?("")
  end

  test "codigo_ativacao_valido? is true for the unsupported-OS sentinel" do
    assert EstacaoPonto.codigo_ativacao_valido?("SistemaOperacionalNaoSuportado")
  end

  # --- registrar_contato (Sprint 1, Task 1.4) ---

  test "registrar_contato updates ultimo_contato and versao for a known station" do
    estacao = estacoes_ponto(:one)
    estacao_atualizada = EstacaoPonto.registrar_contato(estacao.cod_ativacao, versao: "2.0.0")

    assert_equal estacao.id, estacao_atualizada.id
    assert_equal "2.0.0", estacao_atualizada.versao
    assert_in_delta Time.current, estacao_atualizada.ultimo_contato, 5.seconds
  end

  test "registrar_contato keeps existing versao when versao is not informed" do
    estacao = estacoes_ponto(:one)
    versao_anterior = estacao.versao

    estacao_atualizada = EstacaoPonto.registrar_contato(estacao.cod_ativacao)

    assert_equal versao_anterior, estacao_atualizada.versao
  end

  test "registrar_contato returns nil for unknown code" do
    assert_nil EstacaoPonto.registrar_contato("codigo-desconhecido")
  end

  test "registrar_contato returns nil for the unsupported-OS sentinel" do
    assert_nil EstacaoPonto.registrar_contato("SistemaOperacionalNaoSuportado")
  end
end
