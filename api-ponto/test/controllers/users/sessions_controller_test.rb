require "test_helper"

# Task 23.6 — Fluxo Devise (Users::SessionsController).
#
# Cobrem as rotas Devise (/u/sign_in, /u/sign_out) e garantem que:
# - login é por `username` (não email)
# - usuário com `cpf` autentica contra o hash bcrypt do Pessoas2
# - usuário sem `cpf` autentica contra a senha local
# - usuário inativo (status != 1) é bloqueado
# - após login via Devise, `session[:user_id]` fica setado para que o
#   contexto admin (Admin::ApplicationController) reconheça o usuário
class Users::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(nome_completo: "Devise Admin", password: "123456")
  end

  test "deve logar via rota devise (POST /u/sign_in) com username e definir session" do
    post user_session_path, params: { user: { username: @user.username, password: "123456" } }

    assert_redirected_to dashboard_path
    assert_equal @user.id, session[:user_id], "session[:user_id] precisa estar setado para o contexto admin"
    follow_redirect!
    assert_response :success
  end

  test "deve logar via rota devise usando username (nao email)" do
    # Usuário não tem `email` — se o Devise usasse email como auth key,
    # este login falharia. Garante que `authentication_keys = [:username]`
    # está em vigor.
    assert_nil @user.email
    assert_nil @user.cpf

    post user_session_path, params: { user: { username: @user.username, password: "123456" } }

    assert_redirected_to dashboard_path
  end

  test "deve logar via rota devise usuario vindo do pessoas2 (cpf) com a senha real" do
    user_pessoas = User.create!(nome_completo: "Devise Pessoas", password: "senha-local-irrelevante", cpf: "11122233344")
    hash = BCrypt::Password.create("senha-real")
    pessoas_user = Struct.new(:encrypted_password).new(hash)

    original = Pessoas::User.method(:buscar_por_cpf)
    Pessoas::User.define_singleton_method(:buscar_por_cpf) { |*_args, **_kwargs| pessoas_user }
    begin
      post user_session_path, params: { user: { username: user_pessoas.username, password: "senha-real" } }
      assert_redirected_to dashboard_path
      assert_equal user_pessoas.id, session[:user_id]
    ensure
      Pessoas::User.define_singleton_method(:buscar_por_cpf, original)
    end
  end

  test "deve rejeitar via rota devise usuario com cpf e senha errada (Pessoas2)" do
    user_pessoas = User.create!(nome_completo: "Devise Pessoas Errado", password: "senha-local-irrelevante", cpf: "11122233344")
    hash = BCrypt::Password.create("senha-real")
    pessoas_user = Struct.new(:encrypted_password).new(hash)

    original = Pessoas::User.method(:buscar_por_cpf)
    Pessoas::User.define_singleton_method(:buscar_por_cpf) { |*_args, **_kwargs| pessoas_user }
    begin
      post user_session_path, params: { user: { username: user_pessoas.username, password: "senha-errada" } }
      # Falha: Warden recall → re-render da view de login (admin view reusada)
      # com flash.now de alert, status configurado via responder.error_status.
      assert_response :unprocessable_content
      assert_select ".alert-danger", "Username ou senha inválidos."
    ensure
      Pessoas::User.define_singleton_method(:buscar_por_cpf, original)
    end
  end

  test "deve bloquear usuario inativo (status != 1) via rota devise" do
    inativo = User.create!(nome_completo: "Devise Inativo", password: "123456", status: 0)

    post user_session_path, params: { user: { username: inativo.username, password: "123456" } }

    # active_for_authentication? == false → Warden `after_set_user` hook
    # descarta + failure app redireciona para /u/sign_in com alert de inativo.
    assert_redirected_to new_user_session_path
    assert_nil session[:user_id]
  end

  test "deve fazer logout via rota devise (DELETE /u/sign_out)" do
    post user_session_path, params: { user: { username: @user.username, password: "123456" } }
    follow_redirect!
    assert_response :success

    delete destroy_user_session_path
    assert_redirected_to login_path
    assert_nil session[:user_id]
  end

  test "deve fazer logout via /logout (admin) apos login via admin" do
    # Fluxo legado (Admin::SessionsController): session[:user_id] é a fonte
    # de verdade; o logout em /logout (Users::SessionsController#destroy)
    # precisa limpar session[:user_id] mesmo sem usuário no Warden.
    post login_path, params: { username: @user.username, password: "123456" }
    assert_equal @user.id, session[:user_id]

    delete logout_path
    assert_redirected_to login_path
    assert_nil session[:user_id]
  end
end
