module Admin
  class FrequentadoresController < Admin::ApplicationController
    # Unidade piloto da Sprint 10B (SPRINT-PLAN.md, task 10B.1) — lotação
    # principal do usuário que conduziu a validação, 87 servidores. Expandir
    # para múltiplas unidades/todos os órgãos é escopo de sprint futura, não
    # decidido ainda — por isso fixo aqui em vez de um seletor de unidade.
    UNIDADE_PILOTO_ID = 110_001_469

    def index
      if params[:status_filtro].present?
        @frequentadores = User.where(status: params[:status_filtro])
      elsif params[:inativos].present?
        @frequentadores = User.all
      else
        @frequentadores = User.ativos
      end

      @frequentadores = @frequentadores.includes(:frequentador_cache).order(:nome_completo)

      if params[:nome].present?
        @frequentadores = @frequentadores.where("nome_completo ILIKE ?", "%#{params[:nome]}%")
      end

      if params[:digital].present?
        if params[:digital] == "1"
          @frequentadores = @frequentadores.where.not(digitais_hash: [nil, ""])
        elsif params[:digital] == "0"
          @frequentadores = @frequentadores.where(digitais_hash: [nil, ""])
        end
      elsif params[:sem_digital].present?
        @frequentadores = @frequentadores.where(digitais_hash: [nil, ""])
      end

      if params[:orgao].present?
        @frequentadores = @frequentadores.joins(:frequentador_cache).where("frequentador_caches.orgao ILIKE ?", "%#{params[:orgao]}%")
      end

      @frequentadores = @frequentadores.page(params[:page])
    end

    def reimportar_dados_pessoa
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
      ImportarServidoresUnidadeJob.perform_later(UNIDADE_PILOTO_ID)
      redirect_to frequentadores_path, notice: "Importação dos servidores da unidade piloto iniciada."
    end
  end
end

