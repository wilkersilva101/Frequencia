require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(nome_completo: "Admin Teste", password: "123456", admin: true)
    post login_path, params: { username: @user.username, password: "123456" }

    # "Frequentadores" trocou de FrequentadorCache.count (espelho local)
    # para Pessoas::Vinculo.ativos.count (SELECT ao vivo no pessoas2) —
    # pedido do usuário, 2026-09-02. pessoas_test não tem schema carregado
    # (task 8.13) — stuba vazio por padrão, sobrescrito nos testes que
    # precisam de uma contagem específica.
    stub_vinculos_ativos([])
  end

  teardown do
    Pessoas::Vinculo.singleton_class.remove_method(:ativos) if Pessoas::Vinculo.singleton_class.method_defined?(:ativos)
  end

  def stub_vinculos_ativos(lista)
    Pessoas::Vinculo.singleton_class.remove_method(:ativos) if Pessoas::Vinculo.singleton_class.method_defined?(:ativos)
    Pessoas::Vinculo.define_singleton_method(:ativos) { lista }
  end

  test "deve carregar dashboard" do
    get dashboard_path
    assert_response :success
    assert_select ".app-content-header h1", "Dashboard"
  end

  test "deve redirecionar para login se nao autenticado" do
    delete logout_path
    get dashboard_path
    assert_redirected_to login_path
  end

  # Sprint 15 (task 15.1/15.3): KPIs simples de "Fase A" — contagem direta
  # de frequentadores, estações e batidas do dia, sem nenhum cálculo de
  # banco de horas/frequência (isso é Fase B, task 15.2 garante que nenhum
  # KPI dependa disso).
  test "deve exibir contagem real de frequentadores, estacoes e batidas do dia" do
    TimeRecord.delete_all
    EstacaoPonto.delete_all

    stub_vinculos_ativos(%w[11111111111 22222222222])

    EstacaoPonto.create!(descricao: "Estação Recepção", cod_ativacao: "estacao-recepcao")

    outro_usuario = User.create!(nome_completo: "Servidor Teste", password: "123456")
    TimeRecord.create!(
      user: outro_usuario,
      raw_data: "{}",
      punched_at: Time.current,
      authentication_mode: "manual",
      punch_type: "entry"
    )

    get dashboard_path
    assert_response :success
    assert_match(%r{<h3>\s*2\s*</h3>\s*<p>Frequentadores</p>}m, response.body)
    assert_match(%r{<h3>\s*1\s*</h3>\s*<p>Estações de Ponto</p>}m, response.body)
    assert_match(%r{<h3>\s*1\s*</h3>\s*<p>Batidas Hoje</p>}m, response.body)
  end

  test "deve carregar dashboard sem erro com base vazia" do
    TimeRecord.delete_all
    EstacaoPonto.delete_all

    get dashboard_path

    assert_response :success
    assert_select ".app-content-header h1", "Dashboard"
    assert_match(%r{<h3>\s*0\s*</h3>\s*<p>Frequentadores</p>}m, response.body)
    assert_match(%r{<h3>\s*0\s*</h3>\s*<p>Estações de Ponto</p>}m, response.body)
    assert_match(%r{<h3>\s*0\s*</h3>\s*<p>Batidas Hoje</p>}m, response.body)
  end

  # Task 17.3 — 1o KPI do dashboard baseado em dado calculado real (Fase B,
  # Sprint 17): soma de `RegistroMensalFrequencia#faltas` do mes corrente.
  test "deve exibir faltas do mes como zero sem RegistroMensalFrequencia calculado" do
    get dashboard_path

    assert_response :success
    assert_match(%r{Faltas no Mês</p>\s*<h3 class="mb-0">\s*0\s*</h3>}m, response.body)
  end

  test "deve somar faltas do mes a partir de RegistroMensalFrequencia calculados" do
    hoje = Time.zone.today
    usuario1 = User.create!(nome_completo: "Fulano", password: "123456")
    usuario2 = User.create!(nome_completo: "Beltrano", password: "123456")

    RegistroMensalFrequencia.create!(user: usuario1, ano: hoje.year, mes: hoje.month, data_inicio: hoje.beginning_of_month, data_fim: hoje.end_of_month, faltas: 2)
    RegistroMensalFrequencia.create!(user: usuario2, ano: hoje.year, mes: hoje.month, data_inicio: hoje.beginning_of_month, data_fim: hoje.end_of_month, faltas: 3)
    # Mes anterior nao deve entrar na soma
    mes_anterior = hoje.prev_month
    RegistroMensalFrequencia.create!(user: usuario1, ano: mes_anterior.year, mes: mes_anterior.month, data_inicio: mes_anterior.beginning_of_month, data_fim: mes_anterior.end_of_month, faltas: 99)

    get dashboard_path

    assert_response :success
    assert_match(%r{Faltas no Mês</p>\s*<h3 class="mb-0">\s*5\s*</h3>}m, response.body)
  end
end
