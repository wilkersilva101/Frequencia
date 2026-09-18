require "test_helper"

# Task 24.9 — Fechamento da Sprint 24.
#
# Sem infraestrutura de teste de sistema (Capybara/Selenium) no projeto —
# confirmado nas tasks 24.7/24.8 — "testar dark mode toggle via clique real"
# não é viável aqui. Critério de saída reinterpretado para o que é testável
# via `bin/rails test` (requisição HTTP real + inspeção do HTML/CSS gerados):
#
#   1. CSS carrega sem erros: o layout admin referencia o bundle compilado
#      (`app/assets/builds/application.css`, task 24.4) e essa URL responde
#      200 (não 404) quando requisitada de verdade.
#   2. Dark mode toggle funciona: o HTML da página contém o elemento raiz
#      com `data-controller="theme"` e o dropdown com as 3 opções de toggle
#      (claro/escuro/automático) adicionado na task 24.7; e o CSS compilado
#      contém as regras `[data-bs-theme=dark]` portadas na task 24.3 — o
#      clique real (JS em browser) não é testável sem Capybara.
#   3. Font Awesome icons renderizam: views migradas (task 24.5) usam
#      classes `fas fa-*` (não mais `bi bi-*`) no HTML renderizado.
class AdminLayoutAssetsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(nome_completo: "Admin Teste", password: "123456", admin: true)
    post login_path, params: { username: @user.username, password: "123456" }
  end

  test "layout admin referencia o CSS compilado e o asset responde sem erro" do
    get regimes_path
    assert_response :success

    assert_select "link[rel=stylesheet][href*='application']", 1 do |links|
      href = links.first["href"]
      get href
      assert_response :success
      assert_match "text/css", @response.media_type
    end
  end

  test "layout admin expoe o controller Stimulus de tema com as opcoes de toggle" do
    get regimes_path
    assert_response :success

    assert_match(/data-controller="theme"/, @response.body)
    assert_select "button[data-action='theme#pick'][data-theme-mode-param='light']"
    assert_select "button[data-action='theme#pick'][data-theme-mode-param='dark']"
    assert_select "button[data-action='theme#pick'][data-theme-mode-param='auto']"
  end

  test "CSS compilado contem as regras de dark mode portadas na task 24.3" do
    css_path = Rails.root.join("app/assets/builds/application.css")
    assert File.exist?(css_path), "app/assets/builds/application.css precisa existir (rode yarn build:css)"

    css = File.read(css_path)
    assert_match(/\[data-bs-theme=dark\]\s*\.card/, css)
    assert_match(/\[data-bs-theme=dark\]\s*\.btn-light/, css)
  end

  test "views migradas renderizam icones Font Awesome, sem residuo de Bootstrap Icons" do
    Regime.create!(nome: "Jornada A", categorias: [ "SERVIDOR_CARREIRA" ], modalidade: "HORAS_COM_INTERVALO")

    get regimes_path
    assert_response :success

    assert_select "i.fas.fa-plus"
    assert_select "i.fas.fa-pencil"
    assert_select "i.fas.fa-trash"
    assert_select "i[class*='bi-']", 0
    assert_no_match(/class="bi bi-/, @response.body)
  end
end
