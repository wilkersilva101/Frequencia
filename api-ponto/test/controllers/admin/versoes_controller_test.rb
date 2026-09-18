require "test_helper"

module Admin
  class VersoesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = User.create!(nome_completo: "Admin Teste", password: "123456", admin: true)
      post login_path, params: { username: @user.username, password: "123456" }
    end

    test "deve listar versoes cadastradas" do
      Versao.create!(numero: "1.0.0", novidades: "Versão inicial")
      Versao.create!(numero: "1.1.0", novidades: "Correção de bugs", link: "https://example.com/1.1.0")

      get versoes_path

      assert_response :success
      assert_select "table tbody tr", count: Versao.count
      assert_select "td", text: "1.0.0"
      assert_select "td", text: "1.1.0"
      assert_select "td", text: "Correção de bugs"
    end

    test "deve funcionar com base vazia" do
      get versoes_path

      assert_response :success
      assert_select "td", text: "Nenhuma versão cadastrada"
    end

    test "deve redirecionar para login se nao autenticado" do
      delete logout_path
      get versoes_path
      assert_redirected_to login_path
    end

    test "deve mostrar formulario de nova versao" do
      get new_versao_path
      assert_response :success
    end

    test "deve criar versao" do
      assert_difference("Versao.count") do
        post versoes_path, params: { versao: { numero: "2.0.0", novidades: "Nova versão", link: "https://example.com/2.0.0" } }
      end
      assert_redirected_to versoes_path
      assert_equal "2.0.0", Versao.last.numero
    end

    test "nao deve criar versao invalida" do
      assert_no_difference("Versao.count") do
        post versoes_path, params: { versao: { numero: "" } }
      end
      assert_response :unprocessable_entity
    end

    test "deve mostrar formulario de edicao" do
      versao = Versao.create!(numero: "1.0.0")
      get edit_versao_path(versao)
      assert_response :success
    end

    test "deve atualizar versao" do
      versao = Versao.create!(numero: "1.0.0")
      patch versao_path(versao), params: { versao: { numero: "1.0.1" } }
      assert_redirected_to versoes_path
      assert_equal "1.0.1", versao.reload.numero
    end

    test "nao deve atualizar versao com dados invalidos" do
      versao = Versao.create!(numero: "1.0.0")
      patch versao_path(versao), params: { versao: { numero: "" } }
      assert_response :unprocessable_entity
      assert_not_equal "", versao.reload.numero
    end

    test "deve excluir versao" do
      versao = Versao.create!(numero: "1.0.0")
      assert_difference("Versao.count", -1) do
        delete versao_path(versao)
      end
      assert_redirected_to versoes_path
    end

    test "usuario nao-admin nao deve acessar formulario de nova versao" do
      login_como_nao_admin

      get new_versao_path

      # Task 23.7 — CanCanCan: acesso negado redireciona para o dashboard
      # (rescue_from CanCan::AccessDenied), não mais para o recurso.
      assert_redirected_to dashboard_path
    end

    test "usuario nao-admin nao deve criar versao" do
      login_como_nao_admin

      assert_no_difference("Versao.count") do
        post versoes_path, params: { versao: { numero: "3.0.0" } }
      end
      assert_redirected_to dashboard_path
    end

    test "usuario nao-admin nao deve acessar formulario de edicao" do
      login_como_nao_admin

      versao = Versao.create!(numero: "1.0.0")
      get edit_versao_path(versao)

      assert_redirected_to dashboard_path
    end

    private

    def login_como_nao_admin
      delete logout_path
      usuario_comum = User.create!(nome_completo: "Usuario Comum", password: "123456", admin: false)
      post login_path, params: { username: usuario_comum.username, password: "123456" }
    end
  end
end
