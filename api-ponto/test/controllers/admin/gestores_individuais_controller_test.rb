require "test_helper"

module Admin
  class GestoresIndividuaisControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(nome_completo: "Admin Teste", password: "123456", admin: true)
      post login_path, params: { username: @admin.username, password: "123456" }
    end

    test "deve listar gestores cadastrados com contagem de gerenciados" do
      gestor = GestorIndividual.create!(nome: "Fulano Gestor", orgao: "Vara Cível")
      frequentador_a = User.create!(nome_completo: "Frequentador A", password: "123456")
      frequentador_b = User.create!(nome_completo: "Frequentador B", password: "123456")
      GestorIndividualGerenciado.create!(gestor_individual: gestor, user: frequentador_a)
      GestorIndividualGerenciado.create!(gestor_individual: gestor, user: frequentador_b)

      get gestores_individuais_path

      assert_response :success
      assert_select "td", text: "Fulano Gestor"
      assert_select "td", text: "Vara Cível"
      assert_select "td", text: "2"
    end

    test "deve funcionar com base vazia" do
      get gestores_individuais_path

      assert_response :success
      assert_select "td", text: "Nenhum gestor cadastrado"
    end

    test "gestor sem gerenciados mostra zero" do
      GestorIndividual.create!(nome: "Sem Gerenciados")

      get gestores_individuais_path

      assert_response :success
      assert_select "td", text: "0"
    end

    test "deve redirecionar para login se nao autenticado" do
      delete logout_path
      get gestores_individuais_path
      assert_redirected_to login_path
    end
  end
end
