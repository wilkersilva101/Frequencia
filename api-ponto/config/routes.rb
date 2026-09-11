Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Configurações do Sistema — painéis web de monitoramento (Exception Track
  # e Sidekiq) montados como Rack apps isolados e protegidos pelo constraint
  # de administrador (sessão `_api_ponto_session` + `User#admin?`). Ver
  # PRD-CONFIGURACOES-SISTEMA.md e lib/admin_constraint.rb.
  #
  # NOTE (Sidekiq): o projeto usa Solid Queue (sem Redis) por decisão
  # registrada no PRD §16. O Sidekiq::Web é servido aqui para monitoramento;
  # a troca do queue_adapter (Solid Queue -> Sidekiq) NÃO é feita nesta PRD
  # (ver D01 no PRD-CONFIGURACOES-SISTEMA.md).
  mount ExceptionTrack::Engine => "/exception-track", constraints: AdminConstraint.new

  require "sidekiq/web"
  mount Sidekiq::Web => "/sidekiq", constraints: AdminConstraint.new

  # Admin frontend (R.2 — controllers vivem em Admin::, paths preservados via
  # `module:` para não quebrar login_path/dashboard_path/users_path/etc.
  # já usados pelos testes e pelas views — ver ADR-001, Seção 4)
  scope module: "admin" do
    root to: "dashboard#index"
    get "login", to: "sessions#new"
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy"
    get "dashboard", to: "dashboard#index"
    # NOTE (R.2): `config.api_only = true` (ver application.rb) faz o Rails
    # excluir `:new`/`:edit` das rotas padrão de `resources` (ações que só
    # existem para servir formulário HTML). O módulo administrativo precisa
    # delas — adicionadas explicitamente via `concerns`/`except` combinado a
    # rotas extras.
    get "users/new", to: "users#new", as: :new_user
    get "users/:id/edit", to: "users#edit", as: :edit_user
    resources :users, except: [:show, :new, :edit] do
      member do
        delete :purge
      end
    end
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
end
