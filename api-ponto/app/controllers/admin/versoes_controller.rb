module Admin
  class VersoesController < Admin::ApplicationController
    before_action :set_versao, only: [:edit, :update, :destroy]

    def index
      # Task 23.7 — CanCanCan: autorização explícita para listagem.
      # Admin/gestor/operador podem visualizar (todos têm :read em :all).
      authorize! :read, :all

      @versoes = Versao.order(created_at: :desc)
    end

    def new
      # Task 23.7 — CanCanCan: somente admin pode criar versões.
      authorize! :manage, Versao

      @versao = Versao.new
    end

    def create
      # Task 23.7 — CanCanCan: somente admin pode criar versões.
      authorize! :manage, Versao

      @versao = Versao.new(versao_params)
      if @versao.save
        redirect_to versoes_path, notice: "Versão criada com sucesso"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      # Task 23.7 — CanCanCan: somente admin pode editar versões.
      authorize! :manage, Versao
    end

    def update
      # Task 23.7 — CanCanCan: somente admin pode atualizar versões.
      authorize! :manage, Versao

      if @versao.update(versao_params)
        redirect_to versoes_path, notice: "Versão atualizada com sucesso"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      # Task 23.7 — CanCanCan: somente admin pode excluir versões.
      authorize! :manage, Versao

      @versao.destroy
      redirect_to versoes_path, notice: "Versão excluída com sucesso"
    end

    private

    def set_versao
      @versao = Versao.find(params[:id])
    end

    def versao_params
      params.require(:versao).permit(:numero, :novidades, :link)
    end
  end
end
