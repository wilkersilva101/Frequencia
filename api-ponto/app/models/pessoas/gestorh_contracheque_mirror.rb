# Tabela `gestorh_contracheque_mirrors`: espelho local (dentro do próprio
# pessoas2) da folha de pagamento do GestoRH por competência — é a mesma
# fonte de dados que `SticapiClient::Gestorh.competencia(mes:, ano:)`
# expunha via HTTP, só que lendo a tabela diretamente. Colunas relevantes:
# `competencia_id` (join com `competencias`), `matricula`, `cpf`.
module Pessoas
  class GestorhContrachequeMirror < PessoasRecord
    self.table_name = "gestorh_contracheque_mirrors"

    belongs_to :competencia, class_name: "Pessoas::Competencia"

    # Pares [matricula, cpf] de todas as competências de um mês/ano (pode
    # haver mais de uma competência por mês/ano — uma por órgão, ver nota em
    # app/models/pessoas/competencia.rb). Isolado num método de classe único
    # (em vez de inline em ResolverCpfPorMatriculaService) para poder ser
    # stubado nos testes sem precisar de schema populado no banco `pessoas`
    # de teste.
    def self.pares_matricula_cpf_para(mes:, ano:)
      competencia_ids = Pessoas::Competencia.where(mes: mes, ano: ano).pluck(:id)
      return [] if competencia_ids.empty?

      where(competencia_id: competencia_ids).pluck(:matricula, :cpf)
    end
  end
end
