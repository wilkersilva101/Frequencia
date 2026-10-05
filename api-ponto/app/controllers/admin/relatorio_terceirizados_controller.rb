module Admin
  class RelatorioTerceirizadosController < Admin::ApplicationController
    include FrequenciaAuthorization

    def index
      # Task 23.7 — CanCanCan: autorização explícita para leitura.
      # Admin/gestor/operador podem visualizar (todos têm :read em :all).
      authorize! :read, :all

      # Task 29.7 — cascata (atrás da flag). A tela ainda não tem fonte de dado
      # real (`@registros = []`) — não há o que restringir nem o que observar
      # hoje. O concern fica incluído e a listagem, quando a fonte existir,
      # deve passar por `restringir_frequencia`.
      #
      # Task 29.8 (débito S4) — a tela fica FORA da auditoria de negação por
      # construção: sem fonte de dado não há NEGAÇÃO para registrar (nem
      # shadow, nem `:on`). Ligar um logger `:on` aqui emitiria evento de uma
      # barreira inexistente — log de fachada. Quando a fonte real chegar,
      # aplicar `restringir_frequencia` + `registrar_negacoes_frequencia`.
      @registros = []
    end
  end
end
