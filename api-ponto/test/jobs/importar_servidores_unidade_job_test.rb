require "test_helper"

class ImportarServidoresUnidadeJobTest < ActiveJob::TestCase
  # Sem dados reais no banco `pessoas` de teste (sem schema carregado, ver
  # nota em test/jobs/importar_dados_pessoa_job_test.rb) — stubamos os 3
  # pontos de entrada usados pelo job: `Pessoas::Unidade.find_by` (unidade
  # com `.servidores`), `Pessoas::GestorhContrachequeMirror
  # .pares_matricula_cpf_para` (via ResolverCpfPorMatriculaService) e
  # `Pessoas::Pessoa.find_by`.
  def stub_unidade(resposta)
    Pessoas::Unidade.define_singleton_method(:find_by) { |*_args| resposta }
    yield
  ensure
    Pessoas::Unidade.singleton_class.remove_method(:find_by)
  end

  def stub_pares_matricula_cpf(pares)
    Pessoas::GestorhContrachequeMirror.define_singleton_method(:pares_matricula_cpf_para) { |*_args, **_kwargs| pares }
    yield
  ensure
    Pessoas::GestorhContrachequeMirror.singleton_class.remove_method(:pares_matricula_cpf_para)
  end

  def stub_pessoas_find_by_cpf(mapa_cpf_para_pessoa)
    Pessoas::Pessoa.define_singleton_method(:find_by) { |cpf:| mapa_cpf_para_pessoa[cpf] }
    yield
  ensure
    Pessoas::Pessoa.singleton_class.remove_method(:find_by)
  end

  UnidadeDouble = Struct.new(:servidores, keyword_init: true)
  PessoaDouble = Struct.new(:id, :nome, :username, :vinculos_ativos, keyword_init: true)

  def unidade_com_um_servidor
    UnidadeDouble.new(servidores: [ Pessoas::Unidade::ServidorLotado.new(matricula: "1001", nome: "Fulano de Tal") ])
  end

  def pessoa_double(id: 42, nome: "Fulano de Tal", username: nil)
    PessoaDouble.new(id: id, nome: nome, username: username, vinculos_ativos: [])
  end

  test "cria um novo User e FrequentadorCache para servidor resolvido" do
    stub_pares_matricula_cpf([ [ "1001", "11122233344" ] ]) do
      stub_unidade(unidade_com_um_servidor) do
        stub_pessoas_find_by_cpf({ "11122233344" => pessoa_double }) do
          ImportarServidoresUnidadeJob.perform_now(999)
        end
      end
    end

    user = User.find_by(cpf: "11122233344")
    assert user.present?
    assert_equal "Fulano de Tal", user.nome_completo
    assert user.password_digest.present?

    cache = FrequentadorCache.find_by(cpf: "11122233344")
    assert cache.present?
  end

  test "usa o username real vindo do Pessoas ao criar o User" do
    stub_pares_matricula_cpf([ [ "1001", "11122233344" ] ]) do
      stub_unidade(unidade_com_um_servidor) do
        stub_pessoas_find_by_cpf({ "11122233344" => pessoa_double(username: "fulano.pessoas") }) do
          ImportarServidoresUnidadeJob.perform_now(999)
        end
      end
    end

    assert_equal "fulano.pessoas", User.find_by(cpf: "11122233344").username
  end

  test "cai no generate_username local quando o Pessoas nao tem username" do
    stub_pares_matricula_cpf([ [ "1001", "11122233344" ] ]) do
      stub_unidade(unidade_com_um_servidor) do
        stub_pessoas_find_by_cpf({ "11122233344" => pessoa_double }) do
          ImportarServidoresUnidadeJob.perform_now(999)
        end
      end
    end

    assert_equal "fulano.tal", User.find_by(cpf: "11122233344").username
  end

  test "usuario com status ativo por padrao (default do schema, sem set explicito)" do
    stub_pares_matricula_cpf([ [ "1001", "11122233344" ] ]) do
      stub_unidade(unidade_com_um_servidor) do
        stub_pessoas_find_by_cpf({ "11122233344" => pessoa_double }) do
          ImportarServidoresUnidadeJob.perform_now(999)
        end
      end
    end

    assert_equal 1, User.find_by(cpf: "11122233344").status
  end

  test "nao cria User duplicado quando ja existe pelo cpf" do
    existente = User.create!(nome_completo: "Ja Existia", password: "123456", cpf: "11122233344")

    stub_pares_matricula_cpf([ [ "1001", "11122233344" ] ]) do
      stub_unidade(unidade_com_um_servidor) do
        stub_pessoas_find_by_cpf({ "11122233344" => pessoa_double(nome: "Nome Novo Vindo Do Pessoas") }) do
          ImportarServidoresUnidadeJob.perform_now(999)
        end
      end
    end

    assert_equal 1, User.where(cpf: "11122233344").count
    # Nao sobrescreve nome de usuario ja existente (mesmo comportamento do
    # ImportarDadosPessoaJob so alterar quem chama explicitamente)
    assert_equal "Ja Existia", existente.reload.nome_completo
  end

  test "matricula nao resolvida (sem cpf) e pulada sem quebrar o job, com log de aviso" do
    log_io = StringIO.new
    logger_original = Rails.logger
    Rails.logger = Logger.new(log_io)

    begin
      stub_pares_matricula_cpf([]) do
        stub_unidade(unidade_com_um_servidor) do
          assert_nothing_raised do
            ImportarServidoresUnidadeJob.perform_now(999)
          end
        end
      end
    ensure
      Rails.logger = logger_original
    end

    assert_match(/Matrícula 1001 não resolvida em CPF/, log_io.string)
    assert_equal 0, User.where(nome_completo: "Fulano de Tal").count
  end

  test "um servidor com erro nao impede a importacao dos demais" do
    unidade_com_dois = UnidadeDouble.new(servidores: [
      Pessoas::Unidade::ServidorLotado.new(matricula: "1001", nome: "Vai Falhar"),
      Pessoas::Unidade::ServidorLotado.new(matricula: "1002", nome: "Vai Funcionar")
    ])

    pessoa_ok = pessoa_double(id: 2, nome: "Vai Funcionar")

    stub_pares_matricula_cpf([ [ "1001", "11122233344" ], [ "1002", "55566677788" ] ]) do
      stub_unidade(unidade_com_dois) do
        Pessoas::Pessoa.define_singleton_method(:find_by) do |cpf:|
          raise "falha simulada" if cpf == "11122233344"

          pessoa_ok
        end

        begin
          assert_nothing_raised do
            ImportarServidoresUnidadeJob.perform_now(999)
          end
        ensure
          Pessoas::Pessoa.singleton_class.remove_method(:find_by)
        end
      end
    end

    assert_nil User.find_by(cpf: "11122233344")
    assert User.find_by(cpf: "55566677788").present?
  end

  test "unidade sem servidores nao quebra o job" do
    stub_unidade(UnidadeDouble.new(servidores: [])) do
      assert_nothing_raised do
        ImportarServidoresUnidadeJob.perform_now(999)
      end
    end
  end

  test "unidade nao encontrada nao quebra o job" do
    stub_unidade(nil) do
      assert_nothing_raised do
        ImportarServidoresUnidadeJob.perform_now(999)
      end
    end
  end

  test "nao executa quando o lock ja esta adquirido por outra execucao" do
    chamou = false
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    outra_conexao = PG.connect(host: config[:host], port: config[:port], dbname: config[:database], user: config[:username], password: config[:password])

    begin
      outra_conexao.exec("SELECT pg_try_advisory_lock(#{ImportarServidoresUnidadeJob::LOCK_KEY})")

      Pessoas::Unidade.define_singleton_method(:find_by) { |*_args| chamou = true; unidade_com_um_servidor }
      begin
        ImportarServidoresUnidadeJob.perform_now(999)
      ensure
        Pessoas::Unidade.singleton_class.remove_method(:find_by)
      end

      assert_not chamou
    ensure
      outra_conexao.exec("SELECT pg_advisory_unlock(#{ImportarServidoresUnidadeJob::LOCK_KEY})")
      outra_conexao.close
    end
  end
end
