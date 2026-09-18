# Tabela `tipos_afastamento`. Só usamos `nome` (ex: "Licença para tratamento
# de saúde") — equivalente ao antigo campo `dados["afastamento"]` retornado
# por `SticapiClient::Intranet.afastamentos`.
module Pessoas
  class TipoAfastamento < PessoasRecord
    self.table_name = "tipos_afastamento"
  end
end
