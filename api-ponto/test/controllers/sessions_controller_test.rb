require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(nome_completo: "Admin Teste", password: "123456")
  end

  test "deve mostrar formulario de login" do
    get login_path
    assert_response :success
    assert_select "h3", "API Ponto TJPI"
  end

  test "deve fazer login com credenciais validas" do
    post login_path, params: { username: @user.username, password: "123456" }
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success
  end

  test "deve rejeitar login com senha invalida" do
    post login_path, params: { username: @user.username, password: "errada" }
    assert_response :unprocessable_entity
    assert_select ".alert-danger", "Usuário ou senha inválidos"
  end

  test "deve fazer logout" do
    post login_path, params: { username: @user.username, password: "123456" }
    delete logout_path
    assert_redirected_to login_path
  end

  # Task 21.5: usuário vindo do Pessoas (tem cpf) loga com a senha real do
  # pessoas2. Stub no ponto de entrada único (`Pessoas::User.buscar_por_cpf`)
  # pelo mesmo motivo documentado em test/models/user_test.rb — banco
  # `pessoas` de teste sem schema carregado.
  test "deve fazer login de usuario vindo do pessoas com a senha real do pessoas2" do
    user_pessoas = User.create!(nome_completo: "Vindo do Pessoas", password: "senha-local-irrelevante", cpf: "11122233344")
    hash = BCrypt::Password.create("senha-real")
    # Struct simples: Pessoas::User não pode ser instanciado de verdade em
    # teste (banco `pessoas_test` sem schema carregado), ver
    # test/models/user_test.rb.
    pessoas_user = Struct.new(:encrypted_password).new(hash)

    original = Pessoas::User.method(:buscar_por_cpf)
    Pessoas::User.define_singleton_method(:buscar_por_cpf) { |*_args, **_kwargs| pessoas_user }
    begin
      post login_path, params: { username: user_pessoas.username, password: "senha-real" }
      assert_redirected_to dashboard_path
    ensure
      Pessoas::User.define_singleton_method(:buscar_por_cpf, original)
    end
  end

  # Task 21.7 (auditoria de cobertura): a 21.5 cobriu o login de sucesso do
  # usuário vindo do Pessoas, mas faltava o caminho de falha equivalente
  # (mesmo padrão do teste "deve rejeitar login com senha invalida", que só
  # cobre o usuário local via has_secure_password) — aqui a senha errada é
  # validada contra o hash bcrypt do pessoas2, não contra password_digest
  # local, então é um caminho de código diferente dentro de User#authenticate.
  test "deve rejeitar login de usuario vindo do pessoas com senha invalida" do
    user_pessoas = User.create!(nome_completo: "Vindo do Pessoas", password: "senha-local-irrelevante", cpf: "11122233344")
    hash = BCrypt::Password.create("senha-real")
    pessoas_user = Struct.new(:encrypted_password).new(hash)

    original = Pessoas::User.method(:buscar_por_cpf)
    Pessoas::User.define_singleton_method(:buscar_por_cpf) { |*_args, **_kwargs| pessoas_user }
    begin
      post login_path, params: { username: user_pessoas.username, password: "senha-errada" }
      assert_response :unprocessable_entity
      assert_select ".alert-danger", "Usuário ou senha inválidos"
    ensure
      Pessoas::User.define_singleton_method(:buscar_por_cpf, original)
    end
  end

  # Task 21.7: com a criação/exclusão manual removida (21.6), a única porta
  # de entrada pro sistema pra um usuário vindo do Pessoas é o login — se o
  # cpf existe no Frequencia (User local) mas não há mais registro
  # correspondente em Pessoas::User (conta removida/renomeada no pessoas2),
  # o login precisa falhar de forma limpa (sem 500), não travar numa porta
  # de autenticação órfã. Decisão já documentada em app/models/user.rb.
  test "deve rejeitar login de usuario com cpf sem registro correspondente no pessoas2" do
    user_pessoas = User.create!(nome_completo: "Cpf Orfao", password: "123456", cpf: "99988877766")

    original = Pessoas::User.method(:buscar_por_cpf)
    Pessoas::User.define_singleton_method(:buscar_por_cpf) { |*_args, **_kwargs| nil }
    begin
      post login_path, params: { username: user_pessoas.username, password: "123456" }
      assert_response :unprocessable_entity
      assert_select ".alert-danger", "Usuário ou senha inválidos"
    ensure
      Pessoas::User.define_singleton_method(:buscar_por_cpf, original)
    end
  end

  # Task 23.3 (verificação): a regra de usuário inativo (status != 1) vive NO
  # CONTROLLER (`user.status == 1` em #create), não no model — permaneceu
  # intacta durante a transição Devise. Teste documenta o contrato atual.
  test "deve rejeitar login de usuario inativo (status != 1)" do
    inativo = User.create!(nome_completo: "Inativo", password: "123456", status: 0)
    post login_path, params: { username: inativo.username, password: "123456" }
    assert_response :unprocessable_entity
    assert_select ".alert-danger", "Usuário ou senha inválidos"
  end
end
