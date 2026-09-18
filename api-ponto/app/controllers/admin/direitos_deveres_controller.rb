module Admin
  class DireitosDeveresController < Admin::ApplicationController
    def index
      # Task 23.7 — CanCanCan: autorização explícita para leitura.
      # Admin/gestor/operador podem visualizar (todos têm :read em :all).
      authorize! :read, :all

      @registros = AfastamentoCache.includes(:frequentador_cache).order(momento_inicial: :desc)

      if params[:tipo].present?
        @registros = @registros.where(tipo: params[:tipo])
      end
    end

    # Um clique sincroniza os afastamentos de todos os frequentadores
    # vinculados de uma vez (mesmo padrão do botão "Importar servidores da
    # unidade piloto" da Sprint 10B — o gatilho manual não é um-a-um).
    def sincronizar_agora
      # Task 23.7 — CanCanCan: somente admin pode sincronizar afastamentos.
      authorize! :manage, AfastamentoCache

      SincronizarAfastamentosJob.perform_later
      redirect_to direitos_deveres_path, notice: "Sincronização de direitos/deveres iniciada."
    end
  end
end
