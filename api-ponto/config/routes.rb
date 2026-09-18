Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Task 23.6 — Devise routes para o model User.
  # `path: "u"` coloca as rotas Devise em /u/sign_in, /u/sign_out etc.
  # (padrão do basic8). skip: registrations — cadastro vem do Pessoas2, não
  # auto-registro. controllers: sessions customizado (Users::SessionsController)
  # para manter layout "login" + session[:user_id] + after_sign_in para
  # dashboard. Login admin continua em /login via controllers abaixo.
  devise_for :users, path: "u", skip: %i[registrations],
                     controllers: { sessions: "users/sessions" }

  # Admin frontend (R.2 — controllers vivem em Admin::, paths preservados via
  # `module:` para não quebrar login_path/dashboard_path/users_path/etc.
  # já usados pelos testes e pelas views — ver ADR-001, Seção 4)
  scope module: "admin" do
    root to: "dashboard#index"
    get "login", to: "sessions#new"
    post "login", to: "sessions#create"
    # NOTE (Task 23.6): rota de logout removida do scope admin — agora
    # mapeia para `Users::SessionsController#destroy` (Devise) lá embaixo
    # neste arquivo. Mantém `logout_path` válido.
    get "dashboard", to: "dashboard#index"
    # NOTE (R.2): `config.api_only = true` (ver application.rb) faz o Rails
    # excluir `:new`/`:edit` das rotas padrão de `resources` (ações que só
    # existem para servir formulário HTML). O módulo administrativo precisa
    # delas — adicionadas explicitamente via `concerns`/`except` combinado a
    # rotas extras.
    # Task 21.6: criação/exclusão manual de frequentador pela tela admin
    # removida — o cadastro passa a vir inteiramente do Pessoas (via
    # Pessoas::Vinculo, tasks 8.14-8.16) e a autenticação de quem tem cpf
    # via bcrypt do pessoas2 (task 21.5). Sobra apenas leitura/listagem
    # (:index) e edição (:edit/:update), esta última só útil hoje para
    # contas locais sem cpf (admins/cadastros manuais pré-existentes) — o
    # próprio controller bloqueia edição de quem tem cpf.
    get "users/:id/edit", to: "users#edit", as: :edit_user
    resources :users, only: [:index, :update]
    resources :time_records, only: [:index]
    resources :frequentadores, only: [:index] do
      member do
        post :reimportar_dados_pessoa
      end
      collection do
        post :importar_unidade
      end
    end
    get "estacoes/new", to: "estacoes#new", as: :new_estacao
    get "estacoes/:id/edit", to: "estacoes#edit", as: :edit_estacao
    resources :estacoes, only: [:index, :create, :update, :destroy]
    get "versoes/new", to: "versoes#new", as: :new_versao
    get "versoes/:id/edit", to: "versoes#edit", as: :edit_versao
    resources :versoes, only: [:index, :create, :update, :destroy]
    resources :relatorio_terceirizados, only: [:index]
    get "frequencia_por_orgao", to: "frequencia_por_orgao#index", as: :frequencia_por_orgao
    get "parcial", to: "parcial#index", as: :parcial
    get "frequencia", to: "frequencia#index", as: :frequencia
    get "regimes/new", to: "regimes#new", as: :new_regime
    get "regimes/:id/edit", to: "regimes#edit", as: :edit_regime
    resources :regimes, only: [:index, :create, :update, :destroy]
    resources :direitos_deveres, only: [:index] do
      collection do
        post :sincronizar_agora
      end
    end
    resources :gestores_individuais, only: [:index]
  end

  namespace :presenca do
    get "ValidarFrequentador", to: "validar_frequentador#show"
    get "DynFrequentadoresEstacao", to: "dyn_frequentadores_estacao#index"
    get "DynHashFrequentadoresEstacao", to: "dyn_hash_frequentadores_estacao#show"
    get "CarregaRelogioAtual", to: "carrega_relogio_atual#show"
    post "ajax/SincronizarRegistrosPonto", to: "sincronizar_registros_ponto#create"
    get "InicializarPonto", to: "inicializar_ponto#show"
    get "IniciarPonto", to: "iniciar_ponto#show"
    get "PontoDePresenca", to: "ponto_de_presenca#show"
    get "Frequentador", to: "frequentador#show"
    post "Frequentador", to: "frequentador#create"
    get "AdicioneEstacao", to: "adicione_estacao#show"
    get "ProblemaRegistro", to: "problema_registro#show"
  end

  # Task 23.6 — Rota de logout customizada que mapeia para o controller
  # Devise sessions (Users::SessionsController), preservando o helper
  # `logout_path` usado em dezenas de lugares (testes, views, controllers).
  # O controller destrói a sessão via `sign_out` (Devise) + limpa
  # `session[:user_id]` e redireciona para login_path.
  # Fora do scope module:"admin" para não herdar o namespace —
  # o controller é Users::Sessions, não Admin::Sessions.
  # Envolto em `devise_scope :user` para que `request.env["devise.mapping"]`
  # seja setado (DeviseController#devise_mapping depende disso) e o destroy
  # do Devise funcione.
  devise_scope :user do
    delete "logout", to: "users/sessions#destroy", as: :logout
  end
end
