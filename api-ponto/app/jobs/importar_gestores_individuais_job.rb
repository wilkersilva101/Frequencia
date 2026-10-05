# Job da Tarefa 29.3 — wrapper "digitável" da rake
# `frequencia:importar_gestores_individuais`.
#
# A rake é a entrada primária (execução manual assistida na virada do
# Intranet; ver o cabeçalho da task). O job existe para que a mesma operação
# possa ser agendada via `sidekiq-cron` num `config/schedule.yml` quando o
# fluxo estiver estável — mas NÃO é agendado por esta tarefa: a importação
# toca a rede do Intranet e deve ser observada na primeira execução real.
#
# Mesma postura dos demais jobs de importação (lock de execução única), e a
# regra do ambiente se mantém: gravar via ActiveRecord, nunca `upsert_all`
# (ADR-0007, regra 8).
class ImportarGestoresIndividuaisJob < ApplicationJob
  queue_as :default

  # Chave distinta das demais (ImportarDadosPessoaJob 837_462_915,
  # ImportarServidoresUnidadeJob 592_017_384, SincronizarAfastamentosJob
  # 194_773_608) — jobs diferentes podem rodar em paralelo sem conflito.
  LOCK_KEY = 471_209_336

  # `dry_run` propaga para o serviço: `DRY_RUN=1` no agendamento roda sem
  # escrita. O relatório vai para o log.
  def perform(registros: nil, dry_run: false)
    return unless lock_adquirido?

    begin
      resultado = ImportarGestoresIndividuaisService.call(registros: registros, dry_run: dry_run)
      Rails.logger.info("[ImportarGestoresIndividuaisJob]\n#{resultado.resumo}")
      resultado
    ensure
      liberar_lock
    end
  end

  private

  def lock_adquirido?
    ActiveRecord::Base.connection.select_value("SELECT pg_try_advisory_lock(#{LOCK_KEY})") == true
  end

  def liberar_lock
    ActiveRecord::Base.connection.execute("SELECT pg_advisory_unlock(#{LOCK_KEY})")
  end
end
