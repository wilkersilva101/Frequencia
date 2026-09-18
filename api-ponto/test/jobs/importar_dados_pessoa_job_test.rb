require "test_helper"

class ImportarDadosPessoaJobTest < ActiveJob::TestCase
  # Não usamos fixtures/dados reais no banco `pessoas` de teste porque o
  # banco `pessoas_test` (conexão `pessoas:` em config/database.yml) existe
  # mas NÃO tem schema carregado (é gerenciado pelo pessoas2, que roda em
  # outro projeto — `database_tasks: false` aqui de propósito, ver
  # app/models/pessoas_record.rb). Populá-lo por fora seria inventar dado
  # num banco que não é nosso; em vez disso, stubamos o ponto de entrada
  # (`Pessoas::Pessoa.find_by`) do jeito que este arquivo já stubava
  # `SticapiClient::Pessoas.get_by_cpf` antes da task 8.13 — minitest 6
  # removeu Object#stub (agora é a gem separada minitest-mock, não incluída
  # no projeto), então redefinimos o método de classe temporariamente.
  def stub_find_pessoa(pessoa)
    Pessoas::Pessoa.define_singleton_method(:find_by) { |*_args| pessoa }
    yield
  ensure
    Pessoas::Pessoa.singleton_class.remove_method(:find_by)
  end

  PessoaDouble = Struct.new(:id, :nome, :username, :vinculos_ativos, keyword_init: true)
  VinculoDouble = Struct.new(:lotacao_principal, :tipo_vinculo, keyword_init: true)
  LotacaoDouble = Struct.new(:unidade, keyword_init: true)
  UnidadeDouble = Struct.new(:descricao, keyword_init: true)
  TipoVinculoDouble = Struct.new(:nome, keyword_init: true)

  def pessoa_realista(id: 42, nome: "Nome Atualizado Pessoas", orgao: "Vara Cível", vinculo: "Efetivo", username: nil)
    vinculo_ativo = VinculoDouble.new(
      lotacao_principal: orgao ? LotacaoDouble.new(unidade: UnidadeDouble.new(descricao: orgao)) : nil,
      tipo_vinculo: vinculo ? TipoVinculoDouble.new(nome: vinculo) : nil
    )
    PessoaDouble.new(id: id, nome: nome, username: username, vinculos_ativos: [ vinculo_ativo ])
  end

  test "atualiza nome_completo a partir do Pessoas::Pessoa lido do banco" do
    user = User.create!(nome_completo: "Nome Antigo", password: "123456", cpf: "11122233344")

    stub_find_pessoa(pessoa_realista(nome: "Nome Atualizado Pessoas")) do
      ImportarDadosPessoaJob.perform_now(user.id)
    end

    assert_equal "Nome Atualizado Pessoas", user.reload.nome_completo
  end

  test "nao altera o usuario quando a pessoa nao e encontrada no banco do Pessoas" do
    user = User.create!(nome_completo: "Nome Antigo", password: "123456", cpf: "11122233344")

    stub_find_pessoa(nil) do
      ImportarDadosPessoaJob.perform_now(user.id)
    end

    assert_equal "Nome Antigo", user.reload.nome_completo
  end

  test "faz upsert do FrequentadorCache a partir da pessoa lida do banco" do
    user = User.create!(nome_completo: "Nome Antigo", password: "123456", cpf: "11122233344")

    stub_find_pessoa(pessoa_realista) do
      ImportarDadosPessoaJob.perform_now(user.id)
    end

    cache = FrequentadorCache.find_by(cpf: "11122233344")
    assert cache.present?
    assert_equal 42, cache.pessoa_id_pessoas
    assert_equal "Nome Atualizado Pessoas", cache.nome
    assert_equal "Vara Cível", cache.orgao
    assert_equal "Efetivo", cache.vinculo
    assert cache.sincronizado_em.present?
  end

  test "faz upsert do FrequentadorCache mesmo sem lotacao ou vinculo ativo" do
    user = User.create!(nome_completo: "Nome Antigo", password: "123456", cpf: "11122233344")

    pessoa = PessoaDouble.new(id: 42, nome: "Nome Atualizado Pessoas", vinculos_ativos: [])

    stub_find_pessoa(pessoa) do
      ImportarDadosPessoaJob.perform_now(user.id)
    end

    cache = FrequentadorCache.find_by(cpf: "11122233344")
    assert cache.present?
    assert_nil cache.orgao
    assert_nil cache.vinculo
  end

  test "atualiza o FrequentadorCache existente em vez de duplicar" do
    user = User.create!(nome_completo: "Nome Antigo", password: "123456", cpf: "11122233344")
    FrequentadorCache.create!(cpf: "11122233344", nome: "Nome Bem Antigo", sincronizado_em: 1.day.ago)

    stub_find_pessoa(pessoa_realista(orgao: nil, vinculo: nil)) do
      ImportarDadosPessoaJob.perform_now(user.id)
    end

    assert_equal 1, FrequentadorCache.where(cpf: "11122233344").count
    assert_equal "Nome Atualizado Pessoas", FrequentadorCache.find_by(cpf: "11122233344").nome
  end

  test "nao cria FrequentadorCache quando a pessoa nao e encontrada" do
    user = User.create!(nome_completo: "Nome Antigo", password: "123456", cpf: "11122233344")

    stub_find_pessoa(nil) do
      ImportarDadosPessoaJob.perform_now(user.id)
    end

    assert_nil FrequentadorCache.find_by(cpf: "11122233344")
  end

  test "mantem o FrequentadorCache antigo quando a leitura do banco do Pessoas falha" do
    user = User.create!(nome_completo: "Nome Antigo", password: "123456", cpf: "11122233344")
    cache_antigo = FrequentadorCache.create!(cpf: "11122233344", nome: "Nome Antigo", orgao: "Orgao Antigo", vinculo: "Efetivo", sincronizado_em: 2.days.ago)

    Pessoas::Pessoa.define_singleton_method(:find_by) { |*_args| raise PG::ConnectionBad, "banco do pessoas fora do ar" }

    assert_nothing_raised do
      ImportarDadosPessoaJob.perform_now(user.id)
    end

    assert_equal "Nome Antigo", user.reload.nome_completo
    assert_equal cache_antigo.attributes, FrequentadorCache.find(cache_antigo.id).attributes
  ensure
    Pessoas::Pessoa.singleton_class.remove_method(:find_by)
  end

  test "ignora usuarios sem cpf ao rodar em lote" do
    sem_cpf = User.create!(nome_completo: "Sem CPF", password: "123456")
    chamou = false

    Pessoas::Pessoa.define_singleton_method(:find_by) { |*_args| chamou = true; nil }
    begin
      ImportarDadosPessoaJob.perform_now
    ensure
      Pessoas::Pessoa.singleton_class.remove_method(:find_by)
    end

    assert_not chamou
    assert_equal "Sem CPF", sem_cpf.reload.nome_completo
  end

  test "nao executa quando o lock ja esta adquirido por outra execucao" do
    # pg_try_advisory_lock é reentrante na mesma sessão/conexão: para simular
    # uma segunda execução concorrente de verdade, o lock precisa ser
    # adquirido por uma conexão Postgres separada da usada pelo Rails/job.
    user = User.create!(nome_completo: "Nome Antigo", password: "123456", cpf: "11122233344")
    chamou = false
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    outra_conexao = PG.connect(host: config[:host], port: config[:port], dbname: config[:database], user: config[:username], password: config[:password])

    begin
      outra_conexao.exec("SELECT pg_try_advisory_lock(#{ImportarDadosPessoaJob::LOCK_KEY})")

      Pessoas::Pessoa.define_singleton_method(:find_by) { |*_args| chamou = true; nil }
      begin
        ImportarDadosPessoaJob.perform_now(user.id)
      ensure
        Pessoas::Pessoa.singleton_class.remove_method(:find_by)
      end

      assert_not chamou
      assert_equal "Nome Antigo", user.reload.nome_completo
    ensure
      outra_conexao.exec("SELECT pg_advisory_unlock(#{ImportarDadosPessoaJob::LOCK_KEY})")
      outra_conexao.close
    end
  end
end
