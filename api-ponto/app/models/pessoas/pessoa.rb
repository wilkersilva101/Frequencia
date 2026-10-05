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

    # Usuários locais sem CPF são contas administrativas e não têm uma
    # pessoa correspondente no Pessoas; nesse caso a busca deve apenas
    # retornar nil, sem consultar o banco espelho.
    def self.por_user(user)
      normalized_cpf = user&.cpf.to_s.gsub(/\D/, "")
      return if normalized_cpf.blank?

      find_by(cpf: normalized_cpf)
    end

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

    # Predicado de TERCEIRIZADO do alvo (Decisão D4 do CTO, 2026-09-29). Regra:
    # a pessoa é terceirizada se ALGUM vínculo ATIVO tem tipo de vínculo
    # "Terceirizado" (`Pessoas::Vinculo#terceirizado?`). Não é o "vínculo
    # principal" — o espelho não o materializa, e o espelho do Pessoas2 casa o
    # conceito com "vínculo ativo" (Sprint 10B, `.first`). A escolha por "algum"
    # evita o falso-negativo do alvo com múltiplos vínculos ativos.
    def terceirizado?
      vinculos_ativos.any?(&:terceirizado?)
    end
  end
end
