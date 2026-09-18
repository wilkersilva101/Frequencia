module Admin
  class RegimesController < Admin::ApplicationController
    before_action :set_regime, only: [:edit, :update, :destroy]

    def index
      # Task 23.7 — CanCanCan: autorização explícita para listagem.
      # Admin/gestor/operador podem visualizar (todos têm :read em :all).
      authorize! :read, :all

      # Mesmo filtro real do legado (`RegimeDao.paginateList`): só mostra
      # regimes ativos (não excluídos, marcados como visíveis) e que não
      # tenham sido substituídos por uma versão mais nova (não são
      # `anterior_id` de nenhum regime não-excluído).
      @regimes = Regime.includes(:regime_categorias)
        .where(excluido: false, visivel: true)
        .where.not(id: Regime.where(excluido: false).where.not(anterior_id: nil).select(:anterior_id))
        .order(:nome)

      if params[:nome].present?
        @regimes = @regimes.where("nome ILIKE ?", "%#{params[:nome]}%")
      end

      if params[:categoria].present?
        @regimes = @regimes.joins(:regime_categorias).where(regime_categorias: { categoria: params[:categoria] })
      end

      if params[:modalidade].present?
        @regimes = @regimes.where(modalidade: params[:modalidade])
      end
    end

    def new
      # Task 23.7 — CanCanCan: somente admin pode criar regimes.
      authorize! :manage, Regime

      @regime = Regime.new
    end

    def create
      # Task 23.7 — CanCanCan: somente admin pode criar regimes.
      authorize! :manage, Regime

      @regime = Regime.new(regime_params)
      if @regime.save
        redirect_to regimes_path, notice: "Regime criado com sucesso"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      # Task 23.7 — CanCanCan: somente admin pode editar regimes.
      authorize! :manage, Regime
    end

    def update
      # Task 23.7 — CanCanCan: somente admin pode atualizar regimes.
      authorize! :manage, Regime

      if @regime.update(regime_params)
        redirect_to regimes_path, notice: "Regime atualizado com sucesso"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      # Task 23.7 — CanCanCan: somente admin pode excluir regimes.
      authorize! :manage, Regime

      @regime.destroy
      redirect_to regimes_path, notice: "Regime excluído com sucesso"
    rescue ActiveRecord::DeleteRestrictionError
      redirect_to regimes_path, alert: "Não é possível excluir regime com frequentadores vinculados"
    end

    private

    def set_regime
      @regime = Regime.find(params[:id])
    end

    def regime_params
      params.require(:regime).permit(:nome, :modalidade, :resumo, :meta_semanal, categorias: [])
    end
  end
end
