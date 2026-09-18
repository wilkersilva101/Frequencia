module Admin
  class EstacoesController < Admin::ApplicationController
    before_action :set_estacao, only: [:edit, :update, :destroy]

    def index
      # Task 23.7 — CanCanCan: autorização explícita para listagem.
      # Admin/gestor/operador podem visualizar (todos têm :read em :all).
      authorize! :read, :all

      @estacoes = EstacaoPonto.includes(:registro_estacao_pontos).order(:descricao)
    end

    def new
      # Task 23.7 — CanCanCan: somente admin pode criar estações.
      authorize! :manage, EstacaoPonto

      @estacao = EstacaoPonto.new
    end

    def create
      # Task 23.7 — CanCanCan: somente admin pode criar estações.
      authorize! :manage, EstacaoPonto

      @estacao = EstacaoPonto.new(estacao_params)
      if @estacao.save
        redirect_to estacoes_path, notice: "Estação criada com sucesso"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      # Task 23.7 — CanCanCan: somente admin pode editar estações.
      authorize! :manage, EstacaoPonto
    end

    def update
      # Task 23.7 — CanCanCan: somente admin pode atualizar estações.
      authorize! :manage, EstacaoPonto

      if @estacao.update(estacao_params)
        redirect_to estacoes_path, notice: "Estação atualizada com sucesso"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      # Task 23.7 — CanCanCan: somente admin pode excluir estações.
      authorize! :manage, EstacaoPonto

      @estacao.destroy
      redirect_to estacoes_path, notice: "Estação excluída com sucesso"
    end

    private

    def set_estacao
      @estacao = EstacaoPonto.find(params[:id])
    end

    def estacao_params
      params.require(:estacao).permit(
        :descricao, :versao, :ultimo_contato, :vnc, :anydesk, :teamviewer, :observacao, :cod_ativacao,
        :codigo_unico_maquina, :momento_inicio, :momento_fim, :liberado_batida_manual, :ativo
      )
    end
  end
end
