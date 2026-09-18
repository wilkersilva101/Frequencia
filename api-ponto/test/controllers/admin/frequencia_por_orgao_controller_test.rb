require "test_helper"

module Admin
  class FrequenciaPorOrgaoControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(nome_completo: "Admin Teste", password: "123456", admin: true)
      post login_path, params: { username: @admin.username, password: "123456" }
    end

    # Pedido do usuário (2026-09-02): órgão/cpfs deixaram de vir do espelho
    # local (FrequentadorCache) e passaram a ser SELECT ao vivo no pessoas2
    # (Pessoas::Vinculo.orgaos_em_uso/.cpfs_por_orgao). pessoas_test não tem
    # schema carregado (task 8.13) — stubamos os dois pontos de entrada,
    # mesmo padrão já usado em frequentadores_controller_test.rb.
    def stub_orgaos(mapa_orgao_para_cpfs)
      Pessoas::Vinculo.define_singleton_method(:orgaos_em_uso) { mapa_orgao_para_cpfs.keys.sort }
      Pessoas::Vinculo.define_singleton_method(:cpfs_por_orgao) { |orgao| mapa_orgao_para_cpfs[orgao] || [] }

      yield
    ensure
      Pessoas::Vinculo.singleton_class.remove_method(:orgaos_em_uso)
      Pessoas::Vinculo.singleton_class.remove_method(:cpfs_por_orgao)
    end

    test "deve funcionar com base vazia" do
      stub_orgaos({}) do
        get frequencia_por_orgao_path
      end

      assert_response :success
      assert_select "td", text: "Nenhum registro encontrado"
    end

    test "agrupa presencas por orgao contando dias distintos com batida" do
      user = User.create!(nome_completo: "Fulano", password: "123456", cpf: "11122233344")

      dia1 = Time.zone.local(2026, 7, 10, 8, 0)
      dia1_tarde = Time.zone.local(2026, 7, 10, 17, 0)
      dia2 = Time.zone.local(2026, 7, 11, 8, 0)

      TimeRecord.create!(user: user, raw_data: "a", punched_at: dia1, authentication_mode: "biometric")
      TimeRecord.create!(user: user, raw_data: "b", punched_at: dia1_tarde, authentication_mode: "biometric")
      TimeRecord.create!(user: user, raw_data: "c", punched_at: dia2, authentication_mode: "biometric")

      stub_orgaos({ "Vara Cível" => [ "11122233344" ] }) do
        get frequencia_por_orgao_path
      end

      assert_response :success
      assert_select "td", text: "Vara Cível"
      # 2 batidas no mesmo dia contam como 1 presença + 1 batida no outro dia = 2
      assert_select "td", text: "2"
    end

    test "conta afastamentos como ausencias por orgao" do
      AfastamentoCache.create!(afastamento_id_pessoas: 1, cpf: "11122233344", tipo: "Férias", momento_inicial: Time.zone.local(2026, 7, 5))
      AfastamentoCache.create!(afastamento_id_pessoas: 2, cpf: "11122233344", tipo: "Licença", momento_inicial: Time.zone.local(2026, 7, 15))

      stub_orgaos({ "Vara Cível" => [ "11122233344" ] }) do
        get frequencia_por_orgao_path
      end

      assert_response :success
      assert_select "td", text: "2"
    end

    test "trabalhado aparece como travessao quando nao ha CalculoDiario calculado" do
      stub_orgaos({ "Vara Cível" => [ "11122233344" ] }) do
        get frequencia_por_orgao_path
      end

      assert_response :success
      assert_select "td.text-muted", text: "—", minimum: 1
    end

    test "trabalhado continua travessao mesmo com batidas de entrada e saida completas sem CalculoDiario" do
      # Prova que a coluna "Trabalhado" nao infere calculo a partir das
      # batidas brutas: mesmo com dados suficientes pra calcular horas
      # trabalhadas (entrada + saida no mesmo dia), a tela so mostra um
      # numero se `CalculoDiario` ja foi populado (task 17.3) -
      # `CalculoDiarioService.calcular` nao roda automaticamente ainda.
      user = User.create!(nome_completo: "Fulano", password: "123456", cpf: "11122233344")

      TimeRecord.create!(user: user, raw_data: "entrada", punched_at: Time.zone.local(2026, 7, 10, 8, 0), authentication_mode: "biometric")
      TimeRecord.create!(user: user, raw_data: "saida", punched_at: Time.zone.local(2026, 7, 10, 17, 0), authentication_mode: "biometric")

      stub_orgaos({ "Vara Cível" => [ "11122233344" ] }) do
        get frequencia_por_orgao_path
      end

      assert_response :success
      assert_select "td.text-muted", text: "—", minimum: 1
      # Nenhum valor numerico deve aparecer na coluna "Trabalhado" (ex: "9" horas)
      assert_select "td:nth-child(2)" do |cells|
        cells.each { |cell| assert_equal "—", cell.text.strip }
      end
    end

    test "trabalhado soma total_segundos dos CalculoDiario do orgao no periodo" do
      user1 = User.create!(nome_completo: "Fulano", password: "123456", cpf: "11122233344")
      user2 = User.create!(nome_completo: "Beltrano", password: "123456", cpf: "22233344455")

      CalculoDiario.create!(user: user1, data: Date.new(2026, 7, 10), meta_segundos: 18_000, total_segundos: 18_000)
      CalculoDiario.create!(user: user2, data: Date.new(2026, 7, 11), meta_segundos: 18_000, total_segundos: 3_600)
      # Fora do periodo filtrado (agosto) - nao deve entrar na soma
      CalculoDiario.create!(user: user1, data: Date.new(2026, 8, 1), meta_segundos: 18_000, total_segundos: 99_999)

      stub_orgaos({ "Vara Cível" => [ "11122233344", "22233344455" ] }) do
        get frequencia_por_orgao_path, params: { mes: 7, ano: 2026 }
      end

      assert_response :success
      # 18_000 + 3_600 = 21_600s = 06:00:00
      assert_select "td", text: "06:00:00"
    end

    test "filtra por orgao" do
      stub_orgaos({ "Vara Cível" => [ "11122233344" ], "Vara Criminal" => [ "55566677788" ] }) do
        get frequencia_por_orgao_path, params: { orgao: "Cível" }
      end

      assert_response :success
      assert_select "td", text: "Vara Cível"
      assert_select "td", text: "Vara Criminal", count: 0
    end

    test "filtra por mes e ano" do
      user = User.create!(nome_completo: "Fulano", password: "123456", cpf: "11122233344")

      TimeRecord.create!(user: user, raw_data: "julho", punched_at: Time.zone.local(2026, 7, 10, 8, 0), authentication_mode: "biometric")
      TimeRecord.create!(user: user, raw_data: "agosto", punched_at: Time.zone.local(2026, 8, 10, 8, 0), authentication_mode: "biometric")

      stub_orgaos({ "Vara Cível" => [ "11122233344" ] }) do
        get frequencia_por_orgao_path, params: { mes: 7, ano: 2026 }
      end

      assert_response :success
      assert_select "td", text: "1"
    end

    test "orgao sem frequentador algum nao aparece" do
      stub_orgaos({}) do
        get frequencia_por_orgao_path
      end

      assert_response :success
      assert_select "td", text: "Nenhum registro encontrado"
    end

    test "deve redirecionar para login se nao autenticado" do
      delete logout_path
      get frequencia_por_orgao_path
      assert_redirected_to login_path
    end
  end
end
