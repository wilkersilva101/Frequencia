# Sprint 23, task 23.9 — DECISÃO: `status: 1` NÃO foi migrado para Devise
# `confirmed_at`. Investigado antes de decidir:
#   - O model `User` (app/models/user.rb) habilita apenas
#     `:database_authenticatable, :registerable, :recoverable, :rememberable,
#     :validatable, :trackable` — o módulo `:confirmable` NÃO está na lista.
#   - Não existe coluna `confirmed_at` no schema (`db/schema.rb`) nem na
#     migration `20260910000000_add_devise_to_users.rb` (task 23.1), que é
#     explicitamente aditiva e documenta as colunas criadas — `confirmed_at`
#     não é uma delas.
#   - `status` continua sendo o mecanismo REAL de "ativo/inativo": usado no
#     scope `User.ativos` (`where(status: 1)`) e em
#     `active_for_authentication?` (`super && status == 1`, task 23.6), que é
#     o guard efetivo de login via Devise. Migrar/duplicar esse sinal para
#     `confirmed_at` sem o módulo `:confirmable` ativo não teria efeito algum
#     no fluxo de autenticação (Devise só verifica `confirmed_at` quando
#     `:confirmable` está incluso) — seria apenas uma coluna inerte, e
#     arriscaria (se `:confirmable` fosse ativado no futuro sem migração de
#     dados correspondente) bloquear login de usuários existentes com
#     `status: 1` mas `confirmed_at: nil`.
# Conclusão: manter `status` como fonte de verdade de "ativo" (sem alteração
# nesta task). Se o produto decidir adotar confirmação de e-mail via Devise
# no futuro, isso exige uma nova migration (`add_confirmable_to_users` com
# `confirmed_at`/`confirmation_token`/etc.), habilitar `:confirmable` no
# model, e um plano explícito de backfill de `confirmed_at` a partir de
# `status: 1` — decisão arquitetural fora do escopo desta task (seeds).
#
# Sprint 23, task 23.4 — Roles padrão do sistema (idempotentes).
# Criadas ANTES dos users para que possam ser atribuídas abaixo.
admin_role  = Role.find_or_create_by!(name: "admin")
gestor_role = Role.find_or_create_by!(name: "gestor")
operador_role = Role.find_or_create_by!(name: "operador")

puts "Roles criadas: #{[ admin_role, gestor_role, operador_role ].map(&:name).join(', ')}"

# Admin (username: admin.admin)
User.find_or_create_by!(nome_completo: "Admin Admin") do |u|
  u.password = "123456"
end

# Sprint 23, task 23.4 — Atribui role admin ao usuário admin.
# `add_role` lança erro se já existe, então verificamos primeiro.
admin_user = User.find_by(nome_completo: "Admin Admin")
if admin_user && !admin_user.has_role?(:admin)
  admin_user.add_role(:admin)
  puts "Role 'admin' atribuída ao usuário Admin Admin"
end

# Usuários de demonstração
User.find_or_create_by!(nome_completo: "João Biométrico") do |u|
  u.password = "123456"
  u.digitais_hash = "FIR_TEXTENCODE_SAMPLE_HASH_1234567890"
end

User.find_or_create_by!(nome_completo: "Maria Santos") do |u|
  u.password = "123456"
  u.digitais_hash = "FIR_TEXTENCODE_MARIA_HASH_0987654321"
end

User.find_or_create_by!(nome_completo: "Carlos Pereira") do |u|
  u.password = "123456"
end

# Registros de ponto falsos para demonstração
joao = User.find_by(nome_completo: "João Biométrico")
maria = User.find_by(nome_completo: "Maria Santos")
carlos = User.find_by(nome_completo: "Carlos Pereira")

if TimeRecord.count == 0
  agora = Time.current

  # Batidas de hoje
  [[joao, "biometric"], [maria, "biometric"], [carlos, "manual"]].each do |user, mode|
    TimeRecord.create!(
      user: user,
      raw_data: "#{user.id}-#{agora.strftime("%d:%m:%Y:%H:%M:%S")}",
      punched_at: agora - rand(1..8).hours,
      authentication_mode: mode
    )
  end

  # Batidas de dias anteriores
  [1, 2, 3, 5, 7].each do |day_ago|
    [joao, maria].each do |user|
      t = agora - day_ago.days - rand(4..10).hours
      TimeRecord.create!(
        user: user,
        raw_data: "#{user.id}-#{t.strftime("%d:%m:%Y:%H:%M:%S")}",
        punched_at: t,
        authentication_mode: "biometric"
      )
    end
  end
end
