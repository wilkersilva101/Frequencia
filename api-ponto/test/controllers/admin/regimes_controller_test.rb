require "test_helper"

module Admin
  class RegimesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = User.create!(nome_completo: "Admin Teste", password: "123456", admin: true)
      post login_path, params: { username: @user.username, password: "123456" }
    end

    test "deve listar regimes cadastrados" do
      Regime.create!(nome: "Jornada A", categorias: [ "SERVIDOR_CARREIRA" ], modalidade: "HORAS_COM_INTERVALO")
      Regime.create!(nome: "Jornada B", categorias: [ "ESTAGIARIO" ], modalidade: "OCORRENCIAS")

      get regimes_path

      assert_response :success
      assert_select "table tbody tr", count: Regime.count
      assert_select "td", text: "Jornada A"
      assert_select "td", text: "Jornada B"
      assert_select ".card-title", text: /Servidor Efetivo/
      assert_select ".card-title", text: "SERVIDOR_CARREIRA", count: 0
      assert_select "td", text: "Horas com intervalo"
      assert_select "td", text: "Ocorrências"
      assert_select "td", text: "HORAS_COM_INTERVALO", count: 0
      assert_select "td", text: "OCORRENCIAS", count: 0
    end

    test "nao lista regime excluido" do
      Regime.create!(nome: "Jornada Visivel")
      Regime.create!(nome: "Jornada Excluida", excluido: true)

      get regimes_path

      assert_response :success
      assert_select "td", text: "Jornada Visivel"
      assert_select "td", text: "Jornada Excluida", count: 0
    end

    test "nao lista regime marcado como nao visivel" do
      Regime.create!(nome: "Jornada Visivel")
      Regime.create!(nome: "Jornada Invisivel", visivel: false)

      get regimes_path

      assert_response :success
      assert_select "td", text: "Jornada Visivel"
      assert_select "td", text: "Jornada Invisivel", count: 0
    end

    test "nao lista regime substituido por uma versao mais nova (anterior_id)" do
      antigo = Regime.create!(nome: "Jornada Antiga")
      Regime.create!(nome: "Jornada Nova", anterior: antigo)

      get regimes_path

      assert_response :success
      assert_select "td", text: "Jornada Nova"
      assert_select "td", text: "Jornada Antiga", count: 0
    end

    test "lista regime antigo se a versao mais nova que o substituiu estiver excluida" do
      antigo = Regime.create!(nome: "Jornada Antiga")
      Regime.create!(nome: "Jornada Nova", anterior: antigo, excluido: true)

      get regimes_path

      assert_response :success
      assert_select "td", text: "Jornada Antiga"
    end

    test "deve funcionar com base vazia" do
      get regimes_path

      assert_response :success
      assert_select ".card-body", text: "Nenhum regime cadastrado"
    end

    test "filtra por nome" do
      Regime.create!(nome: "Jornada Especial")
      Regime.create!(nome: "Outra Jornada")

      get regimes_path, params: { nome: "Especial" }

      assert_response :success
      assert_select "td", text: "Jornada Especial"
      assert_select "td", text: "Outra Jornada", count: 0
    end

    test "filtra por categoria" do
      Regime.create!(nome: "Jornada Efetivo", categorias: [ "SERVIDOR_CARREIRA" ])
      Regime.create!(nome: "Jornada Estagiario", categorias: [ "ESTAGIARIO" ])

      get regimes_path, params: { categoria: "SERVIDOR_CARREIRA" }

      assert_response :success
      assert_select "td", text: "Jornada Efetivo"
      assert_select "td", text: "Jornada Estagiario", count: 0
    end

    test "filtra por regime com multiplas categorias (aparece se qualquer uma bater)" do
      Regime.create!(nome: "Jornada Mista", categorias: [ "SERVIDOR_CARREIRA", "CEDIDO" ])

      get regimes_path, params: { categoria: "CEDIDO" }

      assert_response :success
      assert_select "td", text: "Jornada Mista"
    end

    test "filtra por modalidade" do
      Regime.create!(nome: "Jornada Horas", modalidade: "HORAS")
      Regime.create!(nome: "Jornada Ocorrencias", modalidade: "OCORRENCIAS")

      get regimes_path, params: { modalidade: "OCORRENCIAS" }

      assert_response :success
      assert_select "td", text: "Jornada Ocorrencias"
      assert_select "td", text: "Jornada Horas", count: 0
    end

    test "combina filtro de categoria e modalidade" do
      Regime.create!(nome: "Bate os dois", modalidade: "HORAS", categorias: [ "ESTAGIARIO" ])
      Regime.create!(nome: "So bate categoria", modalidade: "OCORRENCIAS", categorias: [ "ESTAGIARIO" ])

      get regimes_path, params: { categoria: "ESTAGIARIO", modalidade: "HORAS" }

      assert_response :success
      assert_select "td", text: "Bate os dois"
      assert_select "td", text: "So bate categoria", count: 0
    end

    test "deve redirecionar para login se nao autenticado" do
      delete logout_path
      get regimes_path
      assert_redirected_to login_path
    end

    test "deve mostrar formulario de novo regime" do
      get new_regime_path
      assert_response :success
    end

    test "deve criar regime" do
      assert_difference("Regime.count") do
        post regimes_path, params: { regime: { nome: "Jornada Nova", categorias: [ "SERVIDOR_CARREIRA" ], modalidade: "HORAS", resumo: "8h/dia", meta_semanal: "40h" } }
      end
      assert_redirected_to regimes_path
      assert_equal [ "SERVIDOR_CARREIRA" ], Regime.last.categorias
    end

    test "nao deve criar regime com modalidade invalida" do
      assert_no_difference("Regime.count") do
        post regimes_path, params: { regime: { nome: "Jornada Nova", modalidade: "Presencial" } }
      end
      assert_response :unprocessable_entity
    end

    test "nao deve criar regime invalido" do
      assert_no_difference("Regime.count") do
        post regimes_path, params: { regime: { nome: "" } }
      end
      assert_response :unprocessable_entity
    end

    test "deve mostrar formulario de edicao" do
      regime = Regime.create!(nome: "Jornada Editável")
      get edit_regime_path(regime)
      assert_response :success
    end

    test "deve atualizar regime" do
      regime = Regime.create!(nome: "Jornada Editável")
      patch regime_path(regime), params: { regime: { nome: "Nome Alterado" } }
      assert_redirected_to regimes_path
      assert_equal "Nome Alterado", regime.reload.nome
    end

    test "deve atualizar categorias do regime" do
      regime = Regime.create!(nome: "Jornada Editável", categorias: [ "SERVIDOR_CARREIRA" ])
      patch regime_path(regime), params: { regime: { categorias: [ "AUXILIAR_DA_JUSTICA", "CEDIDO" ] } }
      assert_redirected_to regimes_path
      assert_equal [ "AUXILIAR_DA_JUSTICA", "CEDIDO" ], regime.reload.categorias
    end

    test "nao deve atualizar regime com dados invalidos" do
      regime = Regime.create!(nome: "Jornada Editável")
      patch regime_path(regime), params: { regime: { nome: "" } }
      assert_response :unprocessable_entity
      assert_not_equal "", regime.reload.nome
    end

    test "deve excluir regime" do
      regime = Regime.create!(nome: "Jornada Excluível")
      assert_difference("Regime.count", -1) do
        delete regime_path(regime)
      end
      assert_redirected_to regimes_path
    end

    test "nao deve excluir regime com frequentadores vinculados" do
      regime = Regime.create!(nome: "Jornada Com Vinculo")
      user = User.create!(nome_completo: "Frequentador", password: "123456")
      RegimeFrequentador.create!(user: user, regime: regime, momento_inicial: Time.current)

      assert_no_difference("Regime.count") do
        delete regime_path(regime)
      end
      assert_redirected_to regimes_path
    end

    test "usuario nao-admin nao deve acessar formulario de novo regime" do
      login_como_nao_admin

      get new_regime_path

      # Task 23.7 — CanCanCan: acesso negado redireciona para o dashboard
      # (rescue_from CanCan::AccessDenied), não mais para o recurso.
      assert_redirected_to dashboard_path
    end

    test "usuario nao-admin nao deve criar regime" do
      login_como_nao_admin

      assert_no_difference("Regime.count") do
        post regimes_path, params: { regime: { nome: "Jornada Nova" } }
      end
      assert_redirected_to dashboard_path
    end

    test "usuario nao-admin nao deve acessar formulario de edicao" do
      login_como_nao_admin

      regime = Regime.create!(nome: "Jornada Qualquer")
      get edit_regime_path(regime)

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
