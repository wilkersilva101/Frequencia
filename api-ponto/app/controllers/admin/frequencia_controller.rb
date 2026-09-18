module Admin
  class FrequenciaController < Admin::ApplicationController
    def index
      # Task 23.7 — CanCanCan: autorização explícita para leitura.
      # Admin/gestor/operador podem visualizar (todos têm :read em :all).
      authorize! :read, :all

      @registros = TimeRecord.includes(:user, :estacao_ponto).order(punched_at: :desc)

      if params[:data].present? && data_filtro
        @registros = @registros.merge(TimeRecord.by_date(data_filtro))
      end

      if params[:frequentador].present?
        @registros = @registros.joins(:user).where("users.nome_completo ILIKE ?", "%#{params[:frequentador]}%")
      end

      if params[:estacao].present?
        @registros = @registros.joins(:estacao_ponto).where("estacoes_ponto.descricao ILIKE ?", "%#{params[:estacao]}%")
      end
    end

    private

    def data_filtro
      Date.parse(params[:data])
    rescue Date::Error, TypeError
      nil
    end
  end
end
