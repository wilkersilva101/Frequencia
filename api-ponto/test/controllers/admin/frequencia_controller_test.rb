require "test_helper"

module Admin
  class FrequenciaControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(nome_completo: "Admin Teste", password: "123456", admin: true)
      post login_path, params: { username: @admin.username, password: "123456" }
    end

    test "deve listar registros reais de frequencia" do
      frequentador = User.create!(nome_completo: "Frequentador Um", password: "123456")
      estacao = EstacaoPonto.create!(descricao: "Estação Teste", cod_ativacao: "cod-teste-001")
      TimeRecord.create!(user: frequentador, raw_data: "raw", punched_at: Time.zone.now, authentication_mode: "biometric", punch_type: "entry", estacao_ponto: estacao)

      get frequencia_path

      assert_response :success
      assert_select "td", text: "Frequentador Um"
      assert_select "td", text: "Entrada"
      assert_select "td", text: "Biometria"
      assert_select "td", text: "Estação Teste"
    end

    test "deve funcionar com base vazia" do
      get frequencia_path

      assert_response :success
      assert_select "td", text: "Nenhum registro encontrado"
    end

    test "filtra por frequentador" do
      user_a = User.create!(nome_completo: "Alice Registrada", password: "123456")
      user_b = User.create!(nome_completo: "Bob Registrado", password: "123456")
      TimeRecord.create!(user: user_a, raw_data: "a", punched_at: Time.zone.now, authentication_mode: "biometric")
      TimeRecord.create!(user: user_b, raw_data: "b", punched_at: Time.zone.now, authentication_mode: "biometric")

      get frequencia_path, params: { frequentador: "Alice" }

      assert_response :success
      assert_select "td", text: "Alice Registrada"
      assert_select "td", text: "Bob Registrado", count: 0
    end

    test "filtra por estacao" do
      frequentador = User.create!(nome_completo: "Frequentador", password: "123456")
      estacao_a = EstacaoPonto.create!(descricao: "Estação A", cod_ativacao: "cod-a")
      estacao_b = EstacaoPonto.create!(descricao: "Estação B", cod_ativacao: "cod-b")
      TimeRecord.create!(user: frequentador, raw_data: "a", punched_at: Time.zone.now, authentication_mode: "biometric", estacao_ponto: estacao_a)
      TimeRecord.create!(user: frequentador, raw_data: "b", punched_at: Time.zone.now, authentication_mode: "biometric", estacao_ponto: estacao_b)

      get frequencia_path, params: { estacao: "Estação A" }

      assert_response :success
      assert_select "td", text: "Estação A"
      assert_select "td", text: "Estação B", count: 0
    end

    test "filtra por data" do
      frequentador = User.create!(nome_completo: "Frequentador", password: "123456")
      TimeRecord.create!(user: frequentador, raw_data: "hoje", punched_at: Time.zone.now, authentication_mode: "biometric")
      TimeRecord.create!(user: frequentador, raw_data: "ontem", punched_at: 1.day.ago, authentication_mode: "biometric")

      get frequencia_path, params: { data: Date.current.to_s }

      assert_response :success
      assert_equal 1, TimeRecord.where(raw_data: "hoje").count
    end

    test "data invalida no filtro nao quebra a tela" do
      get frequencia_path, params: { data: "data-invalida" }
      assert_response :success
    end

    test "registro sem estacao_ponto associada nao quebra a tela" do
      frequentador = User.create!(nome_completo: "Frequentador", password: "123456")
      TimeRecord.create!(user: frequentador, raw_data: "sem-estacao", punched_at: Time.zone.now, authentication_mode: "manual")

      get frequencia_path

      assert_response :success
    end

    test "grid mostra batida recebida de verdade pelo canal presenca/* (ponta a ponta)" do
      frequentador = User.create!(nome_completo: "Frequentador Real", password: "123456")
      estacao = EstacaoPonto.create!(descricao: "Estação Real", cod_ativacao: "cod-e2e-13-4")

      registros = "#{frequentador.id}-15:07:2026:14:30:45"
      enc = CryptoDes.encrypt(registros)

      post presenca_ajax_SincronizarRegistrosPonto_path, params: { registros: enc, codAtivacao: estacao.cod_ativacao }
      assert_response :success
      assert_equal "sincronizado", @response.body

      get frequencia_path

      assert_response :success
      assert_select "td", text: "Frequentador Real"
      assert_select "td", text: "Estação Real"
    end

    test "deve redirecionar para login se nao autenticado" do
      delete logout_path
      get frequencia_path
      assert_redirected_to login_path
    end
  end
end
