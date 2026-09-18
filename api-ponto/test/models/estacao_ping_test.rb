require "test_helper"

class EstacaoPingTest < ActiveSupport::TestCase
  test "valid with estacao_ponto" do
    ping = EstacaoPing.new(estacao_ponto: estacoes_ponto(:one))
    assert ping.valid?
  end

  test "invalid without estacao_ponto" do
    ping = EstacaoPing.new
    assert_not ping.valid?
    assert_includes ping.errors[:estacao_ponto], "não pode ficar em branco"
  end

  test "persists all fields" do
    ping = EstacaoPing.create!(
      estacao_ponto: estacoes_ponto(:one),
      ip: "10.0.0.9",
      momento: Time.zone.now,
      versao: "2.1.0"
    )
    ping.reload

    assert_equal "10.0.0.9", ping.ip
    assert_equal "2.1.0", ping.versao
    assert_not_nil ping.momento
  end

  test "usa a tabela estacao_pings" do
    assert_equal "estacao_pings", EstacaoPing.table_name
  end

  test "belongs to estacao_ponto" do
    estacao = estacoes_ponto(:one)
    ping = EstacaoPing.create!(estacao_ponto: estacao)

    assert_equal estacao, ping.estacao_ponto
    assert_includes estacao.estacao_pings, ping
  end
end
