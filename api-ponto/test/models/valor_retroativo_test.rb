require "test_helper"

class ValorRetroativoTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  test "valido com user/ano/mes/data_geracao/numero_hora" do
    valor = ValorRetroativo.new(
      user: @user, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 10
    )

    assert valor.valid?
  end

  test "invalido sem mes" do
    valor = ValorRetroativo.new(user: @user, ano: 2026, data_geracao: Time.current, numero_hora: 10)
    assert_not valor.valid?
  end

  test "mes fora de 1..12 e invalido" do
    valor = ValorRetroativo.new(
      user: @user, ano: 2026, mes: 13, data_geracao: Time.current, numero_hora: 10
    )

    assert_not valor.valid?
  end

  test "invalido sem numero_hora" do
    valor = ValorRetroativo.new(user: @user, ano: 2026, mes: 9, data_geracao: Time.current)
    assert_not valor.valid?
  end

  test "usuario pode ter multiplos valores retroativos no mesmo mes/ano (sem OneToOne)" do
    ValorRetroativo.create!(user: @user, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 5)
    segundo = ValorRetroativo.new(user: @user, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 7)

    assert segundo.valid?
    assert_nothing_raised { segundo.save! }
    assert_equal 2, ValorRetroativo.where(user: @user, ano: 2026, mes: 9).count
  end

  # Teste principal desta task (18.3): prova que a correção do bug DUV-011
  # soma TODOS os valores do mes/ano, não fica só com o ultimo (o
  # comportamento real do legado, por causa do `cont=+valor` em vez de
  # `cont+=valor` — ver comentario de `.soma_do_mes`).
  test "soma_do_mes soma todos os valores retroativos do usuario no mes/ano, nao so o ultimo" do
    ValorRetroativo.create!(user: @user, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 3)
    ValorRetroativo.create!(user: @user, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 5)
    ValorRetroativo.create!(user: @user, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 8)

    # soma real esperada: 3 + 5 + 8 = 16.
    # se o bug do legado fosse replicado (cont=+valor), o resultado seria
    # apenas o ultimo valor do loop (8), nao a soma.
    assert_equal 16, ValorRetroativo.soma_do_mes(@user, 2026, 9)
    assert_not_equal 8, ValorRetroativo.soma_do_mes(@user, 2026, 9)
  end

  test "soma_do_mes retorna zero quando usuario nao tem valor retroativo no mes" do
    assert_equal 0, ValorRetroativo.soma_do_mes(@user, 2026, 9)
  end

  test "soma_do_mes nao inclui valores de outro mes/ano" do
    ValorRetroativo.create!(user: @user, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 10)
    ValorRetroativo.create!(user: @user, ano: 2026, mes: 8, data_geracao: Time.current, numero_hora: 100)
    ValorRetroativo.create!(user: @user, ano: 2025, mes: 9, data_geracao: Time.current, numero_hora: 100)

    assert_equal 10, ValorRetroativo.soma_do_mes(@user, 2026, 9)
  end

  test "soma_do_mes nao inclui valores de outro usuario" do
    outro_user = users(:two)
    ValorRetroativo.create!(user: @user, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 10)
    ValorRetroativo.create!(user: outro_user, ano: 2026, mes: 9, data_geracao: Time.current, numero_hora: 100)

    assert_equal 10, ValorRetroativo.soma_do_mes(@user, 2026, 9)
  end
end
