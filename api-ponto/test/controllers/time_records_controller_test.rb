require "test_helper"

class TimeRecordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(nome_completo: "Admin Teste", password: "123456", admin: true, cpf: "55566677788")
    @user = User.create!(nome_completo: "Frequentador", password: "123456", cpf: "11122233344")
    @record = TimeRecord.create!(user: @user, raw_data: "#{@user.id}-15:07:2026:14:30:45", punched_at: Time.current, authentication_mode: "biometric")

    # @admin tem cpf preenchido só pra participar do filtro por nome
    # simulado abaixo — não representa uma conta vinda de verdade do
    # pessoas2. Como o login (task 21.5) agora valida cpf via
    # Pessoas::User.buscar_por_cpf, stubamos esse ponto de entrada pra
    # devolver o mesmo hash da senha local usada no login deste teste.
    # @admin e @user têm cpf preenchido só pra participar do filtro por nome
    # simulado abaixo — não representam contas vindas de verdade do
    # pessoas2. Como o login (task 21.5) agora valida cpf via
    # Pessoas::User.buscar_por_cpf, stubamos esse ponto de entrada pra
    # devolver o mesmo hash da senha local usada no login ("123456") pra
    # ambos, já que "usuario basico sempre ve o card..." abaixo também
    # loga como @user.
    senha_hash = BCrypt::Password.create("123456")
    cpfs_locais = [ @admin.cpf, @user.cpf ]
    # `Pessoas::User.buscar_por_cpf` já existe como método real na classe
    # — salva o original antes de sobrescrever e restaura explicitamente
    # no teardown (ver nota em test/models/user_test.rb sobre esse padrão).
    @buscar_por_cpf_original = Pessoas::User.method(:buscar_por_cpf)
    Pessoas::User.define_singleton_method(:buscar_por_cpf) do |cpf|
      cpfs_locais.include?(cpf) ? Struct.new(:encrypted_password).new(senha_hash) : nil
    end

    post login_path, params: { username: @admin.username, password: "123456" }

    # O filtro de Usuário funciona igual ao filtro Nome de admin/frequentadores
    # (pedido do usuário, 2026-09-02): busca via vínculo ativo do pessoas2
    # (Pessoas::Vinculo.cpfs_por_nome), não pelo nome_completo local.
    # pessoas_test não tem schema carregado (task 8.13) — simula a mesma
    # busca por nome contra os Users locais de teste (que já têm cpf
    # preenchido), igual ao padrão de stub já usado em
    # frequentadores_controller_test.rb.
    Pessoas::Vinculo.define_singleton_method(:cpfs_por_nome) do |nome|
      User.where("nome_completo ILIKE ?", "%#{nome}%").where.not(cpf: nil).pluck(:cpf)
    end
  end

  teardown do
    Pessoas::Vinculo.singleton_class.remove_method(:cpfs_por_nome)
    Pessoas::User.define_singleton_method(:buscar_por_cpf, @buscar_por_cpf_original)
  end

  test "deve listar registros de ponto" do
    get time_records_path
    assert_response :success
    assert_select ".app-content-header h1", "Registros de Ponto"
  end

  test "filtro de usuario busca pelo nome do pessoas2, nao pelo nome_completo local" do
    cpf_do_user = @user.cpf
    Pessoas::Vinculo.define_singleton_method(:cpfs_por_nome) { |_nome| [ cpf_do_user ] }

    get time_records_path, params: { usuario: "qualquer coisa que não bate com nome_completo local" }

    assert_response :success
    assert_select "th", "Dia" # modo "um usuário só" — resolveu pro @user via cpf
  ensure
    Pessoas::Vinculo.define_singleton_method(:cpfs_por_nome) do |nome|
      User.where("nome_completo ILIKE ?", "%#{nome}%").where.not(cpf: nil).pluck(:cpf)
    end
  end

  test "filtro de usuario nao retorna ninguem quando o pessoas2 nao encontra o nome" do
    Pessoas::Vinculo.define_singleton_method(:cpfs_por_nome) { |_nome| [] }

    get time_records_path, params: { usuario: @user.nome_completo }

    assert_response :success
    assert_select "th", { count: 0, text: "Dia" } # não resolveu pra nenhum usuário
    assert_select "tbody tr td", "Nenhum registro encontrado"
  ensure
    Pessoas::Vinculo.define_singleton_method(:cpfs_por_nome) do |nome|
      User.where("nome_completo ILIKE ?", "%#{nome}%").where.not(cpf: nil).pluck(:cpf)
    end
  end

  test "deve filtrar por usuario" do
    get time_records_path, params: { usuario: @user.nome_completo }
    assert_response :success
  end

  test "deve filtrar por ano e mes" do
    hoje = Time.current
    get time_records_path, params: { usuario: @user.nome_completo, ano: hoje.year, mes: hoje.month }
    assert_response :success
    assert_select "th", "Dia"
    assert_select "td", { count: 0, text: "Nenhum registro encontrado" }
  end

  test "nao deve retornar registro de mes diferente do filtrado" do
    outro_mes = 1.month.ago
    get time_records_path, params: { usuario: @user.nome_completo, ano: outro_mes.year, mes: outro_mes.month }
    assert_response :success
    assert_select "td", text: "Nenhum registro encontrado"
  end

  test "ano/mes futuro na URL nao trava a página (clamp pro presente)" do
    get time_records_path, params: { ano: Time.current.year + 5, mes: 12 }
    assert_response :success
  end

  test "sem filtro de usuario, admin nao ve a tabela de registros" do
    get time_records_path
    assert_response :success
    assert_select "th", { count: 0, text: "Usuário" }
    assert_select ".alert", text: /Busque um usuário/
  end

  test "com filtro de usuario que retorna varios resultados, admin ve o formato agregado (Usuario/Data/Marcacoes)" do
    get time_records_path, params: { usuario: "a" }
    assert_response :success
    assert_select "th", "Usuário"
    assert_select "th", "Data"
    assert_select "th", "Marcações"
    assert_select "th", { count: 0, text: "Trabalhado" }
  end

  test "com filtro de usuario, admin ve o card Dia/Trabalhado/Registro/Informacoes" do
    get time_records_path, params: { usuario: @user.nome_completo }
    assert_response :success
    assert_select "th", "Dia"
    assert_select "th", "Trabalhado"
    assert_select "th", "Registro"
    assert_select "th", "Informações"
  end

  test "usuario basico sempre ve o card Dia/Trabalhado/Registro, mesmo sem filtro" do
    delete logout_path
    post login_path, params: { username: @user.username, password: "123456" }

    get time_records_path
    assert_response :success
    assert_select "th", "Dia"
    assert_select "th", "Trabalhado"
    assert_select "th", { count: 0, text: "Usuário" }
  end

  test "Trabalhado soma so pares completos, ignorando marcacao impar" do
    dia = Time.zone.local(2026, 8, 18, 8, 0, 0)
    TimeRecord.create!(user: @user, raw_data: "x", punched_at: dia, authentication_mode: "manual", punch_type: "entry")
    TimeRecord.create!(user: @user, raw_data: "x", punched_at: dia + 4.hours + 30.minutes, authentication_mode: "manual", punch_type: "exit")
    TimeRecord.create!(user: @user, raw_data: "x", punched_at: dia + 9.hours, authentication_mode: "manual", punch_type: "entry")

    get time_records_path, params: { usuario: @user.nome_completo, ano: 2026, mes: 8 }
    assert_response :success
    assert_select "td", "18 ter"
    assert_select "td", "04:30:00"
  end

  test "dia sem par completo mostra Trabalhado 00:00:00" do
    dia = Time.zone.local(2026, 8, 19, 9, 0, 0)
    TimeRecord.create!(user: @user, raw_data: "x", punched_at: dia, authentication_mode: "manual", punch_type: "entry")

    get time_records_path, params: { usuario: @user.nome_completo, ano: 2026, mes: 8 }
    assert_response :success
    assert_select "td", "19 qua"
    assert_select "td", "00:00:00"
  end

  test "card Registro Mensal so aparece com usuario filtrado" do
    get time_records_path
    assert_response :success
    assert_select "h5", { count: 0, text: /Registro Mensal/ }

    get time_records_path, params: { usuario: @user.nome_completo }
    assert_response :success
    assert_select "h5", text: /Registro Mensal - \d{2}\/\d{4}/
  end

  test "Registro Mensal: Trabalhadas e Presencas somam so pares completos do mes" do
    hoje = Date.current
    dia = Time.zone.local(hoje.year, hoje.month, 1, 8, 0, 0)
    TimeRecord.create!(user: @user, raw_data: "x", punched_at: dia, authentication_mode: "manual", punch_type: "entry")
    TimeRecord.create!(user: @user, raw_data: "x", punched_at: dia + 8.hours, authentication_mode: "manual", punch_type: "exit")

    get time_records_path, params: { usuario: @user.nome_completo }
    assert_response :success
    assert_select "div.fw-bold", text: "08:00:00"
    assert_select "div.fw-bold", text: "1"
  end

  test "Registro Mensal: marcacao solta hoje conta como Em Aberto, dias passados sem marcacao contam como Ausencia" do
    hoje = Date.current
    skip "precisa de pelo menos 1 dia anterior no mes" if hoje.day < 2

    TimeRecord.create!(
      user: @user, raw_data: "x",
      punched_at: Time.zone.local(hoje.year, hoje.month, hoje.day, 9, 0, 0),
      authentication_mode: "manual", punch_type: "entry"
    )

    get time_records_path, params: { usuario: @user.nome_completo }
    assert_response :success

    dias_passados_sem_marcacao = hoje.day - 1
    assert_select "div.fw-bold", text: dias_passados_sem_marcacao.to_s
    assert_select "div.fw-bold", text: "1" # em aberto
  end
end
