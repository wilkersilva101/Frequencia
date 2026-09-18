class EstacaoPonto < ApplicationRecord
  self.table_name = "estacoes_ponto"

  # Sprint 1 (Task 1.4): valor-sentinela enviado pela EstaçãoPonto desktop
  # como `codAtivacao` quando ela própria detecta um sistema operacional não
  # suportado (ver `presenca/validar_frequentador_controller.rb` e
  # `presenca/sincronizar_registros_ponto_controller.rb`, herdado do
  # comportamento pré-existente da PoC). Não corresponde a uma estação real
  # cadastrada — é tratado como sempre válido para preservar o protocolo já
  # em uso pelo client desktop (ADR-0003: nenhuma mudança de protocolo).
  CODIGO_SISTEMA_OPERACIONAL_NAO_SUPORTADO = "SistemaOperacionalNaoSuportado".freeze

  # Estrutura de dados replicada do legado Intranet (`presenca_estacaoponto`)
  # (pedido direto do usuário, 2026-09-02 — ver SPRINT-PLAN.md).
  has_many :registro_estacao_pontos, dependent: :destroy
  has_many :estacao_pings, dependent: :destroy

  validates :descricao, presence: true
  validates :cod_ativacao, presence: true, uniqueness: { case_sensitive: false }

  IP_PATTERN = /(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/

  # Legado (`EstacaoPonto-explore.jsp`): a coluna VNC não é um campo próprio
  # da estação, é o IP extraído do último `RegistroEstacaoPonto` recebido
  # dela (`ep.ultimoRegistroEstacaoPonto.ipEnxuto`).
  def ultimo_registro_estacao_ponto
    if registro_estacao_pontos.loaded?
      registro_estacao_pontos.max_by { |r| r.momento_sinc || Time.at(0) }
    else
      registro_estacao_pontos.order(momento_sinc: :desc).first
    end
  end

  def vnc_ip
    ip = ultimo_registro_estacao_ponto&.ip
    return nil if ip.blank?

    ip[IP_PATTERN]
  end

  # Sprint 1 (Task 1.4): substitui a antiga whitelist hardcoded
  # (`%w[poc-ativacao-001 SistemaOperacionalNaoSuportado]`) por validação
  # contra estações reais cadastradas, mantendo o sentinela de OS não
  # suportado como caso especial do protocolo (ver constante acima).
  def self.codigo_ativacao_valido?(codigo)
    return false if codigo.blank?

    codigo == CODIGO_SISTEMA_OPERACIONAL_NAO_SUPORTADO ||
      where("lower(cod_ativacao) = ?", codigo.downcase).exists?
  end

  # Sprint 1 (Task 1.4): registra o contato mais recente de uma estação real
  # (heartbeat via EP-06 `AdicioneEstacao`). Não faz nada para o sentinela de
  # OS não suportado, pois ele não corresponde a uma estação cadastrada.
  def self.registrar_contato(codigo, versao: nil)
    return nil if codigo.blank? || codigo == CODIGO_SISTEMA_OPERACIONAL_NAO_SUPORTADO

    estacao = find_by("lower(cod_ativacao) = ?", codigo.downcase)
    return nil unless estacao

    atributos = { ultimo_contato: Time.current }
    atributos[:versao] = versao if versao.present?
    estacao.update!(atributos)
    estacao
  end
end
