module Admin
  class UsersController < Admin::ApplicationController
    before_action :set_user, only: [:edit, :update]
    # Task 23.7 — CanCanCan: load_and_authorize_resource para edit/update
    # (manage User). Index usa autorização explícita porque não segue
    # resources padrão (lê de Pessoas::Vinculo, não de User).
    load_and_authorize_resource :user, only: [:edit, :update]

    # Pedido do usuário (2026-09-02): mesma abordagem já aplicada em
    # admin/frequentadores (task 10.10) — a listagem deixa de ser só o
    # `User` local e passa a mostrar TODO vínculo ativo do pessoas2,
    # inclusive quem ainda não tem conta de login local. Status/Digital/
    # username (conceitos só locais) continuam vindo do `User`, ligado por
    # `cpf`.
    def index
      # Task 23.7 — CanCanCan: autorização explícita para leitura da listagem.
      # Admin/gestor/operador podem visualizar (todos têm :read em :all).
      authorize! :read, :all
      @vinculos = Pessoas::Vinculo.frequentadores_ativos(
        nome: params[:nome],
        incluir_cpfs: cpfs_exigidos_pelos_filtros_locais,
        excluir_cpfs: cpfs_excluidos_pelos_filtros_locais.presence
      ).page(params[:page])

      # Pré-carrega todos os Users locais da página de uma vez (por cpf) em
      # vez de 1 query por linha na view.
      cpfs_da_pagina = @vinculos.filter_map { |vinculo| vinculo.pessoa&.cpf }
      @user_por_cpf = User.where(cpf: cpfs_da_pagina).index_by(&:cpf)

      # Users locais SEM cpf (ex: admins criados manualmente, sem vínculo
      # no pessoas2) não aparecem em `@vinculos` de jeito nenhum — listados
      # à parte pra não ficarem invisíveis/inacessíveis pela tela (decisão
      # do usuário, 2026-09-02).
      @users_sem_cpf = User.where(cpf: nil).order(:nome_completo)
      @users_sem_cpf = @users_sem_cpf.where("nome_completo ILIKE ?", "%#{params[:nome]}%") if params[:nome].present?
      @users_sem_cpf = @users_sem_cpf.where("username ILIKE ?", "%#{params[:username]}%") if params[:username].present?
      @users_sem_cpf = @users_sem_cpf.where(status: params[:status_filtro]) if params[:status_filtro].present?
      if params[:digital].present?
        @users_sem_cpf = @users_sem_cpf.where(params[:digital] == "1" ? "digitais_hash IS NOT NULL" : "digitais_hash IS NULL")
      end
    end

    def edit
    end

    def update
      if @user.cpf.present?
        redirect_to users_path, alert: "Frequentador vinculado ao Pessoas — edição manual bloqueada. O cadastro é atualizado via importação/reimportação do Pessoas."
        return
      end

      if @user.update(user_params)
        redirect_to users_path, notice: "Usuário atualizado com sucesso"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      permitted = params.require(:user).permit(:nome_completo, :password, :password_confirmation, :status, :digitais_hash)
      if permitted[:password].blank?
        permitted.extract!(:password, :password_confirmation)
      end
      permitted
    end

    # Mesmo padrão de admin/frequentadores_controller.rb: filtros que só
    # existem no User LOCAL (username, status, digital) resolvidos como
    # listas de CPF, porque `users` (Frequencia) e `pessoas`/`vinculos`
    # (pessoas2) vivem em bancos Postgres diferentes, sem JOIN
    # cross-database possível.
    def cpfs_exigidos_pelos_filtros_locais
      listas = [ cpfs_do_username_filtrado, cpfs_do_status_filtrado, cpfs_com_digital_cadastrada ].compact
      return nil if listas.empty?

      listas.reduce(:&)
    end

    def cpfs_do_username_filtrado
      return nil if params[:username].blank?

      User.where("username ILIKE ?", "%#{params[:username]}%").where.not(cpf: nil).pluck(:cpf)
    end

    def cpfs_do_status_filtrado
      return nil if params[:status_filtro].blank?

      User.where(status: params[:status_filtro]).where.not(cpf: nil).pluck(:cpf)
    end

    def cpfs_com_digital_cadastrada
      return nil unless params[:digital] == "1"

      User.where.not(digitais_hash: [ nil, "" ]).where.not(cpf: nil).pluck(:cpf)
    end

    # "Sem Digital" vira exclusão (não inclusão) dos cpfs com digital
    # cadastrada — assim quem não tem User local nenhum também aparece
    # (por definição, não tem digital cadastrada).
    def cpfs_excluidos_pelos_filtros_locais
      return [] unless params[:digital] == "0"

      User.where.not(digitais_hash: [ nil, "" ]).where.not(cpf: nil).pluck(:cpf)
    end
  end
end
