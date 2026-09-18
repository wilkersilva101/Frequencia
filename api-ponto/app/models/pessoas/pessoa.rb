# Espelha só as colunas da tabela `pessoas` do banco do Pessoas que o
# Frequencia realmente usa (nome, cpf, username) — não replica o model
# `Pessoa` inteiro do pessoas2, que tem dezenas de associações irrelevantes
# aqui (raça, deficiências, procurações etc.).
#
# Ver app/models/pessoas_record.rb: conexão somente-leitura, sem
# INSERT/UPDATE/DELETE em nenhuma camada.
module Pessoas
  class Pessoa < PessoasRecord
    self.table_name = "pessoas"

    has_many :vinculos, class_name: "Pessoas::Vinculo", foreign_key: :pessoa_id, inverse_of: :pessoa
    has_many :afastamentos, through: :vinculos, class_name: "Pessoas::Afastamento"

    # Vínculo "ativo" no sentido usado pela antiga integração Sticapi
    # (`vinculos_ativos`): estado `em_exercicio` e sem data de fim (ou fim
    # no futuro). Uma pessoa pode ter mais de um vínculo simultâneo — igual
    # ao achado documentado na Sprint 10B sobre `vinculos_ativos` da
    # Sticapi, só que aqui não há a inconsistência Hash-vs-Array da API:
    # é sempre uma relação ActiveRecord, então `.first` já resolve o caso
    # de "pegar o vínculo ativo" sem normalização nenhuma.
    def vinculos_ativos
      vinculos.ativos
    end
  end
end
