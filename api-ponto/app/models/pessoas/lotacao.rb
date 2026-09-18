# Tabela `lotacoes`: liga um vínculo a uma unidade, com vigência
# (inicio/fim) e uma flag `principal` (uma pessoa pode ter lotação
# excepcional além da principal). Equivalente ao antigo
# `lotacao_principal` da Sticapi.
module Pessoas
  class Lotacao < PessoasRecord
    self.table_name = "lotacoes"

    belongs_to :vinculo, class_name: "Pessoas::Vinculo", inverse_of: :lotacoes
    belongs_to :unidade, class_name: "Pessoas::Unidade", inverse_of: :lotacoes

    scope :principais, -> { where(principal: true) }
    scope :vigentes, -> { where("lotacoes.fim IS NULL OR lotacoes.fim >= ?", Date.current) }
  end
end
