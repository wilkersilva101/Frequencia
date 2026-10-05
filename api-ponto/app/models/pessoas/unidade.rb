# Tabela `unidades`. Só usamos `descricao` (nome de exibição do órgão/lotação
# — mesmo campo lido no antigo `lotacao_principal.unidade.descricao` da
# Sticapi).
module Pessoas
  class Unidade < PessoasRecord
    self.table_name = "unidades"

    has_many :lotacoes, class_name: "Pessoas::Lotacao", foreign_key: :unidade_id, inverse_of: :unidade

    belongs_to :gestor, class_name: "Pessoas::Pessoa", optional: true
    belongs_to :gestor_substituto, class_name: "Pessoas::Pessoa", optional: true
    belongs_to :gestor_excepcional, class_name: "Pessoas::Pessoa", optional: true

    ServidorLotado = Struct.new(:matricula, :nome, keyword_init: true)

    def gestor?(pessoa)
      return false if pessoa.blank?

      gestor == pessoa || gestor_substituto == pessoa || gestor_excepcional == pessoa
    end

    # O Pessoas2 persiste a árvore no formato materialized path: a folha guarda
    # os IDs dos ancestrais da raiz até o pai, separados por `/`. Como este
    # espelho não usa a gem `ancestry`, a validação e a busca são mantidas
    # localmente; um caminho inválido falha fechado devolvendo apenas a própria
    # unidade, evitando liberar acesso com uma hierarquia corrompida.
    def cadeia_ascendente
      return [ self ] if ancestry.blank?

      ancestor_ids = ancestry.to_s.split("/", -1).reverse
      return [ self ] unless ancestor_ids.all? { |ancestor_id| ancestor_id.match?(/\A\d+\z/) }

      # Compara DEPOIS do `to_i` (Bug 1 do Bug Finder da 29.1): o regex aceita
      # "05", e "05" != "5" numa comparação de string — a auto-referência com
      # zero à esquerda passava batido e a própria unidade reaparecia na cadeia.
      # Comparar inteiros normaliza "5" e "05" para o mesmo id.
      ancestor_ids = ancestor_ids.map(&:to_i)
      return [ self ] if id.present? && ancestor_ids.include?(id.to_i)

      # Path com ids repetidos é corrupção (a gem `ancestry` nunca repete um id
      # no caminho): fail-closed, sem consultar o banco (Bug 2 da 29.1). Antes
      # devolvia ancestral duplicado, inflando as checagens de `gestor?`.
      return [ self ] if ancestor_ids.uniq.size != ancestor_ids.size

      # `includes` das três associações de gestor evita N+1 na cascata da 29.4
      # (MEDIUM-1 do review da 29.1): cada `gestor?` sobre um ancestral não
      # dispara 3 queries por unidade.
      ancestors_by_id = self.class
        .where(id: ancestor_ids)
        .includes(:gestor, :gestor_substituto, :gestor_excepcional)
        .to_a
        .index_by { |ancestor| ancestor.id.to_s }

      # D6 (CTO, 2026-09-25): um ancestral ausente é PULADO (a subida continua —
      # o path é a fonte da estrutura) e gera log estruturado, para que o salto
      # não seja silencioso e alimente o shadow da 29.7/29.8.
      ancestor_ids.each do |ancestor_id|
        next if ancestors_by_id.key?(ancestor_id.to_s)

        Rails.logger.warn(
          evento: "autorizacao_frequencia.ancestral_ausente",
          unidade_id: id,
          ancestral_id: ancestor_id
        )
      end

      [ self ] + ancestor_ids.filter_map { |ancestor_id| ancestors_by_id[ancestor_id.to_s] }
    end

    # Regra D6 (decisão do CTO, 2026-09-25) — uma unidade é ELEGÍVEL para liberar
    # acesso pelos seus gestores sse estiver ativa (`active`, default `false` no
    # Pessoas2) E sem extinção consumada (`data_extincao_serventia` ausente ou no
    # futuro). Unidade inativa ou de órgão extinto não tem autoridade corrente:
    # seus gestores não liberam acesso, embora a CADEIA estrutural continue
    # subindo por elas (ausente/inativa não interrompe a subida — o path é a
    # fonte da estrutura; interromper negaria acesso legítimo aos superiores).
    def elegivel?
      return false if active != true

      data_extincao_serventia.nil? || data_extincao_serventia > Date.current
    end

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
