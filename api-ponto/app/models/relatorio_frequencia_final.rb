class RelatorioFrequenciaFinal < ApplicationRecord
  # O inflector do Rails pluraliza "final" como "finals" (regra do inglês),
  # mas a tabela foi criada como "relatorio_frequencia_finais" (português
  # correto) — força o nome explícito pra não depender de inflection custom.
  self.table_name = "relatorio_frequencia_finais"

  # Sprint 18 (task 18.1) — relatório mensal consolidado (AG-5): um por
  # mês/ano, com um `RelatorioFrequentador` filho por usuário. Portado de
  # `RelatorioFrequenciaFinal.java` + `RelatorioFrequentador.java` +
  # `RelatorioFrequenciaFinalServices.java` (Intranet legada).
  #
  # O bean legado tinha um campo `orgao` (`//private Orgao orgao`)
  # comentado/desativado — ou seja, mesmo no legado real o relatório nunca
  # foi filtrado por órgão, é único por mês/ano. Por isso não há campo
  # `orgao` aqui e o índice único é só em `(ano, mes)`.
  has_many :relatorio_frequentadores, dependent: :destroy

  validates :ano, presence: true
  validates :mes, presence: true, inclusion: { in: 1..12 }
  validates :mes, uniqueness: { scope: :ano }
end
