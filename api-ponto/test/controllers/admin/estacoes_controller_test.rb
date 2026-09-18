require "test_helper"

module Admin
  class EstacoesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = User.create!(nome_completo: "Admin Teste", password: "123456", admin: true)
      post login_path, params: { username: @user.username, password: "123456" }
    end

    test "deve listar estacoes cadastradas" do
      get estacoes_path

      assert_response :success
      assert_select "table tbody tr", count: EstacaoPonto.count
      assert_select "td", text: estacoes_ponto(:one).descricao
      assert_select "td", text: estacoes_ponto(:two).descricao
    end

    test "deve funcionar com base vazia" do
      EstacaoPonto.delete_all

      get estacoes_path

      assert_response :success
      assert_select "td", text: "Nenhuma estação cadastrada"
    end

    test "deve redirecionar para login se nao autenticado" do
      delete logout_path
      get estacoes_path
      assert_redirected_to login_path
    end

    test "deve mostrar formulario de nova estacao" do
      get new_estacao_path
      assert_response :success
    end

    test "deve criar estacao" do
      assert_difference("EstacaoPonto.count") do
        post estacoes_path, params: { estacao: { descricao: "Estacao Nova", cod_ativacao: "cod-nova-001" } }
      end
      assert_redirected_to estacoes_path
    end

    test "nao deve criar estacao invalida" do
      assert_no_difference("EstacaoPonto.count") do
        post estacoes_path, params: { estacao: { descricao: "", cod_ativacao: "" } }
      end
      assert_response :unprocessable_entity
    end

    test "deve mostrar formulario de edicao" do
      get edit_estacao_path(estacoes_ponto(:one))
      assert_response :success
    end

    test "deve atualizar estacao" do
      estacao = estacoes_ponto(:one)
      patch estacao_path(estacao), params: { estacao: { descricao: "Nome Alterado" } }
      assert_redirected_to estacoes_path
      assert_equal "Nome Alterado", estacao.reload.descricao
    end

    test "nao deve atualizar estacao com dados invalidos" do
      estacao = estacoes_ponto(:one)
      patch estacao_path(estacao), params: { estacao: { descricao: "" } }
      assert_response :unprocessable_entity
      assert_not_equal "", estacao.reload.descricao
    end

    test "deve excluir estacao" do
      estacao = estacoes_ponto(:one)
      assert_difference("EstacaoPonto.count", -1) do
        delete estacao_path(estacao)
      end
      assert_redirected_to estacoes_path
    end

    test "usuario nao-admin nao deve acessar formulario de nova estacao" do
      login_como_nao_admin

      get new_estacao_path

      # Task 23.7 — CanCanCan: acesso negado redireciona para o dashboard
      # (rescue_from CanCan::AccessDenied), não mais para o recurso.
      assert_redirected_to dashboard_path
    end

    test "usuario nao-admin nao deve criar estacao" do
      login_como_nao_admin

      assert_no_difference("EstacaoPonto.count") do
        post estacoes_path, params: { estacao: { descricao: "Estacao Nova", cod_ativacao: "cod-nova-001" } }
      end
      assert_redirected_to dashboard_path
    end

    test "usuario nao-admin nao deve acessar formulario de edicao" do
      login_como_nao_admin

      get edit_estacao_path(estacoes_ponto(:one))

      assert_redirected_to dashboard_path
    end

    test "usuario nao-admin nao deve atualizar estacao" do
      login_como_nao_admin
      estacao = estacoes_ponto(:one)

      patch estacao_path(estacao), params: { estacao: { descricao: "Nome Alterado" } }

      assert_redirected_to dashboard_path
      assert_not_equal "Nome Alterado", estacao.reload.descricao
    end

    test "usuario nao-admin nao deve excluir estacao" do
      login_como_nao_admin
      estacao = estacoes_ponto(:one)

      assert_no_difference("EstacaoPonto.count") do
        delete estacao_path(estacao)
      end
      assert_redirected_to dashboard_path
    end

    test "usuario nao-admin ainda pode listar estacoes" do
      login_como_nao_admin

      get estacoes_path

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
