# Tabela `vinculos_estados` (pluralização irregular no pessoas2 — não é
# `vinculo_estados`, conferido em db/schema.rb). Guarda o estado do vínculo
# (ex: "em_exercicio", "encerrado").
module Pessoas
  class VinculoEstado < PessoasRecord
    self.table_name = "vinculos_estados"
  end
end
