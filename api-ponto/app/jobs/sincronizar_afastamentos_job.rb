# Sincronização de Direitos/Deveres (Sprint 12): espelha afastamentos do
# sistema Pessoas, para cada User com `cpf` preenchido.
#
# Fonte real (task 8.13 — leitura direta do Postgres do Pessoas, substitui
# `SticapiClient::Intranet.afastamentos`): tabela `afastamentos`, ligada a
# `vinculos` → `pessoas` (por CPF). A coluna `afastamentos.id_intranet` é o
# mesmo `id` que o endpoint HTTP da Intranet retornava (confirmado contra
# dados reais na task 8.13) — continua sendo a chave usada em
# `AfastamentoCache#afastamento_id_pessoas`.
#
# `cargo`/`lotacao`/`status` do AfastamentoCache (task 12.1) continuam NÃO
# vindo daqui — ficam nil, igual antes da migração. Não inventamos de onde
# tirar esses campos; se forem necessários, precisam de investigação futura
# (talvez outra tabela, ou junção com FrequentadorCache).
class SincronizarAfastamentosJob < ApplicationJob
  queue_as :default

  # Chave distinta de ImportarDadosPessoaJob::LOCK_KEY (837_462_915) e
  # ImportarServidoresUnidadeJob::LOCK_KEY (592_017_384).
  LOCK_KEY = 194_773_608

  def perform(user_id = nil)
    return unless lock_adquirido?

    begin
      usuarios = user_id ? User.where(id: user_id) : User.where.not(cpf: nil)
      usuarios.find_each { |user| sincronizar_usuario(user) }
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

  def sincronizar_usuario(user)
    return if user.cpf.blank?

    pessoa = Pessoas::Pessoa.find_by(cpf: user.cpf)
    return if pessoa.blank?

    pessoa.afastamentos.each { |afastamento| atualizar_cache(user.cpf, afastamento) }
  rescue StandardError => e
    Rails.logger.error("[SincronizarAfastamentosJob] Falha ao sincronizar CPF #{user.cpf}: #{e.message}")
  end

  def atualizar_cache(cpf, afastamento)
    return if afastamento.id_intranet.blank?

    AfastamentoCache.find_or_initialize_by(afastamento_id_pessoas: afastamento.id_intranet).update!(
      cpf: cpf,
      tipo: afastamento.tipo_afastamento&.nome,
      momento_inicial: afastamento.inicio,
      momento_final: afastamento.fim
    )
  end
end
