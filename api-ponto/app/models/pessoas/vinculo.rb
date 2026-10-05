# Tabela `vinculos`. Só as colunas/associações usadas pelo Frequencia:
# matrícula, estado do vínculo, lotações e tipo de vínculo (via
# configuração de cadastro). O model original do pessoas2 tem dezenas de
# `belongs_to`/`has_one` (esocial, cargo, conta bancária etc.) que não nos
# interessam aqui.
module Pessoas
  class Vinculo < PessoasRecord
    self.table_name = "vinculos"

    belongs_to :pessoa, class_name: "Pessoas::Pessoa", inverse_of: :vinculos
    belongs_to :vinculo_estado, class_name: "Pessoas::VinculoEstado", optional: true
    belongs_to :configuracao_cadastro, class_name: "Pessoas::ConfiguracaoCadastro", optional: true

    has_many :lotacoes, class_name: "Pessoas::Lotacao", foreign_key: :vinculo_id, inverse_of: :vinculo
    has_many :afastamentos, class_name: "Pessoas::Afastamento", foreign_key: :vinculo_id, inverse_of: :vinculo

    # Espelha o antigo filtro `vinculos_ativos` da Sticapi: estado
    # "em_exercicio" (nome confirmado em `vinculos_estados`, ver
    # investigação da task 8.13) e sem data de fim (ou fim ainda não
    # alcançado). Não existe mais a inconsistência Hash-vs-Array da API
    # antiga — é sempre uma relação ActiveRecord normal.
    scope :ativos, -> {
      joins(:vinculo_estado)
        .where(vinculos_estados: { nome: "em_exercicio" })
        .where("vinculos.fim IS NULL OR vinculos.fim >= ?", Date.current)
    }

    def lotacao_principal
      lotacoes.principais.merge(Pessoas::Lotacao.vigentes).order(inicio: :desc).first
    end

    # Tarefa 29.6 (Sprint 29) — lista de frequentadores VISÍVEIS por um usuário
    # (PRD §3; §9 item 1). Delegação fina para `FrequentadoresVisiveis` (o
    # object que monta o SQL e replica a cascata da 29.4): o nome
    # `frequentadores_visiveis(usuario)` é o contrato citado na 29.7
    # (`accessible_by`/index). Aditivo — não altera a `Ability` (29.7) nem o
    # PORO da 29.4.
    #
    # NÃO é um `scope :` clássico de propósito: além de ler `vinculos`, precisa
    # consultar o banco `users` (outro Postgres, sem JOIN cross-database) para
    # os passos 1/4, então a montagem vive num object dedicado e testável.
    def self.frequentadores_visiveis(usuario)
      FrequentadoresVisiveis.para(usuario)
    end

    # CPFs dos frequentadores VISÍVEIS por um usuário — o ponto de entrada
    # consumido pela `Ability` e pelos controllers de frequência na 29.7. É a
    # projeção em CPF de `frequentadores_visiveis` (o chamador precisa de CPF
    # porque a FK `time_records.user_id` aponta para `users` locais, ligados ao
    # Pessoas por `users.cpf`).
    #
    # Existe como método de classe PRÓPRIO (`def self.`, não um `scope :`) por
    # dois motivos: (1) o padrão do projeto (Sprint 10B/8.13) de isolar cada
    # consulta ao banco do Pessoas num único ponto testável/stubável — o banco
    # `pessoas_test` existe mas não tem schema carregado; e (2) a 29.7 delega a
    # regra em vez de reimplementá-la: o conjunto de CPFs visíveis vem do
    # `FrequentadoresVisiveis` (29.6), cuja equivalência com o PORO
    # `AutorizacaoFrequencia#pode_ver?` é provada item a item pela 29.6.
    def self.cpfs_frequentadores_visiveis(usuario)
      frequentadores_visiveis(usuario)
        .joins(:pessoa)
        .where.not(pessoas: { cpf: nil })
        .distinct
        .pluck("pessoas.cpf")
    end

    def tipo_vinculo
      configuracao_cadastro&.tipo_vinculo
    end

    # Fonte de "TERCEIRIZADO" do alvo — Decisão D4 do CTO (2026-09-29). É o
    # TIPO de vínculo (`tipos_vinculo.nome == "Terceirizado"`), idêntico ao
    # `TipoVinculo#terceirizado?` do pessoas2 (`app/models/tipo_vinculo.rb:234`) —
    # NÃO a categoria eSocial (`categorias_trabalhador.codigo_esocial`), que não
    # tem mapeamento determinístico.
    #
    # Semântica fixada na 29.4: QUALQUER vínculo ATIVO com tipo Terceirizado
    # torna a pessoa terceirizada (não só o "vínculo principal"). O espelho não
    # materializa `vinculo_principal`; usar `.first` sobre os ativos poderia
    # negar um terceirizado cujo vínculo Terceirizado não fosse o primeiro —
    # falso negativo (não vaza dado). Por isso o predicado é "algum vínculo
    # ativo" (consumido em `Pessoas::Pessoa#terceirizado?`).
    def terceirizado?
      tipo_vinculo&.nome == "Terceirizado"
    end

    # Ponto de entrada único para a tela `admin/frequentadores` (SPRINT-PLAN
    # task 10.10) — concentra toda a query complexa (nome, órgão, filtros de
    # User local via cpf) num só método de classe, tanto pra manter o
    # controller enxuto quanto pra dar um único lugar pra stubar nos testes
    # (banco `pessoas_test` existe mas não tem schema carregado, ver task
    # 8.13 — não dá pra criar `Pessoas::Vinculo`/`Pessoas::Pessoa` reais em
    # teste).
    #
    # `incluir_cpfs`/`excluir_cpfs` resolvem os filtros que só existem no
    # User LOCAL do Frequencia (status, digital) — calculados no controller
    # a partir da tabela `users` (outro banco Postgres, sem JOIN
    # cross-database possível) e passados aqui como listas de CPF.
    #
    # Órgão vem da lotação principal vigente, que não é um `belongs_to`
    # direto em `Vinculo` (ver `#lotacao_principal` acima, resolvido em
    # Ruby). Filtrar via subquery de IDs evita duplicar linhas de vínculo
    # que um LEFT JOIN de has_one poderia causar (uma pessoa pode, em tese,
    # ter mais de uma lotação "principal" vigente simultânea) — importante
    # porque a lista é paginada e duplicação quebraria a contagem/paginação.
    def self.frequentadores_ativos(nome: nil, orgao: nil, categoria_trabalhador_id: nil, incluir_cpfs: nil, excluir_cpfs: nil)
      scope = ativos
        .joins(:pessoa)
        .includes(:pessoa, configuracao_cadastro: { tipo_vinculo: :categoria_trabalhador })
        .order("pessoas.nome")

      scope = scope.where("pessoas.nome ILIKE ?", "%#{nome}%") if nome.present?

      if orgao.present?
        vinculo_ids_no_orgao = Pessoas::Lotacao.principais.merge(Pessoas::Lotacao.vigentes)
          .joins(:unidade)
          .where("unidades.descricao ILIKE ?", "%#{orgao}%")
          .select(:vinculo_id)

        scope = scope.where(id: vinculo_ids_no_orgao)
      end

      if categoria_trabalhador_id.present?
        scope = scope.joins(configuracao_cadastro: :tipo_vinculo)
          .where(tipos_vinculo: { categoria_trabalhador_id: categoria_trabalhador_id })
      end

      scope = scope.where(pessoas: { cpf: incluir_cpfs }) if incluir_cpfs
      scope = scope.where.not(pessoas: { cpf: excluir_cpfs }) if excluir_cpfs.present?

      scope
    end

    # Mesmo filtro de nome de `frequentadores_ativos` (vínculo ativo +
    # `pessoas.nome ILIKE`), exposto como lista de CPFs — usado pelo filtro
    # de "Usuário" em admin/time_records (pedido do usuário, 2026-09-02:
    # "deve funcionar da mesma maneira que o filtro Nome funciona em
    # /frequentadores"). Isolado como método de classe pra ser o único
    # ponto de entrada a stubar nos testes (mesmo motivo dos métodos acima).
    def self.cpfs_por_nome(nome)
      return [] if nome.blank?

      ativos.joins(:pessoa).where("pessoas.nome ILIKE ?", "%#{nome}%").distinct.pluck("pessoas.cpf")
    end

    # Lista de órgãos (unidade da lotação principal vigente) entre os
    # vínculos ativos — substitui `FrequentadorCache.distinct.pluck(:orgao)`
    # em admin/frequencia_por_orgao (pedido do usuário, 2026-09-02: trocar
    # leitura de espelho local por SELECT ao vivo no pessoas2).
    def self.orgaos_em_uso
      Pessoas::Lotacao.principais.merge(Pessoas::Lotacao.vigentes)
        .where(vinculo_id: ativos.select(:id))
        .joins(:unidade)
        .distinct
        .pluck("unidades.descricao")
        .compact
        .sort
    end

    # CPFs dos vínculos ativos cuja lotação principal vigente é o órgão
    # informado (comparação exata — o chamador já resolveu o nome via
    # `orgaos_em_uso`). Substitui `FrequentadorCache.where(orgao:).pluck(:cpf)`.
    def self.cpfs_por_orgao(orgao)
      return [] if orgao.blank?

      vinculo_ids = Pessoas::Lotacao.principais.merge(Pessoas::Lotacao.vigentes)
        .joins(:unidade)
        .where(unidades: { descricao: orgao })
        .select(:vinculo_id)

      ativos.where(id: vinculo_ids).joins(:pessoa).distinct.pluck("pessoas.cpf")
    end

    # Lotação principal vigente pré-carregada em lote pros vínculos de uma
    # página (não é um `belongs_to` simples — ver `#lotacao_principal`).
    # Evita 1 query por linha na view; isolado como método de classe pra
    # poder ser stubado nos testes do controller (mesmo motivo do método
    # acima).
    def self.unidades_por_vinculo(vinculo_ids)
      return {} if vinculo_ids.blank?

      Pessoas::Lotacao.principais.merge(Pessoas::Lotacao.vigentes)
        .where(vinculo_id: vinculo_ids)
        .includes(:unidade)
        .order(inicio: :desc)
        .group_by(&:vinculo_id)
        .transform_values { |lotacoes| lotacoes.first&.unidade }
    end
  end
end
