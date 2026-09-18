require "test_helper"

# Task 23.8 — View real do Devise (app/views/users/sessions/new.html.erb).
# Garante que a tela renderiza (layout "login" + form Devise nativo),
# complementando os testes de fluxo de autenticação já cobertos em
# test/controllers/users/sessions_controller_test.rb.
class DeviseLoginViewSmokeTest < ActionDispatch::IntegrationTest
  test "GET /u/sign_in renders the Devise login view with a username/password form" do
    get new_user_session_path

    assert_response :success
    assert_select "form"
    assert_select "input[name='user[username]']"
    assert_select "input[name='user[password]']"
  end
end
