# Tabela `afastamentos`. A coluna `id_intranet` é a chave central desta
# migração: é literalmente o mesmo `id` que `SticapiClient::Intranet
# .afastamentos` retornava (confirmado contra dados reais — ver task 8.13),
# então `AfastamentoCache#afastamento_id_pessoas` continua podendo usá-la
# como identificador estável, só que lendo direto da coluna em vez de vir
# de um payload HTTP.
#
# `cargo`/`lotacao`/`status` do AfastamentoCache continuam não vindo daqui
# (mesma limitação documentada em sincronizar_afastamentos_job.rb desde a
# versão Sticapi) — não inventamos de onde tirar esses campos.
module Pessoas
  class Afastamento < PessoasRecord
    self.table_name = "afastamentos"

    belongs_to :vinculo, class_name: "Pessoas::Vinculo", inverse_of: :afastamentos
    belongs_to :tipo_afastamento, class_name: "Pessoas::TipoAfastamento", optional: true
  end
end
