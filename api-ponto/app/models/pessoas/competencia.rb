# Tabela `competencias` (mês/ano da folha de pagamento, por órgão). Usada
# só para localizar o(s) `id` de competência(s) de um mês/ano, e a partir
# daí buscar `gestorh_contracheque_mirrors`.
#
# Achado (task 8.13): o pessoas2 tem múltiplos órgãos (`orgao_id`) com
# competências próprias para o mesmo mês/ano — a antiga chamada
# `SticapiClient::Gestorh.competencia(mes:, ano:)` não recebia `orgao_id`
# (a API já respondia escopada ao órgão autenticado). Aqui não filtramos
# por `orgao_id` pelo mesmo motivo que o código antigo não filtrava:
# matrícula já é suficientemente específica na prática. Se isso um dia
# gerar colisão entre órgãos, é um ponto a revisar.
module Pessoas
  class Competencia < PessoasRecord
    self.table_name = "competencias"

    has_many :gestorh_contracheque_mirrors, class_name: "Pessoas::GestorhContrachequeMirror",
             foreign_key: :competencia_id, inverse_of: :competencia
  end
end
