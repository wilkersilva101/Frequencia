module Admin
  class GestoresIndividuaisController < Admin::ApplicationController
    def index
      # Task 23.7 — CanCanCan: autorização explícita para leitura.
      # Admin/gestor/operador podem visualizar (todos têm :read em :all).
      authorize! :read, :all

      @gestores = GestorIndividual.includes(:gerenciados).order(:nome)
    end
  end
end
