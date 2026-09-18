module Admin
  class SessionsController < Admin::ApplicationController
    skip_before_action :require_login, only: [:new, :create]
    skip_before_action :verify_authenticity_token, only: [:create]
    # Task 23.7 — Login/sessão não requer autorização CanCanCan.
    skip_authorization_check

    def new
      if logged_in?
        redirect_to dashboard_path
      else
        render layout: "login"
      end
    end

    def create
      user = User.find_by(username: params[:username])
      if user&.authenticate(params[:password]) && user.status == 1
        session[:user_id] = user.id
        redirect_to dashboard_path, notice: "Login realizado com sucesso"
      else
        flash.now[:alert] = "Usuário ou senha inválidos"
        render :new, layout: "login", status: :unprocessable_entity
      end
    end

    def destroy
      session[:user_id] = nil
      redirect_to login_path, notice: "Sessão encerrada"
    end
  end
end
