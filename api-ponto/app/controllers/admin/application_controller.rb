module Admin
  # Controller base do contexto administrativo (ADR-001, Seção 4).
  # Concentra autenticação de sessão e autorização (CanCanCan, task 23.7).
  # Todas as rotas administrativas exigem login, exceto as explicitamente
  # liberadas (ex: Admin::SessionsController#new/#create, tela de login).
  class ApplicationController < ::ApplicationController
    include CanCan::ControllerAdditions

    layout "admin"

    before_action :require_login
    check_authorization

    # Task 23.7 — CanCanCan: redireciona para dashboard quando o usuário
    # não tem permissão. Mantém o mesmo padrão de alert do require_admin
    # legado ( mensagem em pt-BR ).
    rescue_from CanCan::AccessDenied do |exception|
      redirect_to dashboard_path, alert: exception.message
    end

    helper_method :current_user, :logged_in?

    private

    def current_user
      @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
    end

    def logged_in?
      current_user.present?
    end

    def require_login
      unless logged_in?
        redirect_to login_path
      end
    end

    # Task 23.7 — Mantido como fallback legado. Controllers que usavam
    # require_admin agora usam load_and_authorize_resource ou authorize!
    # do CanCanCan. O método permanece disponível para chamada manual
    # se necessário durante a transição.
    def require_admin(fallback_path = dashboard_path)
      return if current_user&.admin?

      redirect_to fallback_path, alert: "Acesso restrito a administradores"
    end
  end
end
