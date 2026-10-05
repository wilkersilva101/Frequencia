# frozen_string_literal: true

# Tarefa 29.3 (Sprint 29) — importação idempotente dos gestores individuais
# do Intranet legado (PRD §2.5).
#
#   bin/rails frequencia:importar_gestores_individuais
#   DRY_RUN=1 bin/rails frequencia:importar_gestores_individuais
#
# A lógica vive em `ImportarGestoresIndividuaisService` (testável sem tocar a
# rede); aqui fica só a borda operacional: ler `DRY_RUN`, chamar o serviço e
# imprimir o relatório. Reexecutar é seguro ("segunda execução = 0 criações")
# — o upsert é feito pelas chaves estáveis (`id_legado`).
#
# `DRY_RUN=1` percorre o mesmo caminho de resolução/validação, mas não escreve
# nada — é o modo de conferência recomendado antes da primeira execução real
# na virada.
namespace :frequencia do
  desc "Importa (idempotente) os gestores individuais do Intranet. DRY_RUN=1 simula sem escrever."
  task importar_gestores_individuais: :environment do
    dry_run = ENV["DRY_RUN"] == "1"

    resultado = ImportarGestoresIndividuaisService.call(dry_run: dry_run)

    puts resultado.resumo

    # Sinal honesto para scripts/encadeamento: uma execução REAL com linhas
    # não resolvidas não deve sair com status de sucesso — mas o relatório já
    # foi impresso, nada é engolido. Em DRY_RUN o exit code permanece 0: é o
    # modo de conferência e "achar pendências" é o resultado esperado dele.
    if resultado.nao_resolvidos.any? && !resultado.dry_run
      abort "Importação concluída com #{resultado.nao_resolvidos.size} linha(s) não resolvida(s) — ver relatório acima."
    end
  end
end
