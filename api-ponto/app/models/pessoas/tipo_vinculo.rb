# Tabela `tipos_vinculo`. Usamos `nome` (ex: "Efetivo", "Comissionado")
# — equivalente ao antigo `vinculos_ativos[0].tipo_vinculo.nome` da Sticapi —
# e `categoria_trabalhador` (fonte real do filtro de Categoria em
# `admin/frequentadores`, ver SPRINT-PLAN task 10.11).
module Pessoas
  class TipoVinculo < PessoasRecord
    self.table_name = "tipos_vinculo"

    belongs_to :categoria_trabalhador, class_name: "Pessoas::CategoriaTrabalhador", optional: true
  end
end
