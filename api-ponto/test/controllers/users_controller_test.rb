require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(nome_completo: "Admin Teste", password: "123456", admin: true)
    post login_path, params: { username: @admin.username, password: "123456" }
  end

  # Pedido do usuário (2026-09-02): index passou a listar
  # Pessoas::Vinculo.ativos (mesmo padrão de admin/frequentadores, task
  # 10.10) em vez de só User.order(:nome_completo). pessoas_test não tem
  # schema carregado (task 8.13) — stuba o ponto de entrada, mesmo padrão
  # já usado em frequentadores_controller_test.rb.
  test "deve listar usuarios" do
    Pessoas::Vinculo.define_singleton_method(:frequentadores_ativos) { |**_kwargs| Kaminari.paginate_array([]).page(1) }

    get users_path

    assert_response :success
  ensure
    Pessoas::Vinculo.singleton_class.remove_method(:frequentadores_ativos)
  end

  test "usuario local sem cpf aparece na secao separada, mesmo sem vinculo no pessoas2" do
    Pessoas::Vinculo.define_singleton_method(:frequentadores_ativos) { |**_kwargs| Kaminari.paginate_array([]).page(1) }
    sem_cpf = User.create!(nome_completo: "Admin Sem Vinculo", password: "123456")

    get users_path

    assert_response :success
    assert_select "td", text: "Admin Sem Vinculo"
    assert_select "code", text: sem_cpf.username
  ensure
    Pessoas::Vinculo.singleton_class.remove_method(:frequentadores_ativos)
  end

  test "deve mostrar formulario de edicao" do
    user = User.create!(nome_completo: "Editável", password: "123456")
    get edit_user_path(user)
    assert_response :success
  end

  test "deve atualizar usuario" do
    user = User.create!(nome_completo: "Editável", password: "123456")
    patch user_path(user), params: { user: { nome_completo: "Nome Alterado" } }
    assert_redirected_to users_path
    assert_equal "Nome Alterado", user.reload.nome_completo
  end

  test "edit exibe campos desabilitados para frequentador vinculado ao Pessoas (com cpf)" do
    user = User.create!(nome_completo: "Vindo Do Pessoas", password: "123456", cpf: "11122233344")

    get edit_user_path(user)

    assert_response :success
    assert_select "input[name='user[nome_completo]'][disabled]"
    assert_select "input[type='submit']", count: 0
  end

  test "edit nao desabilita campos para usuario sem cpf (cadastro manual)" do
    user = User.create!(nome_completo: "Manual", password: "123456")

    get edit_user_path(user)

    assert_response :success
    assert_select "input[name='user[nome_completo]']:not([disabled])"
    assert_select "input[type='submit']"
  end

  test "update bloqueia edicao de frequentador vinculado ao Pessoas mesmo via POST direto" do
    user = User.create!(nome_completo: "Vindo Do Pessoas", password: "123456", cpf: "11122233344")

    patch user_path(user), params: { user: { nome_completo: "Tentativa De Alterar" } }

    assert_redirected_to users_path
    assert_equal "Vindo Do Pessoas", user.reload.nome_completo
  end

  # Task 21.7 (auditoria de cobertura): a 21.6 removeu new/create/destroy/
  # purge de config/routes.rb e do controller, mas não havia teste
  # confirmando que essas rotas realmente não existem mais (só os testes
  # antigos de new/create/destroy/purge foram removidos, não substituídos
  # por uma prova negativa). `resources :users, only: [:index, :update]`
  # não gera os helpers de path pra ações fora dessa lista — chamar um
  # helper inexistente levanta NoMethodError, o mesmo teste orientado pelo
  # dev.
  test "helpers de rota para criacao/exclusao manual nao existem mais" do
    assert_raises(NameError) { new_user_path }
    assert_raises(NameError) { purge_user_path(@admin) }
  end

  # Complementa o teste acima com a prova em nível de HTTP: mesmo sem o
  # helper, uma requisição direta pros verbos/paths que existiam antes da
  # 21.6 não deve mais casar com nenhuma rota. `show_exceptions = :rescuable`
  # (config/environments/test.rb) faz o Rails converter o RoutingError numa
  # resposta 404 em vez de deixá-lo propagar como exceção.
  test "POST direto em users_path (criacao manual) nao casa com nenhuma rota" do
    post "/users", params: { user: { nome_completo: "Tentativa" } }
    assert_response :not_found
  end

  test "DELETE direto em user_path (exclusao manual) nao casa com nenhuma rota" do
    user = User.create!(nome_completo: "Para Excluir", password: "123456")

    delete "/users/#{user.id}"
    assert_response :not_found
  end
end
