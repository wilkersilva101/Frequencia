require "test_helper"

class AtualizarFrequentadorCacheServiceTest < ActiveSupport::TestCase
  # Doubles no formato exposto por Pessoas::Pessoa/Pessoas::Vinculo (task
  # 8.13). Não usamos registros reais de app/models/pessoas/*.rb porque o
  # serviço só depende da interface (id, nome, vinculos_ativos ->
  # lotacao_principal.unidade.descricao / tipo_vinculo.nome), e o banco
  # `pessoas_test` não tem schema carregado (ver nota em
  # test/jobs/importar_dados_pessoa_job_test.rb).
  PessoaDouble = Struct.new(:id, :nome, :vinculos_ativos, keyword_init: true)
  VinculoDouble = Struct.new(:lotacao_principal, :tipo_vinculo, keyword_init: true)
  LotacaoDouble = Struct.new(:unidade, keyword_init: true)
  UnidadeDouble = Struct.new(:descricao, keyword_init: true)
  TipoVinculoDouble = Struct.new(:nome, keyword_init: true)

  def vinculo_double(orgao:, vinculo:)
    VinculoDouble.new(
      lotacao_principal: orgao ? LotacaoDouble.new(unidade: UnidadeDouble.new(descricao: orgao)) : nil,
      tipo_vinculo: vinculo ? TipoVinculoDouble.new(nome: vinculo) : nil
    )
  end

  test "extrai orgao e vinculo do primeiro vinculo ativo quando ha varios" do
    pessoa = PessoaDouble.new(
      id: 42,
      nome: "Fulano de Tal",
      vinculos_ativos: [
        vinculo_double(orgao: "Vara Cível", vinculo: "Efetivo"),
        vinculo_double(orgao: "Outra Unidade", vinculo: "Comissionado")
      ]
    )

    cache = AtualizarFrequentadorCacheService.call(cpf: "11122233344", pessoa: pessoa)

    assert_equal "Vara Cível", cache.orgao
    assert_equal "Efetivo", cache.vinculo
  end

  test "extrai orgao e vinculo quando ha exatamente 1 vinculo ativo" do
    pessoa = PessoaDouble.new(
      id: 42,
      nome: "Fulano de Tal",
      vinculos_ativos: [ vinculo_double(orgao: "Vara Cível", vinculo: "Efetivo") ]
    )

    cache = AtualizarFrequentadorCacheService.call(cpf: "11122233344", pessoa: pessoa)

    assert_equal "Vara Cível", cache.orgao
    assert_equal "Efetivo", cache.vinculo
  end

  test "orgao e vinculo ficam nil quando nao ha vinculo ativo" do
    pessoa = PessoaDouble.new(id: 42, nome: "Fulano de Tal", vinculos_ativos: [])

    cache = AtualizarFrequentadorCacheService.call(cpf: "11122233344", pessoa: pessoa)

    assert_nil cache.vinculo
    assert_nil cache.orgao
  end

  test "faz upsert (nao duplica) para o mesmo cpf" do
    primeiro = PessoaDouble.new(id: 1, nome: "Primeiro", vinculos_ativos: [])
    AtualizarFrequentadorCacheService.call(cpf: "11122233344", pessoa: primeiro)

    segundo = PessoaDouble.new(id: 1, nome: "Segundo", vinculos_ativos: [])
    AtualizarFrequentadorCacheService.call(cpf: "11122233344", pessoa: segundo)

    assert_equal 1, FrequentadorCache.where(cpf: "11122233344").count
    assert_equal "Segundo", FrequentadorCache.find_by(cpf: "11122233344").nome
  end
end
