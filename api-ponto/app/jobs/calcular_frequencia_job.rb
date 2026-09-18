# Sprint 17 (task 17.5) — job automático pra rodar o pipeline de cálculo
# (`CalculoDiarioService.calcular` → `ConsolidacaoMensalService.consolidar`),
# fechando o débito técnico registrado no fim da 17.4: os dois services
# existiam e funcionavam, mas nada os disparava automaticamente.
#
# Mesmo padrão dos outros jobs diários (`ImportarDadosPessoaJob`,
# `SincronizarAfastamentosJob`): advisory lock via `pg_try_advisory_lock`/
# `pg_advisory_unlock`, itera `User.where.not(cpf: nil).find_each`,
# `rescue StandardError` por usuário sem derrubar o job inteiro, log de
# erro por usuário.
#
# Escopo por execução (decisão já tomada, não reabrir):
# - Recalcula `CalculoDiario` (via `CalculoDiarioService.calcular`) dos
#   últimos 3 dias (hoje, ontem, anteontem) de cada usuário — não o mês
#   inteiro, caro e desnecessário rodar toda noite; 3 dias cobre correções
#   tardias de sincronização sem reprocessar histórico completo. O cálculo
#   já é idempotente (`find_or_initialize_by` dentro do service).
# - Consolida o mês corrente (via `ConsolidacaoMensalService.consolidar`)
#   de cada usuário, também idempotente.
# - `ConsolidacaoMensalService::MesFinalizadoError` é esperado (mês fechado
#   pela trava da 17.2) e é pulado silenciosamente — não é erro, não conta
#   como falha, não loga como erro, só segue pro próximo usuário. Erros
#   genuínos (`StandardError` de outra natureza, em qualquer etapa) são
#   logados por usuário, sem derrubar o job inteiro, mesmo padrão dos
#   outros dois jobs.
class CalcularFrequenciaJob < ApplicationJob
  queue_as :default

  DIAS_RECALCULADOS = 3

  # Chave distinta de ImportarDadosPessoaJob::LOCK_KEY (837_462_915),
  # ImportarServidoresUnidadeJob::LOCK_KEY (592_017_384) e
  # SincronizarAfastamentosJob::LOCK_KEY (194_773_608).
  LOCK_KEY = 451_926_073

  def perform(user_id = nil)
    return unless lock_adquirido?

    begin
      usuarios = user_id ? User.where(id: user_id) : User.where.not(cpf: nil)
      usuarios.find_each { |user| processar_usuario(user) }
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

  def processar_usuario(user)
    return if user.cpf.blank?

    hoje = Date.current
    (0...DIAS_RECALCULADOS).each { |dias_atras| CalculoDiarioService.calcular(user, hoje - dias_atras) }

    ConsolidacaoMensalService.consolidar(user, hoje.year, hoje.month)
  rescue ConsolidacaoMensalService::MesFinalizadoError
    # Esperado: mês já finalizado pela trava da 17.2, não recalcula — não é
    # erro, segue pro próximo usuário silenciosamente.
  rescue StandardError => e
    Rails.logger.error("[CalcularFrequenciaJob] Falha ao processar CPF #{user.cpf}: #{e.message}")
  end
end
