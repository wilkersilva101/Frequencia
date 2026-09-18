# frozen_string_literal: true

# Task 23.6 — Controller Devise customizado para sessões.
#
# Sobrescreve o controller padrão do Devise para:
# 1. Manter o layout "login" (mesmo layout usado pela tela de login admin)
# 2. Manter os helpers `login_path`/`logout_path` (rotas `/login` e `/logout`)
# 3. Sincronizar `session[:user_id]` para que `Admin::ApplicationController`
#    continue funcionando (usa `session[:user_id]` como fonte de verdade)
# 4. Redirecionar para `dashboard_path` após login (em vez de `root_path`)
#
# A autenticação passa pelo Warden/Devise, que usa `User#find_for_database_authentication`
# (sobrescrito para buscar por `username`) e `User#valid_password?` (sobrescrito
# para rotear usuários com `cpf` para o Pessoas2). O status inativo é bloqueado
# por `User#active_for_authentication?`.
class Users::SessionsController < Devise::SessionsController
  layout "login", only: :new

  # Task 23.6 — o login atual (Admin::SessionsController) usa só
  # `session[:user_id]`; o Devise só sabe do Warden. Se o usuário logou pelo
  # fluxo legado, o Warden está vazio e o `verify_signed_out_user` do Devise
  # responderia "already signed out" e abortaria o destroy ANTES de limpar
  # `session[:user_id]`. Skip necessário para o logout funcionar em ambos os
  # fluxos.
  skip_before_action :verify_signed_out_user, only: :destroy

  # Task 23.8 — GET /u/sign_in.
  # View própria (`users/sessions/new`, criada nesta task), mesmo layout
  # "login" e mesma identidade visual da tela legada (`admin/sessions/new`),
  # mas com form Devise nativo (submete para a rota Devise via Warden, que
  # usa `User#find_for_database_authentication`/`#valid_password?` — mesma
  # fonte de verdade para CPF/Pessoas2, ver app/models/user.rb).
  def new
    if warden.authenticated?(:user)
      redirect_to dashboard_path
    else
      super
    end
  end

  # POST /u/sign_in (também mapeado como POST /login)
  def create
    super do |resource|
      # Após Devise autenticar via Warden, sincroniza session[:user_id]
      # para que Admin::ApplicationController#current_user funcione.
      session[:user_id] = resource.id
    end
  end

  # DELETE /logout (também mapeado como DELETE /u/sign_out)
  def destroy
    session[:user_id] = nil
    super
  end

  private

  # Redireciona para dashboard_path após login (em vez de root_path).
  # Devise usa `stored_location_for` ou `after_sign_in_path_for`.
  def after_sign_in_path_for(_resource)
    dashboard_path
  end

  # Redireciona para login_path após logout (em vez de root_path).
  def after_sign_out_path_for(_resource_or_scope)
    login_path
  end
end
