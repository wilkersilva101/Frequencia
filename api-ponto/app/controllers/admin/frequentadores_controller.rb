module Admin
  class FrequentadoresController < Admin::ApplicationController
    # Unidade piloto da Sprint 10B (SPRINT-PLAN.md, task 10B.1) — lotação
    # principal do usuário que conduziu a validação, 87 servidores. Expandir
    # para múltiplas unidades/todos os órgãos é escopo de sprint futura, não
    # decidido ainda — por isso fixo aqui em vez de um seletor de unidade.
    UNIDADE_PILOTO_ID = 110_001_469

    # SPRINT-PLAN task 10.10: a fonte da tela deixou de ser o `User` local
    # (espelho via `FrequentadorCache`) e passou a ser TODO vínculo ativo do
    # pessoas2 (`Pessoas::Vinculo.ativos`) — inclusive quem ainda não tem
    # `User` cadastrado localmente no Frequencia. Status/Digital/ações
    # continuam vindo do `User` local (não existem no pessoas2), ligado via
    # `cpf`.
    def index
      # Task 23.7 — CanCanCan: autorização explícita para leitura.
      # Admin/gestor/operador podem visualizar.
      authorize! :read, :all
      @vinculos = Pessoas::Vinculo.frequentadores_ativos(
        nome: params[:nome],
        orgao: params[:orgao],
        categoria_trabalhador_id: params[:categoria],
        incluir_cpfs: cpfs_exigidos_pelos_filtros_locais,
        excluir_cpfs: cpfs_excluidos_pelos_filtros_locais.presence
      ).page(params[:page])

      @unidade_por_vinculo_id = Pessoas::Vinculo.unidades_por_vinculo(@vinculos.map(&:id))
      @categorias_trabalhador = Pessoas::CategoriaTrabalhador.em_uso

      # Pré-carrega todos os Users locais da página de uma vez (por cpf) em
      # vez de 1 query por linha na view.
      cpfs_da_pagina = @vinculos.filter_map { |vinculo| vinculo.pessoa&.cpf }
      @user_por_cpf = User.where(cpf: cpfs_da_pagina).index_by(&:cpf)
    end

    def reimportar_dados_pessoa
      # Task 23.7 — CanCanCan: somente admin pode reimportar dados do Pessoas.
      authorize! :manage, User

      user = User.find(params[:id])

      if user.cpf.blank?
        redirect_to frequentadores_path, alert: "Frequentador sem CPF cadastrado — não é possível reimportar do Pessoas."
        return
      end

      ImportarDadosPessoaJob.perform_later(user.id)
      redirect_to frequentadores_path, notice: "Reimportação do Pessoas iniciada para #{user.nome_completo}."
    end

    # Um clique importa a unidade inteira de uma vez (decisão do usuário
    # 2026-08-28: o polling manual não deve ser um-a-um) — distinto do
    # botão "Reimportar do Pessoas" acima, que atualiza 1 pessoa já
    # cadastrada.
    def importar_unidade
      # Task 23.7 — CanCanCan: somente admin pode importar servidores.
      authorize! :manage, User

      ImportarServidoresUnidadeJob.perform_later(UNIDADE_PILOTO_ID)
      redirect_to frequentadores_path, notice: "Importação dos servidores da unidade piloto iniciada."
    end

    private

    # Filtro "Status" (select com status exato) restringe a lista aos cpfs
    # de Users locais naquele status; filtro "Digital: Com Digital"
    # restringe aos cpfs com `digitais_hash` presente. Quando os dois estão
    # ativos ao mesmo tempo, o resultado é a interseção (AND) — calculada em
    # Ruby porque `users` (Frequencia) e `pessoas`/`vinculos` (pessoas2)
    # vivem em bancos Postgres diferentes, sem JOIN cross-database possível.
    def cpfs_exigidos_pelos_filtros_locais
      listas = [ cpfs_do_status_filtrado, cpfs_com_digital_cadastrada ].compact
      return nil if listas.empty?

      listas.reduce(:&)
    end

    def cpfs_do_status_filtrado
      return nil if params[:status_filtro].blank?

      User.where(status: params[:status_filtro]).where.not(cpf: nil).pluck(:cpf)
    end

    def cpfs_com_digital_cadastrada
      return nil unless params[:digital] == "1"

      User.where.not(digitais_hash: [ nil, "" ]).where.not(cpf: nil).pluck(:cpf)
    end

    # "Sem Digital" (seja pelo select ou pelo checkbox) vira exclusão em vez
    # de inclusão — assim um vínculo sem NENHUM User local também aparece
    # (afinal, quem não tem cadastro local também não tem digital
    # cadastrada, por definição). E "Frequentadores inativos" desmarcado
    # (padrão) oculta só quem tem User local marcado como inativo — vínculo
    # sem User local nenhum sempre aparece, por ser vínculo ativo real do
    # pessoas2.
    def cpfs_excluidos_pelos_filtros_locais
      excluir = []

      if params[:digital] == "0" || params[:sem_digital].present?
        excluir += User.where.not(digitais_hash: [ nil, "" ]).where.not(cpf: nil).pluck(:cpf)
      end

      if params[:inativos].blank?
        excluir += User.where(status: 0).where.not(cpf: nil).pluck(:cpf)
      end

      excluir.uniq
    end
  end
end
