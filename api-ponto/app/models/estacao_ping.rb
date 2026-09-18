class EstacaoPing < ApplicationRecord
  # Histórico completo de heartbeats de uma EstaçãoPonto — equivalente ao
  # legado `presenca_estacaoponto_ping` (Intranet). Diferente de
  # `EstacaoPonto#ultimo_contato` (que guarda só o último contato), aqui
  # fica o histórico completo. Apenas estrutura de dados (pedido direto do
  # usuário, 2026-09-02): nenhuma lógica de "estação viva/morta" foi
  # replicada.
  belongs_to :estacao_ponto
end
