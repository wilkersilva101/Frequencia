require "test_helper"

# Task 23.10 (auditoria de fechamento da Sprint 23) — Admin::UsersController
# não tinha NENHUM teste até esta task, apesar de usar
# `load_and_authorize_resource :user, only: [:edit, :update]` (task 23.7).
# Gap real: o único controller admin com `load_and_authorize_resource`
# (em vez do padrão `authorize!` explícito usado nos demais) estava sem
# cobertura de autorização e sem cobertura funcional básica.
module Admin
  class UsersControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    setup do
      @admin = User.create!(nome_completo: "Admin Teste", password: "123456", admin: true)
      post login_path, params: { username: @admin.username, password: "123456" }
    end

    # Mesmo padrão de stub de test/controllers/admin/frequentadores_controller_test.rb
    # (banco `pessoas_test` sem schema carregado — task 8.13).
    def stub_vinculos(vinculos)
      paginado = Kaminari.paginate_array(vinculos).page(1)
      Pessoas::Vinculo.define_singleton_method(:frequentadores_ativos) { |**_kwargs| paginado }
      yield
    ensure
      Pessoas::Vinculo.singleton_class.remove_method(:frequentadores_ativos)
    end

    test "deve listar usuarios sem cpf (cadastrados manualmente)" do
      sem_cpf = User.create!(nome_completo: "Usuario Local", password: "123456")

      stub_vinculos([]) { get users_path }

      assert_response :success
      assert_select "td", text: sem_cpf.nome_completo
    end

    test "deve redirecionar para login se nao autenticado" do
      delete logout_path
      get users_path
      assert_redirected_to login_path
    end

    test "deve mostrar formulario de edicao de usuario sem cpf" do
      sem_cpf = User.create!(nome_completo: "Editavel", password: "123456")

      get edit_user_path(sem_cpf)

      assert_response :success
    end

    test "deve atualizar usuario sem cpf" do
      sem_cpf = User.create!(nome_completo: "Editavel", password: "123456")

      patch user_path(sem_cpf), params: { user: { nome_completo: "Nome Alterado" } }

      assert_redirected_to users_path
      assert_equal "Nome Alterado", sem_cpf.reload.nome_completo
    end

    test "nao deve atualizar usuario vinculado ao pessoas (com cpf)" do
      com_cpf = User.create!(nome_completo: "Vindo Do Pessoas", password: "123456", cpf: "11122233344")

      patch user_path(com_cpf), params: { user: { nome_completo: "Tentativa De Alteracao" } }

      assert_redirected_to users_path
      assert_not_equal "Tentativa De Alteracao", com_cpf.reload.nome_completo
    end

    # --- Autorização (task 23.7 / 23.10) ---
    # `load_and_authorize_resource` nega edit/update a quem não tem
    # `can :manage, User` — apenas admin (role ou coluna legada) tem essa
    # permissão; gestor/operador/autenticado-sem-role só têm `:read`.

    test "usuario nao-admin nao deve acessar formulario de edicao" do
      sem_cpf = User.create!(nome_completo: "Editavel", password: "123456")
      login_como_nao_admin

      get edit_user_path(sem_cpf)

      assert_redirected_to dashboard_path
    end

    test "usuario nao-admin nao deve atualizar usuario" do
      sem_cpf = User.create!(nome_completo: "Editavel", password: "123456")
      login_como_nao_admin

      patch user_path(sem_cpf), params: { user: { nome_completo: "Nome Alterado" } }

      assert_redirected_to dashboard_path
      assert_not_equal "Nome Alterado", sem_cpf.reload.nome_completo
    end

    test "gestor tambem nao deve editar usuario (fora do escopo de manage do gestor)" do
      sem_cpf = User.create!(nome_completo: "Editavel", password: "123456")
      delete logout_path
      gestor = User.create!(nome_completo: "Gestor Teste", password: "123456")
      gestor.add_role(:gestor)
      post login_path, params: { username: gestor.username, password: "123456" }

      get edit_user_path(sem_cpf)

      assert_redirected_to dashboard_path
    end

    test "usuario nao-admin ainda pode listar usuarios (read baseline)" do
      login_como_nao_admin

      stub_vinculos([]) { get users_path }

      assert_response :success
    end

    private

    def login_como_nao_admin
      delete logout_path
      usuario_comum = User.create!(nome_completo: "Usuario Comum", password: "123456", admin: false)
      post login_path, params: { username: usuario_comum.username, password: "123456" }
    end
  end
end
