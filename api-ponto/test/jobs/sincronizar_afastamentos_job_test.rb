require "test_helper"

class SincronizarAfastamentosJobTest < ActiveJob::TestCase
  # Sem dados reais no banco `pessoas` de teste (sem schema carregado, ver
  # nota em test/jobs/importar_dados_pessoa_job_test.rb) — stubamos
  # `Pessoas::Pessoa.find_by`, cuja pessoa devolvida expõe `.afastamentos`
  # no formato usado pelo job (id_intranet, tipo_afastamento.nome, inicio,
  # fim).
  PessoaDouble = Struct.new(:id, :afastamentos, keyword_init: true)
  AfastamentoDouble = Struct.new(:id_intranet, :tipo_afastamento, :inicio, :fim, keyword_init: true)
  TipoAfastamentoDouble = Struct.new(:nome, keyword_init: true)

  def afastamento_double(id_intranet:, tipo:, inicio:, fim:)
    AfastamentoDouble.new(
      id_intranet: id_intranet,
      tipo_afastamento: tipo ? TipoAfastamentoDouble.new(nome: tipo) : nil,
      inicio: Date.parse(inicio),
      fim: Date.parse(fim)
    )
  end

  def stub_pessoa_com_afastamentos(afastamentos)
    Pessoas::Pessoa.define_singleton_method(:find_by) { |*_args| PessoaDouble.new(id: 1, afastamentos: afastamentos) }
    yield
  ensure
    Pessoas::Pessoa.singleton_class.remove_method(:find_by)
  end

  test "faz upsert de AfastamentoCache a partir dos afastamentos lidos do banco" do
    user = User.create!(nome_completo: "Fulano", password: "123456", cpf: "11122233344")

    stub_pessoa_com_afastamentos([
      afastamento_double(id_intranet: 42, tipo: "Férias", inicio: "2026-01-10", fim: "2026-01-20")
    ]) do
      SincronizarAfastamentosJob.perform_now(user.id)
    end

    cache = AfastamentoCache.find_by(afastamento_id_pessoas: 42)
    assert cache.present?
    assert_equal "11122233344", cache.cpf
    assert_equal "Férias", cache.tipo
    assert_equal Date.parse("2026-01-10"), cache.momento_inicial.to_date
    assert_equal Date.parse("2026-01-20"), cache.momento_final.to_date
  end

  test "faz upsert de multiplos afastamentos do mesmo usuario" do
    user = User.create!(nome_completo: "Fulano", password: "123456", cpf: "11122233344")

    stub_pessoa_com_afastamentos([
      afastamento_double(id_intranet: 1, tipo: "Férias", inicio: "2026-01-10", fim: "2026-01-20"),
      afastamento_double(id_intranet: 2, tipo: "Licença Médica", inicio: "2026-02-01", fim: "2026-02-05")
    ]) do
      SincronizarAfastamentosJob.perform_now(user.id)
    end

    assert_equal 2, AfastamentoCache.where(cpf: "11122233344").count
  end

  test "atualiza o AfastamentoCache existente em vez de duplicar" do
    user = User.create!(nome_completo: "Fulano", password: "123456", cpf: "11122233344")
    AfastamentoCache.create!(afastamento_id_pessoas: 42, cpf: "11122233344", tipo: "Tipo Antigo")

    stub_pessoa_com_afastamentos([
      afastamento_double(id_intranet: 42, tipo: "Tipo Novo", inicio: "2026-01-10", fim: "2026-01-20")
    ]) do
      SincronizarAfastamentosJob.perform_now(user.id)
    end

    assert_equal 1, AfastamentoCache.where(afastamento_id_pessoas: 42).count
    assert_equal "Tipo Novo", AfastamentoCache.find_by(afastamento_id_pessoas: 42).tipo
  end

  test "nao quebra quando a pessoa nao tem afastamentos" do
    user = User.create!(nome_completo: "Fulano", password: "123456", cpf: "11122233344")

    stub_pessoa_com_afastamentos([]) do
      assert_nothing_raised { SincronizarAfastamentosJob.perform_now(user.id) }
    end

    assert_equal 0, AfastamentoCache.where(cpf: "11122233344").count
  end

  test "ignora usuarios sem cpf ao rodar em lote" do
    sem_cpf = User.create!(nome_completo: "Sem CPF", password: "123456")
    chamou = false

    Pessoas::Pessoa.define_singleton_method(:find_by) { |*_args| chamou = true; nil }

    begin
      SincronizarAfastamentosJob.perform_now
    ensure
      Pessoas::Pessoa.singleton_class.remove_method(:find_by)
    end

    assert_not chamou
    assert_equal 0, AfastamentoCache.where(cpf: sem_cpf.cpf).count
  end

  test "erro em um usuario nao impede a sincronizacao dos demais" do
    user1 = User.create!(nome_completo: "Vai Falhar", password: "123456", cpf: "11122233344")
    user2 = User.create!(nome_completo: "Vai Funcionar", password: "123456", cpf: "55566677788")

    pessoa_ok = PessoaDouble.new(id: 2, afastamentos: [ afastamento_double(id_intranet: 99, tipo: "Férias", inicio: "2026-01-10", fim: "2026-01-20") ])

    Pessoas::Pessoa.define_singleton_method(:find_by) do |cpf:|
      raise "falha simulada" if cpf == "11122233344"

      pessoa_ok
    end

    begin
      assert_nothing_raised { SincronizarAfastamentosJob.perform_now }
    ensure
      Pessoas::Pessoa.singleton_class.remove_method(:find_by)
    end

    assert_equal 0, AfastamentoCache.where(cpf: user1.cpf).count
    assert_equal 1, AfastamentoCache.where(cpf: user2.cpf).count
  end

  test "nao executa quando o lock ja esta adquirido por outra execucao" do
    user = User.create!(nome_completo: "Fulano", password: "123456", cpf: "11122233344")
    chamou = false
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    outra_conexao = PG.connect(host: config[:host], port: config[:port], dbname: config[:database], user: config[:username], password: config[:password])

    begin
      outra_conexao.exec("SELECT pg_try_advisory_lock(#{SincronizarAfastamentosJob::LOCK_KEY})")

      Pessoas::Pessoa.define_singleton_method(:find_by) { |*_args| chamou = true; nil }
      begin
        SincronizarAfastamentosJob.perform_now(user.id)
      ensure
        Pessoas::Pessoa.singleton_class.remove_method(:find_by)
      end

      assert_not chamou
    ensure
      outra_conexao.exec("SELECT pg_advisory_unlock(#{SincronizarAfastamentosJob::LOCK_KEY})")
      outra_conexao.close
    end
  end
end
