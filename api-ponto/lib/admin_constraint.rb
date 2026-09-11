# frozen_string_literal: true

# Restringe o acesso a uma rota (ou engine montada) a usuários
# administradores autenticados, com base na sessão administradora
# usada pelo módulo admin (ver `Admin::ApplicationController`).
#
# Usado para proteger os painéis web de terceiros montados na aplicação
# — Exception Track e Sidekiq::Web — que são Rack apps isolados e não
# passam pelo `Admin::ApplicationController` (não herdam `require_login`
# nem `require_admin`). Este constraint olha a mesma cookie de sessão que
# o login do admin (`_api_ponto_session`) e valida `User#admin?`.
#
# Ver PRD-CONFIGURACOES-SISTEMA.md §8 (D03 — autenticação dos painéis).
class AdminConstraint
  def matches?(request)
    return false unless request.session[:user_id]

    user = User.find_by(id: request.session[:user_id])
    user&.admin?
  end
end
