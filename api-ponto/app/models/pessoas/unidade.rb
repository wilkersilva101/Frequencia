# Tabela `unidades`. Só usamos `descricao` (nome de exibição do órgão/lotação
# — mesmo campo lido no antigo `lotacao_principal.unidade.descricao` da
# Sticapi).
module Pessoas
  class Unidade < PessoasRecord
    self.table_name = "unidades"

    has_many :lotacoes, class_name: "Pessoas::Lotacao", foreign_key: :unidade_id, inverse_of: :unidade

    ServidorLotado = Struct.new(:matricula, :nome, keyword_init: true)

    # Servidores com lotação principal e vigente nesta unidade — equivalente
    # ao antigo `unidade.dig("servidores")` da Sticapi (matrícula + nome,
    # sem CPF; ver ResolverCpfPorMatriculaService para resolver o CPF).
    # Isolado num método próprio (em vez de inline no job) para poder ser
    # stubado nos testes sem precisar de schema populado no banco `pessoas`
    # de teste.
    def servidores
      lotacoes.principais.merge(Pessoas::Lotacao.vigentes).includes(vinculo: :pessoa).filter_map do |lotacao|
        vinculo = lotacao.vinculo
        next if vinculo.blank?

        ServidorLotado.new(matricula: vinculo.matricula, nome: vinculo.pessoa&.nome)
      end
    end
  end
end
