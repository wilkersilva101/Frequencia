require "test_helper"

class UserTest < ActiveSupport::TestCase
  # --- Validations ---

  test "valid with nome_completo, username and password" do
    user = User.new(nome_completo: "Novo Usuario", username: "novo.usuario", password: "123456")
    assert user.valid?
  end

  test "invalid without nome_completo" do
    user = User.new(username: "sem.nome", password: "123456")
    assert_not user.valid?
    assert_includes user.errors[:nome_completo], "não pode ficar em branco"
  end

  test "invalid without username" do
    user = User.new(nome_completo: "Sem Username", username: nil, password: "123456")
    user.define_singleton_method(:generate_username) { } # impede a geração automática
    assert_not user.valid?
    assert_includes user.errors[:username], "não pode ficar em branco"
  end

  test "invalid with duplicated username (case insensitive)" do
    existing = users(:one)
    user = User.new(nome_completo: "Duplicado", username: existing.username.upcase, password: "123456")
    assert_not user.valid?
    assert_includes user.errors[:username], "já está em uso"
  end

  test "invalid without status" do
    user = User.new(nome_completo: "Sem Status", password: "123456")
    user.status = nil
    assert_not user.valid?
    assert_includes user.errors[:status], "não pode ficar em branco"
  end

  test "invalid with password shorter than 6 characters" do
    user = User.new(nome_completo: "Senha Curta", password: "123")
    assert_not user.valid?
    assert_includes user.errors[:password], "é muito curto (mínimo: 6 caracteres)"
  end

  test "valid without password when updating existing record" do
    user = users(:one)
    user.nome_completo = "Usuario Teste Um Atualizado"
    assert user.valid?
  end

  # --- generate_username callback ---

  test "generates username automatically from nome_completo when blank" do
    user = User.create!(nome_completo: "Fulano de Tal", password: "123456")
    assert_equal "fulano.tal", user.username
  end

  test "does not overwrite username when already present" do
    user = User.create!(nome_completo: "Ciclano", username: "usuario.manual", password: "123456")
    assert_equal "usuario.manual", user.username
  end

  test "generates unique username when there is a collision" do
    User.create!(nome_completo: "Fulano de Tal", password: "123456")
    outro = User.create!(nome_completo: "Fulano de Tal", password: "123456")
    assert_equal "fulano.tal.2", outro.username
  end

  # --- has_secure_password ---

  test "authenticates with correct password" do
    user = users(:one)
    assert user.authenticate("123456")
  end

  test "does not authenticate with incorrect password" do
    user = users(:one)
    assert_not user.authenticate("senha-errada")
  end

  # --- Autenticação via Pessoas (task 21.5) ---
  #
  # Não usamos dados reais no banco `pessoas` de teste (sem schema
  # carregado, mesma limitação documentada em
  # test/services/resolver_cpf_por_matricula_service_test.rb) — stubamos
  # o ponto de entrada único, `Pessoas::User.buscar_por_cpf`.
  #
  # ATENÇÃO: `Pessoas::User` já tem `buscar_por_cpf` como método real
  # (não stubado por padrão), então salvamos o método original antes de
  # sobrescrever e restauramos explicitamente no `ensure` — um stub que
  # simplesmente `remove_method` deixaria a classe sem o método depois.
  def stub_pessoas_user(resposta)
    original = Pessoas::User.method(:buscar_por_cpf)
    Pessoas::User.define_singleton_method(:buscar_por_cpf) { |*_args, **_kwargs| resposta }
    yield
  ensure
    Pessoas::User.define_singleton_method(:buscar_por_cpf, original)
  end

  # `Pessoas::User` não pode ser instanciado de verdade em teste — o banco
  # `pessoas_test` não tem a tabela `users` (sem schema carregado). Como o
  # fluxo de autenticação só lê `encrypted_password`, um duck type simples
  # (Struct) basta e evita tocar a conexão `pessoas` de teste.
  PessoasUserStub = Struct.new(:encrypted_password)

  test "usuario com cpf autentica com a senha real do pessoas2 (hash bcrypt)" do
    hash = BCrypt::Password.create("senha-real-do-pessoas")
    user = User.create!(nome_completo: "Vindo do Pessoas", password: "senha-local-irrelevante", cpf: "11122233344")
    pessoas_user = PessoasUserStub.new(hash)

    stub_pessoas_user(pessoas_user) do
      assert user.authenticate("senha-real-do-pessoas")
    end
  end

  test "usuario com cpf rejeita senha incorreta mesmo que bata com a senha local" do
    hash = BCrypt::Password.create("senha-real-do-pessoas")
    user = User.create!(nome_completo: "Vindo do Pessoas", password: "senha-local-irrelevante", cpf: "11122233344")
    pessoas_user = PessoasUserStub.new(hash)

    stub_pessoas_user(pessoas_user) do
      assert_not user.authenticate("senha-local-irrelevante")
    end
  end

  test "usuario com cpf sem registro correspondente no pessoas2 nao autentica" do
    user = User.create!(nome_completo: "Cpf Orfao", password: "123456", cpf: "99988877766")

    stub_pessoas_user(nil) do
      assert_not user.authenticate("123456")
    end
  end

  test "usuario sem cpf (admin local) continua autenticando via has_secure_password" do
    user = users(:one)
    assert_nil user.cpf
    assert user.authenticate("123456")
  end

  # Task 21.7 (auditoria de cobertura): não existe mais "consistência
  # eventual"/"reprocessamento de evento perdido" (isso era do modelo antigo
  # de API+eventos assíncronos, abandonado na task 8.12 em favor de SELECT
  # direto e somente-leitura no Postgres do pessoas2 — não há fila nem
  # reprocessamento a testar). O equivalente real hoje é: o que acontece
  # quando a leitura ao pessoas2 falha (conexão indisponível/timeout) no
  # ponto crítico de autenticação. `Pessoas::User.buscar_por_cpf` não tem
  # rescue em nenhuma camada (`app/models/user.rb#authenticate`, nem
  # `Admin::SessionsController#create`) — este teste documenta o
  # comportamento real atual (a exceção propaga, sem fallback silencioso
  # pra senha local), não um mecanismo novo.
  test "authenticate propaga erro quando a leitura ao pessoas2 falha (sem fallback silencioso)" do
    user = User.create!(nome_completo: "Vindo do Pessoas", password: "senha-local-irrelevante", cpf: "11122233344")

    original = Pessoas::User.method(:buscar_por_cpf)
    Pessoas::User.define_singleton_method(:buscar_por_cpf) { |*_args, **_kwargs| raise ActiveRecord::ConnectionNotEstablished, "conexao indisponivel" }
    begin
      assert_raises(ActiveRecord::ConnectionNotEstablished) { user.authenticate("qualquer-senha") }
    ensure
      Pessoas::User.define_singleton_method(:buscar_por_cpf, original)
    end
  end

  # --- Devise (task 23.3) ---
  #
  # Contrato da coexistência has_secure_password × Devise durante a
  # transição (ver comentários numerados em app/models/user.rb):
  #  1. os 6 módulos Devise exigidos no sprint estão ativos;
  #  2. `password=` grava AMBAS as colunas (password_digest p/ auth local atual
  #     via `super`, encrypted_password p/ o Devise futuro da task 23.6);
  #  3. `password_digest` reader/writer continuam lendo/gravando a coluna real
  #     (sem colisão com o `password_digest(password)` interno do Devise);
  #  4. `validatable` NÃO exige email durante a transição (users do Pessoas2
  #     podem não ter email — decisão 23.1 — e os locais ainda não migraram);
  #  5. o `valid_password?` do Devise já valida a encrypted_password gravada;
  #  6. `clean_up_passwords` (Devise) não apaga os digests das colunas;
  #  7. usuários com `cpf` continuam autenticando APENAS contra o Pessoas2
  #     (a encrypted_password local gravada não vira porta alternativa).

  test "devise modules exigidos no sprint estao ativos no User" do
    %i[
      database_authenticatable
      registerable
      recoverable
      rememberable
      validatable
      trackable
    ].each do |modulo|
      assert_includes User.devise_modules, modulo
    end
  end

  test "password= grava password_digest (has_secure_password) e encrypted_password (Devise)" do
    user = User.create!(nome_completo: "Dual Write", password: "123456")
    assert_not_nil user.password_digest
    assert_not_empty user.encrypted_password
    assert BCrypt::Password.new(user.password_digest).is_password?("123456")
  end

  test "usuario local criado apos o devise continua autenticando via has_secure_password (super)" do
    user = User.create!(nome_completo: "Novo Local", password: "123456")
    assert_equal user, user.authenticate("123456")
    assert_not user.authenticate("senha-errada")
  end

  test "password_digest reader continua lendo a coluna (sem conflito com Devise password_digest(pw))" do
    user = users(:one)
    assert_not_nil user.password_digest
    assert BCrypt::Password.new(user.password_digest).is_password?("123456")

    # writer explícito (task 23.3) também segue gravando a coluna real
    nova = BCrypt::Password.create("nova-senha")
    user.password_digest = nova
    user.save!
    assert_equal nova.to_s, user.reload.password_digest
    assert user.authenticate("nova-senha")
  end

  test "usuario com cpf do pessoas2 nao precisa de email (decisao 23.1)" do
    user = User.create!(nome_completo: "Do Pessoas", password: "123456", cpf: "11122233344")
    assert_nil user.email
    assert user.valid?
  end

  test "usuario local sem cpf nao precisa de email durante a transicao (23.3)" do
    user = User.create!(nome_completo: "Admin Local", password: "123456")
    assert_nil user.email
    assert user.valid?
  end

  test "email_required? retorna false durante a transicao (validatable nao exige email)" do
    assert_not User.new.email_required?
  end

  test "valid_password? (Devise) valida contra encrypted_password ja na transicao" do
    user = User.create!(nome_completo: "Devise Pronto", password: "123456")
    assert user.valid_password?("123456")
    assert_not user.valid_password?("errada")
  end

  test "clean_up_passwords (Devise) nao apaga password_digest nem encrypted_password" do
    user = User.create!(nome_completo: "Clean Up", password: "123456")
    user.clean_up_passwords
    assert_not_nil user.password_digest
    assert_not_empty user.encrypted_password
    assert user.authenticate("123456")
  end

  test "usuario com cpf autentica contra pessoas2 mesmo tendo encrypted_password local gravada" do
    hash = BCrypt::Password.create("senha-real-do-pessoas")
    user = User.create!(nome_completo: "Vindo do Pessoas", password: "senha-local", cpf: "11122233344")

    # `password=` gravou a senha local (dual write), mas para quem tem cpf
    # a encrypted_password local NUNCA é a fonte de verdade.
    assert user.encrypted_password.present?

    stub_pessoas_user(PessoasUserStub.new(hash)) do
      assert user.authenticate("senha-real-do-pessoas")
      assert_not user.authenticate("senha-local")
    end
  end

  # --- Devise routing (task 23.6) ---
  #
  # O Devise agora autentica por `username` (auth key configurada no
  # initializer) e o Warden usa estes três pontos do model:
  #  1. `find_for_database_authentication` — busca por username;
  #  2. `valid_password?` — roteia usuário com cpf para o Pessoas2;
  #  3. `active_for_authentication?` — bloqueia status != 1.

  test "find_for_database_authentication busca por username (case insensitive)" do
    user = users(:one) # username "usuario.teste.um"

    assert_equal user, User.find_for_database_authentication(username: "usuario.teste.um")
    assert_equal user, User.find_for_database_authentication(username: "USUARIO.TESTE.UM")
    assert_nil User.find_for_database_authentication(username: "nao.existe")
  end

  test "find_for_database_authentication ignora busca por email (username e a chave)" do
    user = users(:one)
    # Mesmo que alguém passe `email`, o sobrescrito só olha `username`.
    assert_equal user, User.find_for_database_authentication(username: "usuario.teste.um", email: user.email)
    assert_nil User.find_for_database_authentication(email: "qualquer@email.com")
  end

  test "valid_password? roteia usuario com cpf para o Pessoas2 (Nao a senha local)" do
    hash = BCrypt::Password.create("senha-real-do-pessoas")
    user = User.create!(nome_completo: "Devise Pessoas", password: "senha-local-irrelevante", cpf: "11122233344")

    stub_pessoas_user(PessoasUserStub.new(hash)) do
      assert user.valid_password?("senha-real-do-pessoas")
      assert_not user.valid_password?("senha-local-irrelevante")
    end
  end

  test "valid_password? retorna false para usuario com cpf sem registro no pessoas2" do
    user = User.create!(nome_completo: "Devise Cpf Orfao", password: "123456", cpf: "99988877766")

    stub_pessoas_user(nil) do
      assert_not user.valid_password?("123456")
    end
  end

  test "valid_password? valida senha local para usuario sem cpf" do
    user = User.create!(nome_completo: "Devise Local", password: "123456")
    assert_nil user.cpf

    assert user.valid_password?("123456")
    assert_not user.valid_password?("errada")
  end

  test "active_for_authentication? retorna false para usuario inativo (status != 1)" do
    inativo = User.create!(nome_completo: "Devise Inativo", password: "123456", status: 0)
    ativo = User.create!(nome_completo: "Devise Ativo", password: "123456", status: 1)

    assert_not inativo.active_for_authentication?
    assert ativo.active_for_authentication?
  end

  # --- Scopes ---

  test "scope ativos returns only users with status 1" do
    inativo = User.create!(nome_completo: "Usuario Inativo", password: "123456", status: 0)
    assert_includes User.ativos, users(:one)
    assert_not_includes User.ativos, inativo
  end

  test "scope com_digitais returns only users with digitais_hash present" do
    com_digital = User.create!(nome_completo: "Com Digital", password: "123456", digitais_hash: "HASH123")
    assert_includes User.com_digitais, com_digital
    assert_not_includes User.com_digitais, users(:one)
  end

  # --- Associations ---

  test "has many time_records via TimeRecord#user association" do
    user = users(:one)
    record = TimeRecord.create!(
      user: user,
      raw_data: "raw",
      punched_at: Time.zone.now,
      authentication_mode: "biometric"
    )
    assert_equal user, record.user
  end

  test "belongs_to frequentador_cache via cpf" do
    user = User.create!(nome_completo: "Com Vinculo", password: "123456", cpf: "11122233344")
    cache = FrequentadorCache.create!(cpf: "11122233344", nome: "Com Vinculo")

    assert_equal cache, user.reload.frequentador_cache
  end

  test "frequentador_cache fica nil quando nao ha cpf ou nao ha cache correspondente" do
    sem_cpf = User.create!(nome_completo: "Sem Cpf", password: "123456")
    assert_nil sem_cpf.frequentador_cache

    com_cpf_sem_cache = User.create!(nome_completo: "Sem Cache", password: "123456", cpf: "99988877766")
    assert_nil com_cpf_sem_cache.frequentador_cache
  end

  # --- Rolify (task 23.4) ---
  #
  # Valida que o `rolify` (adicionado ao model User na task 23.4) habilita
  # corretamente os métodos de gerenciamento de roles. A existência da gem
  # e do call `rolify` no model é o que torna esses métodos disponíveis.

  test "user responds to rolify instance methods" do
    user = users(:one)
    assert_respond_to user, :has_role?
    assert_respond_to user, :add_role
    assert_respond_to user, :remove_role
    assert_respond_to user, :roles
  end

  test "user responds to rolify class methods" do
    assert_respond_to User, :with_role
  end

  test "add_role creates role and assigns to user" do
    user = users(:one)
    user.add_role(:admin)
    assert user.has_role?(:admin)
    assert_includes user.roles.pluck(:name), "admin"
  end

  test "has_role? returns true when user has the role" do
    user = users(:one)
    user.add_role(:gestor)
    assert user.has_role?(:gestor)
  end

  test "has_role? returns false when user does not have the role" do
    user = users(:one)
    assert_not user.has_role?(:admin)
  end

  test "remove_role removes role from user" do
    user = users(:one)
    user.add_role(:operador)
    assert user.has_role?(:operador)
    user.remove_role(:operador)
    assert_not user.has_role?(:operador)
  end

  test "with_role returns users with the specified role" do
    user = users(:one)
    user.add_role(:admin)
    admin_users = User.with_role(:admin)
    assert_includes admin_users, user
  end

  test "with_role excludes users without the role" do
    user = users(:one)
    admin_users = User.with_role(:admin)
    assert_not_includes admin_users, user
  end

  test "add_role is idempotent (adding same role twice does not duplicate)" do
    user = users(:one)
    user.add_role(:admin)
    user.add_role(:admin) # segunda chamada não deve duplicar
    assert_equal 1, user.roles.where(name: "admin").count
  end

  test "rolify coexists with has_secure_password and authenticate" do
    user = users(:one)
    user.add_role(:admin)
    # Autenticação continua funcionando normalmente
    assert user.authenticate("123456")
    assert_not user.authenticate("senha-errada")
    # Role atribuída corretamente
    assert user.has_role?(:admin)
  end

  test "rolify coexists with Devise modules" do
    user = User.create!(nome_completo: "Rolify Devise", password: "123456")
    user.add_role(:gestor)
    assert user.has_role?(:gestor)
    # Devise modules continuam ativos
    assert_includes User.devise_modules, :database_authenticatable
    assert user.valid_password?("123456")
  end

  test "rolify coexists with authenticate custom (Pessoas2 via CPF)" do
    hash = BCrypt::Password.create("senha-real-do-pessoas")
    user = User.create!(nome_completo: "Cpf Rolify", password: "senha-local", cpf: "11122233344")
    user.add_role(:operador)
    assert user.has_role?(:operador)

    stub_pessoas_user(PessoasUserStub.new(hash)) do
      assert user.authenticate("senha-real-do-pessoas")
      assert_not user.authenticate("senha-local")
    end
  end

  test "multiple roles on same user" do
    user = users(:one)
    user.add_role(:admin)
    user.add_role(:gestor)
    assert user.has_role?(:admin)
    assert user.has_role?(:gestor)
    assert_equal 2, user.roles.count
  end
end
