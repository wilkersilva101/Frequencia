require "test_helper"

# Garante que os helpers do espelho produzem dados que os scopes reais leem e
# que tudo roda dentro da transação do teste (ADR-0006, regra 4).
class PessoasEspelhoHelperTest < ActiveSupport::TestCase
  include PessoasEspelhoHelper

  # Débito B1: em CI/máquina limpos sem o schema do espelho, PULA em vez de
  # explodir com PG::UndefinedTable (ver `skip_sem_espelho!`).
  setup { skip_sem_espelho! }

  test "runs inside an open transaction on the pessoas connection" do
    criar_pessoa

    assert PessoasRecord.connection.transaction_open?
  end

  test "builds ancestry as a materialized path from the root" do
    arvore = criar_arvore_unidades

    assert_nil arvore[:raiz].ancestry
    assert_equal arvore[:raiz].id.to_s, arvore[:intermediaria].ancestry
    assert_equal "#{arvore[:raiz].id}/#{arvore[:intermediaria].id}", arvore[:folha].ancestry
  end

  test "creates a person with an active vinculo and a current principal lotacao" do
    unidade = criar_unidade
    pessoa = criar_pessoa_lotada(unidade: unidade, matricula: "12345")

    vinculo = pessoa.vinculos_ativos.sole
    assert_equal "12345", vinculo.matricula
    assert_equal unidade, vinculo.lotacao_principal.unidade
    assert_equal [ [ "12345", pessoa.nome ] ], unidade.servidores.map { [ _1.matricula, _1.nome ] }
  end

  test "reuses the vinculo estado and keeps CPFs unique" do
    unidade = criar_unidade
    primeira = criar_pessoa_lotada(unidade: unidade)
    segunda = criar_pessoa_lotada(unidade: unidade)

    assert_equal 1, Pessoas::VinculoEstado.where(nome: "em_exercicio").count
    assert_not_equal primeira.cpf, segunda.cpf
  end
end
