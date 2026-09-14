# Job noturno que sincroniza as digitais (biometria) da Intranet para a api-ponto.
#
# Executado manualmente:
#   bin/rails runner "SyncDigitaisJob.perform_later"
# E agendado via config/schedule.yml (sidekiq-cron) nas madrugadas.
#
# Modelo: SyncPrediosJob do Pessoas2 (docs/JOB-sync-predios.md).
class SyncDigitaisJob < ApplicationJob
  queue_as :default

  def perform
    resumo = Intranet::SyncDigitaisService.call
    Rails.logger.info "SyncDigitaisJob concluído — #{resumo}"
  end
end
