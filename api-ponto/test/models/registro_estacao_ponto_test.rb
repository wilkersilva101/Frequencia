require "test_helper"

class RegistroEstacaoPontoTest < ActiveSupport::TestCase
  test "valid with estacao_ponto and processado" do
    registro = RegistroEstacaoPonto.new(estacao_ponto: estacoes_ponto(:one), processado: false)
    assert registro.valid?
  end

  test "invalid without estacao_ponto" do
    registro = RegistroEstacaoPonto.new(processado: false)
    assert_not registro.valid?
    assert_includes registro.errors[:estacao_ponto], "não pode ficar em branco"
  end

  test "persists all fields" do
    registro = RegistroEstacaoPonto.create!(
      estacao_ponto: estacoes_ponto(:one),
      arquivo_criptografado: "conteudo-cifrado",
      momento_processamento: Time.zone.now,
      momento_sinc: Time.zone.now,
      processado: true,
      ip: "10.0.0.5"
    )
    registro.reload

    assert_equal "conteudo-cifrado", registro.arquivo_criptografado
    assert registro.processado
    assert_equal "10.0.0.5", registro.ip
  end

  test "usa a tabela registro_estacao_pontos" do
    assert_equal "registro_estacao_pontos", RegistroEstacaoPonto.table_name
  end

  test "belongs to estacao_ponto" do
    estacao = estacoes_ponto(:one)
    registro = RegistroEstacaoPonto.create!(estacao_ponto: estacao, processado: false)

    assert_equal estacao, registro.estacao_ponto
    assert_includes estacao.registro_estacao_pontos, registro
  end
end
