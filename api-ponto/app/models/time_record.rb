class TimeRecord < ApplicationRecord
  belongs_to :user
  # Sprint 13 (task 13.1): optional porque registros antigos (antes desta
  # migration) e o sentinela de OS não suportado (ver
  # EstacaoPonto::CODIGO_SISTEMA_OPERACIONAL_NAO_SUPORTADO) não têm uma
  # EstacaoPonto real associada.
  belongs_to :estacao_ponto, optional: true

  # Sprint 19 (task 19.1, UC-08 — batida_manual; task 19.2, UC-09 —
  # desconsiderar!/reconsiderar!): um TimeRecord pode acumular mais de uma
  # IntervencaoFrequencia ao longo do tempo (ex.: criado por batida manual
  # e depois desconsiderado, ou desconsiderado e reconsiderado em
  # seguida) — por isso `has_many`, não `has_one` (era `has_one` na 19.1,
  # quando só existia o vínculo 1:1 de criação via batida manual). Vazio
  # para batidas normais (biometria/estação) sem nenhuma intervenção ainda
  # e sempre vazio pra errata (que nesta sprint não cria/referencia
  # TimeRecord).
  has_many :intervencoes_frequencia, class_name: "IntervencaoFrequencia", dependent: :nullify

  validates :raw_data, presence: true
  validates :punched_at, presence: true
  validates :authentication_mode, presence: true, inclusion: { in: %w[biometric manual] }
  validates :punch_type, inclusion: { in: %w[entry exit], allow_nil: true }

  scope :by_date, ->(date) { where(punched_at: date.beginning_of_day..date.end_of_day) }

  # Sprint 19 (task 19.2, UC-09) — marca este registro como desconsiderado
  # do cálculo diário, portado de `RegistroFrequencia#desconsiderar`
  # (intranet, linhas 300-318). O registro continua existindo/visível
  # (não é soft-delete) — só ganha `ressalva: true` (sinalização visual de
  # pendência/observação) e `desconsiderado: true` (excluído do cálculo,
  # ver `CalculoDiarioService::EstrategiaBase#registros`). Cria uma
  # `IntervencaoFrequencia` de auditoria já `status: "registrado"` (a ação
  # é efetiva na hora, sem workflow de aprovação pendente — diferente da
  # "errata" da 19.1). `justificativa` é obrigatória (mesma assinatura do
  # legado: `desconsiderar(justificativa, responsavel)`).
  def desconsiderar!(justificativa:, responsavel:)
    transaction do
      update!(desconsiderado: true, ressalva: true)
      IntervencaoFrequencia.create!(
        user: user,
        responsavel: responsavel,
        tipo: "desconsideracao_ponto",
        justificativa: justificativa,
        momento: punched_at,
        punch_type: punch_type,
        time_record: self,
        status: "registrado"
      )
    end
  end

  # Sprint 19 (task 19.2, UC-09) — desfaz `desconsiderar!`, portado de
  # `RegistroFrequencia#reconsiderar` (intranet, linhas 340-358): volta
  # `desconsiderado: false`/`ressalva: false` (registro passa a contar no
  # cálculo normalmente de novo) e cria a `IntervencaoFrequencia` própria
  # ("reconsideracao_ponto"). Sem `justificativa` obrigatória — o legado
  # não recebe `intervencaoObs` neste método (diferente de
  # `desconsiderar`).
  def reconsiderar!(responsavel:)
    transaction do
      update!(desconsiderado: false, ressalva: false)
      IntervencaoFrequencia.create!(
        user: user,
        responsavel: responsavel,
        tipo: "reconsideracao_ponto",
        momento: punched_at,
        punch_type: punch_type,
        time_record: self,
        status: "registrado"
      )
    end
  end

  # Sprint 19 (task 19.4, UC-11) — marca este registro como desconsiderado
  # do cálculo por ter sido batido numa estação de prédio não autorizado
  # pro frequentador, portado de
  # `RegistroFrequencia#desconsiderarPorPredioNaoPermitido` (intranet,
  # linhas 320-338). Reaproveita o mesmo efeito de `desconsiderar!`
  # (`desconsiderado: true`, `ressalva: true`, exclusão do cálculo via
  # `CalculoDiarioService::EstrategiaBase#registros`) — não duplica essa
  # lógica, só troca o `tipo`/`justificativa` da `IntervencaoFrequencia`
  # de auditoria criada. `justificativa` é gerada automaticamente
  # referenciando a estação (o legado não pede texto livre pra esse
  # motivo específico, é sempre a mesma constatação objetiva); ainda
  # assim aceita um `justificativa:` customizado opcional pra não travar
  # um caso em que o responsável queira detalhar mais o motivo.
  def desconsiderar_por_predio!(estacao_ponto:, responsavel:, justificativa: nil)
    transaction do
      update!(desconsiderado: true, ressalva: true)
      IntervencaoFrequencia.create!(
        user: user,
        responsavel: responsavel,
        tipo: "desconsideracao_predio",
        justificativa: justificativa.presence ||
          "Ponto desconsiderado: servidor bateu na estação #{estacao_ponto.descricao}, prédio não autorizado",
        momento: punched_at,
        punch_type: punch_type,
        time_record: self,
        status: "registrado"
      )
    end
  end

  def self.last_today(user_id)
    where(user_id: user_id, punched_at: Time.zone.now.beginning_of_day..Time.zone.now.end_of_day)
      .order(punched_at: :desc, created_at: :desc)
      .first
  end

  # Última batida do dia entre TODOS os usuários (não filtra por user_id) —
  # usada nas telas de status da Estação (IniciarPonto/PontoDePresenca) para
  # refletir quem de fato bateu o ponto por último, seja via biometria,
  # "Simular digital" ou login manual.
  def self.last_punched_today
    by_date(Time.zone.now).order(punched_at: :desc, created_at: :desc).first
  end
end
