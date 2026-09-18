# Tabela `configuracoes_cadastro`. Ponte entre `vinculos` e `tipos_vinculo`
# no pessoas2 (`Vinculo belongs_to :configuracao_cadastro`,
# `has_one :tipo_vinculo, through: :configuracao_cadastro`) — replicamos só
# essa ponte, não o resto das regras de cadastro condicional do model
# original.
module Pessoas
  class ConfiguracaoCadastro < PessoasRecord
    self.table_name = "configuracoes_cadastro"

    belongs_to :tipo_vinculo, class_name: "Pessoas::TipoVinculo", optional: true
  end
end
