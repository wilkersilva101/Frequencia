require "test_helper"
require "rake"

# Tarefa 29.3 — cobre a borda operacional da rake
# `frequencia:importar_gestores_individuais`: leitura de `DRY_RUN`, impressão
# do relatório e o `abort` quando há linhas não resolvidas numa execução real.
#
# Carregamos as tasks no `Rake.application` REAL da aplicação (via
# `load_tasks`) — montar um `Rake::Application` novo perderia a dependência
# `:environment` que a task declara.
#
# Stubamos `.call` capturando o `UnboundMethod` REAL e reinstalando-o no
# `ensure` (restaura ao fim do bloco, inclusive sob falha). NÃO usamos apenas
# `define_singleton_method` + `remove_method`: o `remove_method` APAGA o método
# real de classe e envenena os testes seguintes do mesmo processo (ver
# docs/governance/lessons.md). O `Object#stub` do Minitest não existe neste
# bundle (Minitest 6.0.6 sem `minitest/mock`).
class FrequenciaImportarGestoresIndividuaisRakeTest < ActiveSupport::TestCase
  TASK_NAME = "frequencia:importar_gestores_individuais"

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?(TASK_NAME)
    @task = Rake::Task[TASK_NAME]
    @task.reenable
  end

  def resultado(nao_resolvidos: [], dry_run: false)
    ImportarGestoresIndividuaisService::Resultado.new(
      importados: 1, atualizados: 0, nao_resolvidos: nao_resolvidos, dry_run: dry_run
    )
  end

  # Restaura o `.call` original ao fim do bloco (ver nota no teste do serviço).
  def com_call_stubado(resposta)
    com_metodo_de_classe_stubado(ImportarGestoresIndividuaisService, :call, resposta) { yield }
  end

  test "imprime o relatorio e nao aborta quando tudo resolve" do
    resolvido = resultado
    com_call_stubado(->(*_a, **_k) { resolvido }) do
      saida = capture_io { @task.invoke }
      assert_includes saida.first, "importados:"
    end
  end

  test "aborta em execucao real com nao-resolvidos" do
    resolvido = resultado(nao_resolvidos: [ ImportarGestoresIndividuaisService::NaoResolvido.new(id_legado: 1, motivo: "x") ])

    com_call_stubado(->(*_a, **_k) { resolvido }) do
      assert_raises(SystemExit) { capture_io { @task.invoke } }
    end
  end

  test "nao aborta em dry-run mesmo com nao-resolvidos" do
    resolvido = resultado(nao_resolvidos: [ ImportarGestoresIndividuaisService::NaoResolvido.new(id_legado: 1, motivo: "x") ], dry_run: true)

    com_call_stubado(->(*_a, **_k) { resolvido }) do
      saida = nil
      assert_nothing_raised { saida = capture_io { @task.invoke } }
      assert_includes saida.first, "não resolvidos: 1"
      assert_includes saida.first, "DRY-RUN"
    end
  end

  test "DRY_RUN=1 e propagado ao servico" do
    recebido = nil
    captura = lambda do |*_args, **kwargs|
      recebido = kwargs[:dry_run]
      ImportarGestoresIndividuaisService::Resultado.new(importados: 0, atualizados: 0, nao_resolvidos: [], dry_run: true)
    end

    begin
      ENV["DRY_RUN"] = "1"
      com_call_stubado(captura) { capture_io { @task.invoke } }
      assert_equal true, recebido
    ensure
      ENV.delete("DRY_RUN")
    end
  end
end
