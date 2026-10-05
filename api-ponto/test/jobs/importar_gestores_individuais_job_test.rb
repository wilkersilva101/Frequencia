require "test_helper"

# Tarefa 29.3 — o job é um wrapper fino da rake/serviço: lock de execução
# única + log do relatório. A lógica em si é coberta em
# test/services/importar_gestores_individuais_service_test.rb.
class ImportarGestoresIndividuaisJobTest < ActiveJob::TestCase
  def linha(id:, matricula_gestor: "1001", matricula_gerido: "2002")
    {
      "id" => id,
      "data_criacao" => "2019-10-30 10:03:25.0",
      "data_exclusao" => nil,
      "observacao" => "SEI",
      "id_vinculo_gestor" => 900,
      "matricula_gestor" => matricula_gestor,
      "id_vinculo_gerido" => 700,
      "matricula_gerido" => matricula_gerido
    }
  end

  # Restaura o método original ao fim do bloco (ver nota no teste do serviço).
  def stub_mapa_cpf(mapa)
    original = ResolverCpfPorMatriculaService.method(:mais_recente)
    ResolverCpfPorMatriculaService.singleton_class.send(:remove_method, :mais_recente)
    ResolverCpfPorMatriculaService.define_singleton_method(:mais_recente) { |*_args, **_kwargs| mapa }
    yield
  ensure
    ResolverCpfPorMatriculaService.singleton_class.send(:remove_method, :mais_recente)
    ResolverCpfPorMatriculaService.define_singleton_method(:mais_recente, original)
  end

  test "executa a importacao e devolve o relatorio" do
    User.create!(nome_completo: "Gerido", password: "123456", cpf: "55566677788")

    resultado = nil
    stub_mapa_cpf({ "1001" => "11122233344", "2002" => "55566677788" }) do
      resultado = ImportarGestoresIndividuaisJob.perform_now(registros: [ linha(id: 42) ])
    end

    assert_equal 1, resultado.importados
    assert GestorIndividualGerenciado.find_by(id_legado: 42).present?
  end

  test "dry_run propagado nao escreve" do
    User.create!(nome_completo: "Gerido", password: "123456", cpf: "55566677788")

    assert_no_difference([ "GestorIndividual.count", "GestorIndividualGerenciado.count" ]) do
      stub_mapa_cpf({ "1001" => "11122233344", "2002" => "55566677788" }) do
        resultado = ImportarGestoresIndividuaisJob.perform_now(registros: [ linha(id: 42) ], dry_run: true)
        assert resultado.dry_run
      end
    end
  end

  test "nao executa quando o lock ja esta adquirido por outra execucao" do
    User.create!(nome_completo: "Gerido", password: "123456", cpf: "55566677788")

    config = ActiveRecord::Base.connection_db_config.configuration_hash
    outra_conexao = PG.connect(
      host: config[:host], port: config[:port], dbname: config[:database],
      user: config[:username], password: config[:password]
    )

    begin
      outra_conexao.exec("SELECT pg_try_advisory_lock(#{ImportarGestoresIndividuaisJob::LOCK_KEY})")

      resultado = stub_mapa_cpf({ "1001" => "11122233344", "2002" => "55566677788" }) do
        ImportarGestoresIndividuaisJob.perform_now(registros: [ linha(id: 42) ])
      end

      assert_nil resultado, "com o lock tomado, o job não deve rodar"
      assert_nil GestorIndividualGerenciado.find_by(id_legado: 42)
    ensure
      outra_conexao.exec("SELECT pg_advisory_unlock(#{ImportarGestoresIndividuaisJob::LOCK_KEY})")
      outra_conexao.close
    end
  end
end
