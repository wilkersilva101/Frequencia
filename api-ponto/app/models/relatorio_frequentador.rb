class RelatorioFrequentador < ApplicationRecord
  # Sprint 18 (task 18.1) — 1 registro por usuário dentro de um
  # `RelatorioFrequenciaFinal` (AG-5). Portado de `RelatorioFrequentador.java`
  # (Intranet legada); ver `RelatorioFrequenciaFinalService` pro algoritmo de
  # geração e a fórmula do `resultado`.
  belongs_to :user
  belongs_to :relatorio_frequencia_final

  validates :saldo_bruto, :valor_retroativo, :resultado, presence: true
end
