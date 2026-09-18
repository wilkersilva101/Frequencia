require "test_helper"

class RetificadorBancoHorasTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  test "válido com user/ano/mes/tipo/segundos_a_retificar" do
    retificador = RetificadorBancoHoras.new(
      user: @user, ano: 2026, mes: 9,
      tipo: RetificadorBancoHoras::CREDITO_POR_TRABALHO_EXCEPCIONAL,
      segundos_a_retificar: 3600
    )

    assert retificador.valid?
  end

  test "responsavel é opcional" do
    retificador = RetificadorBancoHoras.new(
      user: @user, ano: 2026, mes: 9,
      tipo: RetificadorBancoHoras::CREDITO_POR_TRABALHO_EXCEPCIONAL,
      segundos_a_retificar: 3600
    )

    assert_nil retificador.responsavel
    assert retificador.valid?
  end

  test "mes fora de 1..12 é inválido" do
    retificador = RetificadorBancoHoras.new(
      user: @user, ano: 2026, mes: 13,
      tipo: RetificadorBancoHoras::CREDITO_POR_TRABALHO_EXCEPCIONAL,
      segundos_a_retificar: 3600
    )

    assert_not retificador.valid?
  end

  test "tipo fora de TIPOS_DISPONIVEIS é inválido" do
    retificador = RetificadorBancoHoras.new(
      user: @user, ano: 2026, mes: 9, tipo: "TIPO_INEXISTENTE", segundos_a_retificar: 3600
    )

    assert_not retificador.valid?
  end

  test "fator_multiplicacao é +1 para os 4 tipos de crédito" do
    %w[
      CREDITO_POR_DESCONTO_EM_FOLHA
      CREDITO_POR_TRABALHO_EXCEPCIONAL
      CREDITO_POR_DEBITO_INDEVIDO
      CREDITO_POR_DEBITO_EM_OUTRO_MES
    ].each do |tipo|
      retificador = RetificadorBancoHoras.new(tipo: tipo)
      assert_equal 1, retificador.fator_multiplicacao, "esperava fator +1 para #{tipo}"
    end
  end

  test "fator_multiplicacao é -1 para os 3 tipos de débito" do
    %w[
      DEBITO_POR_CREDITO_INDEVIDO
      DEBITO_POR_CREDITO_EM_OUTRO_MES
      DEBITO_PARA_COMPENSACAO
    ].each do |tipo|
      retificador = RetificadorBancoHoras.new(tipo: tipo)
      assert_equal(-1, retificador.fator_multiplicacao, "esperava fator -1 para #{tipo}")
    end
  end

  test "excluir! marca excluido = true sem apagar o registro" do
    retificador = RetificadorBancoHoras.create!(
      user: @user, ano: 2026, mes: 9,
      tipo: RetificadorBancoHoras::DEBITO_PARA_COMPENSACAO, segundos_a_retificar: 1800
    )

    retificador.excluir!

    assert retificador.reload.excluido?
    assert RetificadorBancoHoras.exists?(retificador.id)
  end
end
