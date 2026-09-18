module Presenca
  class SincronizarRegistrosPontoController < ApiController
    # Sprint R (R.4): compatibilidade retroativa ADR-08/ADR-001 — a Estação
    # ainda não envia `punch_type` na prática (sem cadastro/biometria real),
    # então este valor segue sendo o caminho de fallback, não o primário.
    VALID_PUNCH_TYPES = %w[entry exit].freeze

    # Deduplicação: o leitor biométrico captura em loop enquanto o dedo
    # estiver no sensor (ver PreProcessandoService, lado Estação) — se o
    # usuário não tirar o dedo a tempo, a mesma passagem física gera duas
    # requisições de sincronização com o MESMO punched_at (mesmo segundo
    # exato, herdado do relógio da Estação no momento da captura). Sem essa
    # checagem, cada uma consultava PunchTypeService.determine antes da
    # outra terminar de persistir, e as duas liam o mesmo "último registro"
    # — resultando em duas entradas (ou duas saídas) seguidas.
    #
    # Importante: a checagem é por punched_at EXATO, não por proximidade de
    # created_at — um login manual seguido de uma batida biométrica segundos
    # depois (ou vice-versa) é uma batida legítima e diferente, com
    # punched_at próprio, e não pode ser descartada.

    def create
      # Sprint 1 (Task 1.4): antes validava contra uma whitelist hardcoded de
      # códigos de ativação; agora valida contra estações reais cadastradas
      # em `EstacaoPonto` (mesma resposta/formato do protocolo, apenas a
      # fonte do dado mudou — ver ADR-0003).
      unless EstacaoPonto.codigo_ativacao_valido?(params[:codAtivacao])
        return render plain: "sincronizado"
      end

      # Sprint 13 (task 13.1): guarda de qual estação veio o lote, pra grid
      # admin/frequencia poder exibir a coluna "Estação". `find_by` (não
      # `find_by!`) porque o sentinela de OS não suportado é válido no
      # `codigo_ativacao_valido?` acima mas não corresponde a uma linha
      # real — nesse caso `estacao_ponto` fica nil, e o `TimeRecord` grava
      # sem esse vínculo (coluna nullable).
      estacao_ponto = EstacaoPonto.find_by("lower(cod_ativacao) = ?", params[:codAtivacao].to_s.downcase)

      registros_raw = params[:registros].to_s
      registros_decrypted = decrypt_registros(registros_raw)
      # A Estação junta os registros com ";" (ArquivoRegistros.lerArquivo,
      # não com quebra de linha — nunca houve "\n" nesse payload de verdade.
      linhas = registros_decrypted.split(";").map(&:strip).reject(&:empty?)

      registros_aceitos = []
      registros_rejeitados = []

      # B1 (Code Review Iteration 7): loop envolto em transação para garantir
      # que nenhum registro seja persistido parcialmente se uma linha falhar.
      # O `create!` dentro do loop levanta exceção em caso de erro, o que
      # aciona o rollback automático da transação.
      ApplicationRecord.transaction do
        linhas.each do |linha|
        # Campo `punch_type` explícito opcional (ADR-001, Seção 3), separado
        # por "-" ao final da linha, ex: "1-15:07:2026:14:30:45-entry".
        parts = linha.match(/\A(\d+)-(\d{2}:\d{2}:\d{4}:\d{2}:\d{2}:\d{2})(?:-(\w+))?\z/)
        unless parts
          registros_rejeitados << { linha: linha, erro: "Formato de linha inválido" }
          next
        end

        user_id = parts[1].to_i
        punched_at = Time.zone.strptime(parts[2], "%d:%m:%Y:%H:%M:%S")
        explicit_punch_type = parts[3]

        # Sprint R (R.6): o matching biométrico em si (hash MD5, download de
        # digitais) já foi feito do lado da Estação/DynFrequentadoresEstacao
        # (Sprint 3/4) antes do envio — o `user_id` na linha É o resultado
        # desse matching. Aqui apenas garantimos o vínculo com um cadastro
        # válido (FK não nula); não reimplementamos o matching biométrico.
        user = User.find_by(id: user_id)
        unless user
          registros_rejeitados << {
            linha: linha,
            erro: "Usuário não encontrado para o identificador #{user_id}"
          }
          next
        end

        if TimeRecord.where(user_id: user.id, punched_at: punched_at).exists?
          registros_rejeitados << {
            linha: linha,
            erro: "Batida duplicada ignorada (mesmo usuário e mesmo instante já registrados)"
          }
          next
        end

        punch_type_is_explicit = VALID_PUNCH_TYPES.include?(explicit_punch_type)

        punch_type = if punch_type_is_explicit
          # Fonte de verdade explícita: não consulta o PunchTypeService (ADR-001).
          explicit_punch_type
        else
          # Fallback (ADR-08): valor ausente ou inválido é tratado como ausente.
          begin
            PunchTypeService.determine(user_id, punched_at)
          rescue => e
            Rails.logger.warn "[PunchTypeService] Erro para user #{user_id}: #{e.message}"
            nil
          end
        end

        record = TimeRecord.create!(
          user_id: user.id,
          raw_data: linha,
          punched_at: punched_at,
          authentication_mode: params[:authenticationMode] == "manual" ? "manual" : "biometric",
          punch_type: punch_type,
          # Sprint R (R.5): auditoria — true quando o valor veio do payload,
          # false quando foi inferido pelo PunchTypeService (fallback ADR-08).
          punch_type_explicit: punch_type_is_explicit,
          estacao_ponto: estacao_ponto
        )

        registros_aceitos << {
          user_id: user.id,
          nome: user.nome_completo,
          foto: foto_payload(user),
          horario: record.punched_at.strftime("%d/%m/%Y %H:%M:%S"),
          punch_type: record.punch_type
        }
      end # each
    end # transaction

      # Sprint R (R.6-ajuste): a lógica de aceite/rejeição roda sempre, de
      # forma idêntica, independente do formato de saída — apenas a
      # representação da resposta muda a seguir (content negotiation).
      if formato_rico_solicitado?
        # Sprint R (R.6): sinaliza rejeição de forma explícita para a Estação
        # (ADR-001, Seção 3) em vez de descartar silenciosamente — segue o
        # padrão de status já usado pelos controllers administrativos do
        # projeto (`Admin::UsersController`/`Admin::SessionsController`).
        status = registros_rejeitados.any? ? :unprocessable_entity : :ok

        render json: {
          status: "sincronizado",
          registros_aceitos: registros_aceitos,
          registros_rejeitados: registros_rejeitados
        }, status: status
      else
        # Sprint R (R.6-ajuste): compatibilidade retroativa — o client Java
        # da Estação (fora deste repositório) ainda espera o texto puro
        # "sincronizado" desde a Sprint 5. Sem sinalização explícita de que
        # quer o formato rico, a resposta e o status HTTP permanecem
        # idênticos ao comportamento anterior a R.6 (sempre 200/"sincronizado"),
        # mesmo que existam registros rejeitados no lote — a rejeição
        # silenciosa de itens individuais já era o comportamento pré-R.6.
        render plain: "sincronizado"
      end
    rescue StandardError => e
      # B1 (Code Review Iteration 7): loga o erro real, retorna formato
      # adequado conforme content negotiation, e garante rollback da
      # transação (nenhum registro persistido parcialmente).
      Rails.logger.error "[SincronizarRegistrosPonto] Erro no lote: #{e.message}"

      if formato_rico_solicitado?
        render json: { status: "erro", message: e.message }, status: :unprocessable_entity
      else
        render plain: "sincronizado"
      end
    end

    private

    # Sprint R (R.6-ajuste): content negotiation — o client sinaliza que
    # quer o contrato JSON rico (nome/foto/horario) via header HTTP padrão
    # `Accept: application/json` OU via parâmetro explícito `confirmacaoVisual=1`,
    # seguindo a convenção de nomenclatura em português já usada pelos demais
    # parâmetros do módulo Presença (`codAtivacao`, `codigoUnicoMaquina`).
    # Sem nenhuma das duas sinalizações, o padrão é sempre o texto puro
    # legado, preservando o client Java existente.
    def formato_rico_solicitado?
      request.format.json? || params[:confirmacaoVisual] == "1"
    end

    # Sprint R (R.6): o schema atual (`db/schema.rb`) não possui coluna de
    # foto/avatar em `users` nem ActiveStorage configurado no projeto — não
    # inventamos esse campo. A resposta apenas sinaliza explicitamente a
    # ausência, conforme critério de aceite de R.6, para a Estação tratar o
    # caso graciosamente na confirmação visual.
    def foto_payload(user)
      {
        disponivel: false,
        url: nil,
        motivo: "Foto não cadastrada para o usuário #{user.id}"
      }
    end

    def decrypt_registros(raw)
      return raw if raw.blank?

      begin
        CryptoDes.decrypt(raw)
      rescue
        raw
      end
    end
  end
end
