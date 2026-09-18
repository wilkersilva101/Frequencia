require "test_helper"

# Sprint 23, task 23.1 — Valida que a migration AddDeviseToUsers criou
# todas as colunas Devise no model User sem remover colunas existentes.
class AddDeviseToUsersMigrationTest < ActiveSupport::TestCase
  # Colunas Devise que a migration deve ter adicionado
  DEVISE_COLUMNS = %w[
    email
    encrypted_password
    reset_password_token
    reset_password_sent_at
    remember_created_at
    sign_in_count
    current_sign_in_at
    last_sign_in_at
    current_sign_in_ip
    last_sign_in_ip
  ].freeze

  # Colunas que já existiam antes e NÃO devem ter sido removidas
  EXISTING_COLUMNS = %w[
    nome_completo
    username
    password_digest
    status
    digitais_hash
    cpf
    admin
  ].freeze

  # --- Schema: colunas existem ---

  test "all Devise columns exist on users table" do
    columns = User.column_names
    DEVISE_COLUMNS.each do |col|
      assert_includes columns, col, "missing Devise column: #{col}"
    end
  end

  test "existing columns are preserved after migration" do
    columns = User.column_names
    EXISTING_COLUMNS.each do |col|
      assert_includes columns, col, "existing column removed: #{col}"
    end
  end

  # --- Defaults e tipos ---

  test "encrypted_password defaults to empty string" do
    user = User.new
    assert_equal "", user.encrypted_password
  end

  test "sign_in_count defaults to 0" do
    user = User.new
    assert_equal 0, user.sign_in_count
  end

  test "email is nullable at database level" do
    user = User.new(
      nome_completo: "Teste Email Null",
      username: "teste.email.null",
      password: "123456",
      email: nil
    )
    assert user.save!
    assert_nil user.reload.email
  end

  # --- Indexes ---

  test "reset_password_token has a unique index" do
    indexes = ActiveRecord::Base.connection.indexes("users")
    token_index = indexes.find { |i| i.columns == ["reset_password_token"] }
    assert token_index, "missing index on reset_password_token"
    assert token_index.unique, "reset_password_token index should be unique"
  end

  test "username unique index still exists" do
    indexes = ActiveRecord::Base.connection.indexes("users")
    username_index = indexes.find { |i| i.columns == ["username"] }
    assert username_index, "username index removed"
    assert username_index.unique
  end

  test "cpf unique index still exists" do
    indexes = ActiveRecord::Base.connection.indexes("users")
    cpf_index = indexes.find { |i| i.columns == ["cpf"] }
    assert cpf_index, "cpf index removed"
    assert cpf_index.unique
  end

  # --- Integridade: model continua funcional com has_secure_password ---

  test "User still uses has_secure_password (password_digest intact)" do
    user = User.new(
      nome_completo: "Transicao Devise",
      password: "123456"
    )
    assert user.save!
    assert_not_nil user.password_digest
    assert user.authenticate("123456")
  end

  test "existing authenticate method still works for users without cpf" do
    user = users(:one)
    assert_nil user.cpf
    assert user.authenticate("123456")
    assert_not user.authenticate("senha-errada")
  end
end
