# Importação em massa (Sprint 10B): dado o id de uma unidade do Pessoas,
# descobre todos os servidores lotados nela e cria/atualiza o Frequentador
# (User + FrequentadorCache) correspondente — sem precisar que alguém já
# tenha cadastrado o CPF manualmente (diferença central em relação ao
# ImportarDadosPessoaJob, que só atualiza quem já existe).
#
# Fluxo (task 8.13 — leitura direta do Postgres do Pessoas, substitui
# Sticapi): `Pessoas::Unidade#servidores` (lotação principal e vigente) dá a
# lista de servidores (matrícula, nome — sem CPF, igual antes) →
# ResolverCpfPorMatriculaService resolve CPF via folha do GestoRH →
# `Pessoas::Pessoa.find_by(cpf:)` traz os dados completos de cada um →
# upsert em User/FrequentadorCache.
#
# Ver SPRINT-PLAN.md, Sprint 10B e Sprint 8 (task 8.13).
class ImportarServidoresUnidadeJob < ApplicationJob
  queue_as :default

  # Chave distinta de ImportarDadosPessoaJob::LOCK_KEY — são jobs diferentes,
  # que podem rodar em paralelo sem conflito (um por unidade, outro por
  # usuário já cadastrado).
  LOCK_KEY = 592_017_384

  def perform(unidade_id)
    return unless lock_adquirido?

    begin
      importar_unidade(unidade_id)
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

  def importar_unidade(unidade_id)
    unidade = Pessoas::Unidade.find_by(id: unidade_id)
    return if unidade.blank?

    servidores = unidade.servidores
    return if servidores.blank?

    matriculas = servidores.filter_map(&:matricula)
    cpf_por_matricula = ResolverCpfPorMatriculaService.mais_recente(matriculas)

    servidores.each do |servidor|
      cpf = cpf_por_matricula[servidor.matricula.to_s]

      if cpf.blank?
        Rails.logger.warn("[ImportarServidoresUnidadeJob] Matrícula #{servidor.matricula} não resolvida em CPF (não encontrada na competência atual nem na anterior) — servidor pulado")
        next
      end

      importar_servidor(cpf)
    end
  end

  def importar_servidor(cpf)
    pessoa = Pessoas::Pessoa.find_by(cpf: cpf)
    return if pessoa.blank? || pessoa.nome.blank?

    criar_user_se_necessario(cpf, pessoa)
    AtualizarFrequentadorCacheService.call(cpf: cpf, pessoa: pessoa)
  rescue StandardError => e
    Rails.logger.error("[ImportarServidoresUnidadeJob] Falha ao importar CPF #{cpf}: #{e.message}")
  end

  # Decisões registradas na Sprint 10B/21 sobre campos que o User exige mas
  # o Pessoas não supre diretamente:
  #
  # - password: aleatória/inutilizável (SecureRandom) — ninguém a conhece,
  #   é só um placeholder para satisfazer `has_secure_password`. Login local
  #   via senha fica bloqueado para frequentadores criados assim até a
  #   Sprint 21 substituir a autenticação por `sticapi_authenticatable`
  #   (login/senha reais do Pessoas, mecanismo já confirmado tecnicamente).
  #   Biometria continua funcionando (não depende de senha).
  # - username: usa o `username` real da tabela `pessoas`
  #   (`pessoa.username`) — mesmo campo que o próprio pessoas2 usa para
  #   vincular seu User a Pessoa (`has_one :pessoa, foreign_key: "username",
  #   primary_key: "username"`). Só cai no `generate_username` local
  #   (callback já existente no model) quando o Pessoas não tem username
  #   preenchido — não sobrescreve o de quem já existe (só se aplica na
  #   criação, ver método `new_record?` abaixo).
  # - status: usa o default do schema (`status: 1`, ativo) — não setado
  #   explicitamente aqui de propósito, para não duplicar a regra do
  #   banco/model.
  def criar_user_se_necessario(cpf, pessoa)
    user = User.find_or_initialize_by(cpf: cpf)
    return unless user.new_record?

    user.nome_completo = pessoa.nome
    user.username = pessoa.username if pessoa.username.present?
    user.password = SecureRandom.hex(16)
    user.save!
  end
end
