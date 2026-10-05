module Admin
  class FrequenciaController < Admin::ApplicationController
    include FrequenciaAuthorization

    def index
      # Task 23.7 — CanCanCan: autorização explícita para leitura.
      # Admin/gestor/operador podem visualizar (todos têm :read em :all).
      authorize! :read, :all

      # Task 29.7 — cascata (atrás da flag). Com a flag LIGADA, a listagem
      # passa a mostrar só os frequentadores visíveis do usuário logado
      # (`frequentadores_visiveis`, 29.6); em shadow, a relação é observada e
      # logada sem restringir; desligada, nada muda.
      @registros = TimeRecord.includes(:user, :estacao_ponto).order(punched_at: :desc)
      observar_cascata_frequencia(@registros)
      # Task 29.8 (débito S4) — no modo `:on`, registra a negação EFETIVA dos
      # alvos que sairão da listagem (antes do `where`). No shadow, quem loga é
      # o `observar_*` acima; aqui é no-op.
      registrar_negacoes_frequencia(@registros)
      @registros = restringir_frequencia(@registros)

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
