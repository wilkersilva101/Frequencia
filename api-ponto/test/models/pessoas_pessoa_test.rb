require "test_helper"

# Roda contra o schema real do espelho (ADR-0006): `bin/rails test:pessoas_schema:load`.
class PessoasPessoaTest < ActiveSupport::TestCase
  include PessoasEspelhoHelper

  # Débito B1: em CI/máquina limpos sem o schema do espelho, PULA em vez de
  # explodir com PG::UndefinedTable (ver `skip_sem_espelho!`).
  setup { skip_sem_espelho! }

  UserDouble = Struct.new(:cpf)

  test "finds a person by the normalized user CPF" do
    pessoa = criar_pessoa(nome: "Maria", cpf: "12345678901")
    criar_pessoa(nome: "Outra", cpf: "12345678902")

    assert_equal pessoa, Pessoas::Pessoa.por_user(UserDouble.new("123.456.789-01"))
  end

  test "returns nil when no person has the user CPF" do
    criar_pessoa(cpf: "12345678901")

    assert_nil Pessoas::Pessoa.por_user(UserDouble.new("999.999.999-99"))
  end

  test "returns nil without querying when user is nil or has no CPF" do
    criar_pessoa(cpf: "12345678901")

    assert_no_queries do
      assert_nil Pessoas::Pessoa.por_user(nil)
      assert_nil Pessoas::Pessoa.por_user(UserDouble.new(nil))
      assert_nil Pessoas::Pessoa.por_user(UserDouble.new(""))
      assert_nil Pessoas::Pessoa.por_user(UserDouble.new("---"))
    end
  end
end
