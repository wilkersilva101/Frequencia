class RegistroEstacaoPonto < ApplicationRecord
  # Log de cada sincronização recebida de uma EstaçãoPonto — equivalente ao
  # legado `presenca_registroestacaoponto` (Intranet). Apenas estrutura de
  # dados (pedido direto do usuário, 2026-09-02): nenhuma lógica de
  # processamento foi replicada aqui.
  belongs_to :estacao_ponto

  validates :processado, inclusion: { in: [ true, false ] }
end
