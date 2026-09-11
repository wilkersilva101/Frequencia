require "test_helper"

module Admin
  # Testes das rotas de "Configurações do Sistema" (PRD-CONFIGURACOES-SISTEMA.md):
  # os painéis Exception Track (/exception-track) e Sidekiq (/sidekiq) são Rack
  # apps isolados montados com o `AdminConstraint`, que valida sessão de
  # administrador. Não passam por `Admin::ApplicationController`, então o
  # comportamento de cada rota é testado diretamente aqui.
  class ConfiguracoesSistemaTest < ActionDispatch::IntegrationTest
    setup do
      @user = User.create!(nome_completo: "Admin Teste", password: "123456", admin: true)
      post login_path, params: { username: @user.username, password: "123456" }
    end

    # --- Exception Track ---------------------------------------------------

    test "exception track: nao-autenticado recebe 404 (constraint nao revela a rota)" do
      delete logout_path
      get "/exception-track"
      assert_response :not_found
    end

    test "exception track: admin autenticado acessa o painel" do
      get "/exception-track"
      assert_response :success
    end

    test "exception track: usuario nao-admin nao acessa (constraint)" do
      delete logout_path
      usuario_comum = User.create!(nome_completo: "Usuario Comum", password: "123456", admin: false)
      post login_path, params: { username: usuario_comum.username, password: "123456" }

      get "/exception-track"

      assert_response :not_found
    end

    test "exception track: lista excecoes registradas no banco" do
      ExceptionTrack::Log.create!(title: "Erro de validacao teste", body: "stacktrace de teste")

      get "/exception-track"

      assert_response :success
      assert_select "a", /Erro de validacao teste/
    end

    # --- Sidekiq ----------------------------------------------------------

    test "sidekiq: nao-autenticado recebe 404 (constraint nao revela a rota)" do
      delete logout_path
      get "/sidekiq"
      assert_response :not_found
    end

    test "sidekiq: admin autenticado acessa o painel" do
      get "/sidekiq"
      assert_response :success
    end

    test "sidekiq: usuario nao-admin nao acessa (constraint)" do
      delete logout_path
      usuario_comum = User.create!(nome_completo: "Usuario Comum", password: "123456", admin: false)
      post login_path, params: { username: usuario_comum.username, password: "123456" }

      get "/sidekiq"

      assert_response :not_found
    end

    # --- Menu lateral -----------------------------------------------------

    test "menu Configuracoes do Sistema aparece para admin" do
      get dashboard_path
      assert_response :success
      assert_select "a.nav-link", /Configurações do Sistema/
      assert_select "a.nav-link", /Exception Track/
      assert_select "a.nav-link", /Sidekiq/
    end

    test "menu Configuracoes do Sistema nao aparece para nao-admin" do
      delete logout_path
      usuario_comum = User.create!(nome_completo: "Usuario Comum", password: "123456", admin: false)
      post login_path, params: { username: usuario_comum.username, password: "123456" }

      get dashboard_path
      assert_response :success
      assert_select "a.nav-link", { text: /Configurações do Sistema/, count: 0 }
    end
  end
end
