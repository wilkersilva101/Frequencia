# Sincronização contínua das digitais (biometria) da Intranet (mysql legado)
# para a api-ponto.
#
# Análogo ao `Intranet::SyncPrediosService` do Pessoas2 (docs/JOB-sync-predios.md).
# Diferente da migração inicial (que apenas insere), este serviço compara os dados
# da Intranet com a api-ponto e aplica as mudanças:
#
#   - User existe (por CPF ou username/matrícula) e a digital mudou -> atualiza
#   - User existe e a digital é igual                 -> "sem alteração"
#   - User não existe / vínculo não resolvido          -> IGNORADO (logado, não cria)
#   - digital vazia/null na Intranet                   -> IGNORADO (não apaga)
#
# Idempotente: reexecutar não duplica nem aplica mudanças redundantes.
# NUNCA exclui digitais que deixaram de existir na Intranet.
# Erros são tratados individualmente: um registro com problema não interrompe o lote.
#
# Fonte (somente leitura): MySQL da Intranet
#   (presenca_frequentador + tjpi_vinculado + tjpi_vinculo + global_pessoafisica).
# Conexão definida em `config/database.yml` (seções intranet_development /
# intranet_production). A api-ponto NUNCA escreve nesse banco.
#
# Uso:
#   Intranet::SyncDigitaisService.call                        # sincroniza todos
#   Intranet::SyncDigitaisService.call(dry_run: true)          # só simula/relatório
#   Intranet::SyncDigitaisService.call(only_cpfs: ['1', '2'])  # sincroniza somente CPFs
#
# Retorno: Hash com o resumo {
#   processados, atualizados, sem_alteracao, ignorados, erros
# }
class Intranet::SyncDigitaisService
  LOG_PATH = Rails.root.join('log', 'digitais_migracao.log')

  def self.call(dry_run: false, only_cpfs: nil)
    new(dry_run: dry_run, only_cpfs: only_cpfs).call
  end

  def initialize(dry_run: false, only_cpfs: nil)
    @dry_run = dry_run
    @only_cpfs = Array(only_cpfs).map(&:to_s) if only_cpfs
    @log_path = LOG_PATH
  end

  def call
    FileUtils.mkdir_p(File.dirname(@log_path))
    @registros_intranet = ler_digitais_intranet
    resumo = {
      processados: @registros_intranet.size,
      atualizados: 0,
      sem_alteracao: 0,
      ignorados: 0,
      erros: 0
    }

    @registros_intranet.each do |registro|
      processar(registro, resumo)
    end

    log("SINCRONIZAÇÃO CONCLUÍDA — " \
        "#{resumo[:atualizados]} atualizados, #{resumo[:sem_alteracao]} sem alteração, " \
        "#{resumo[:ignorados]} ignorados, #{resumo[:erros]} erros (de #{resumo[:processados]} processados)")
    resumo
  end

  private

  def ler_digitais_intranet
    return [] unless carregar_mysql2!

    client = client_intranet
    rows = client.query(<<~SQL, symbolize_keys: true, cast: true)
      SELECT
        f.id             AS frequentador_id,
        f.`digitaisHash` AS digitais_hash,
        vp.`matricula`   AS matricula,
        pf.`cpf`         AS cpf
      FROM presenca_frequentador f
        INNER JOIN tjpi_vinculado vin   ON vin.id = f.`vinculado_id`
        INNER JOIN tjpi_previnculado pv ON pv.id  = vin.`preVinculado_id`
        INNER JOIN tjpi_vinculo vp      ON vp.id  = vin.vinculoPrincipal_id
        INNER JOIN global_pessoafisica pf ON pf.id = vin.pessoaFisica_id
      WHERE f.ativo IS TRUE
        AND f.`digitaisHash` <> ''
      ORDER BY f.id ASC
    SQL
    client.close
    rows.map { |r| converter_charset(r) }
  rescue Mysql2::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
    log("ERRO ao conectar na Intranet: #{e.message}")
    []
  end

  def carregar_mysql2!
    require 'mysql2'
    true
  rescue LoadError => e
    log("ERRO: gem mysql2 indisponível. Verifique o Gemfile/libmariadb.so.3 (LD_LIBRARY_PATH) — #{e.message}")
    false
  end

  def client_intranet
    config = conexao_intranet_config
    unless config
      log("ERRO: conexão intranet não configurada (seção 'intranet_#{Rails.env}' ausente no config/database.yml)")
      return nil
    end
    Mysql2::Client.new(config)
  end

  def conexao_intranet_config
    config = Rails.application.config.database_configuration["intranet_#{Rails.env}"]
    return nil if config.blank?

    if Rails.env.production?
      # Produção: credenciais prioritariamente via variáveis de ambiente.
      config = config.merge(
        host: ENV.fetch('INTRANET_HOST', config['host']),
        port: ENV.fetch('INTRANET_PORT', config['port']).to_i,
        username: ENV.fetch('INTRANET_USER', config['username']),
        password: ENV.fetch('INTRANET_PASSWORD', config['password']),
        database: ENV.fetch('INTRANET_DATABASE', config['database'])
      )
    end

    config.symbolize_keys
  end

  def converter_charset(registro)
    registro.transform_values do |valor|
      next if valor.nil?
      valor.is_a?(String) ? valor.encode('UTF-8') : valor
    end
  end

  def processar(registro, resumo)
    cpf = registro[:cpf]
    matricula = registro[:matricula]
    digitais_hash = registro[:digitais_hash]

    if @only_cpfs && !@only_cpfs.include?(cpf.to_s)
      return
    end

    if digitais_hash.blank?
      log("IGNORADO — cpf=#{cpf} matricula=#{matricula}: digital vazia/nula (registro ignorado)")
      resumo[:ignorados] += 1
      return
    end

    begin
      user = encontrar_user(cpf: cpf, matricula: matricula)

      if user.nil?
        log("IGNORADO — cpf=#{cpf} matricula=#{matricula}: User correspondente não encontrado (registro ignorado)")
        resumo[:ignorados] += 1
        return
      end

      if user.digitais_hash == digitais_hash
        resumo[:sem_alteracao] += 1
      else
        atualizar_digital(user, digitais_hash)
        resumo[:atualizados] += 1
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      log("ERRO — cpf=#{cpf} matricula=#{matricula}: #{e.message}")
      resumo[:erros] += 1
    end
  end

  def encontrar_user(cpf:, matricula:)
    user = User.find_by(cpf: cpf) if cpf.present?
    user ||= User.find_by(username: matricula) if matricula.present?
    user
  end

  def atualizar_digital(user, digitais_hash)
    return if @dry_run

    user.update!(digitais_hash: digitais_hash)
    log("ATUALIZADO — id=#{user.id} cpf=#{user.cpf} username=#{user.username}")
  end

  def log(mensagem)
    File.open(@log_path, 'a') do |f|
      f.puts("[#{Time.current.strftime('%Y-%m-%d %H:%M:%S')}] #{mensagem}")
    end
    Rails.logger.info("[SyncDigitais] #{mensagem}")
  end
end
