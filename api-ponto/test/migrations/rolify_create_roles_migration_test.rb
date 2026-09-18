require "test_helper"

# Sprint 23, task 23.2 — Valida que a migration RolifyCreateRoles criou
# as tabelas `roles` e `users_roles` com colunas e índices corretos.
class RolifyCreateRolesMigrationTest < ActiveSupport::TestCase
  # --- Schema: tabelas existem ---

  test "roles table exists" do
    assert ActiveRecord::Base.connection.table_exists?("roles"),
           "roles table does not exist"
  end

  test "users_roles table exists" do
    assert ActiveRecord::Base.connection.table_exists?("users_roles"),
           "users_roles table does not exist"
  end

  # --- Schema: colunas da tabela roles ---

  test "roles table has name column" do
    columns = ActiveRecord::Base.connection.columns("roles").map(&:name)
    assert_includes columns, "name"
  end

  test "roles table has resource_type column (polymorphic)" do
    columns = ActiveRecord::Base.connection.columns("roles").map(&:name)
    assert_includes columns, "resource_type"
  end

  test "roles table has resource_id column (polymorphic)" do
    columns = ActiveRecord::Base.connection.columns("roles").map(&:name)
    assert_includes columns, "resource_id"
  end

  test "roles table has timestamps" do
    columns = ActiveRecord::Base.connection.columns("roles").map(&:name)
    assert_includes columns, "created_at"
    assert_includes columns, "updated_at"
  end

  # --- Schema: colunas da tabela users_roles ---

  test "users_roles table has user_id column" do
    columns = ActiveRecord::Base.connection.columns("users_roles").map(&:name)
    assert_includes columns, "user_id"
  end

  test "users_roles table has role_id column" do
    columns = ActiveRecord::Base.connection.columns("users_roles").map(&:name)
    assert_includes columns, "role_id"
  end

  test "users_roles table has no id column (join table)" do
    columns = ActiveRecord::Base.connection.columns("users_roles").map(&:name)
    assert_not_includes columns, "id",
                        "users_roles should not have an id column (join table)"
  end

  # --- Indexes ---

  test "roles has composite index on name, resource_type, resource_id" do
    indexes = ActiveRecord::Base.connection.indexes("roles")
    composite = indexes.find do |i|
      i.columns == ["name", "resource_type", "resource_id"]
    end
    assert composite,
           "missing composite index on roles [name, resource_type, resource_id]"
  end

  test "users_roles has composite index on user_id, role_id" do
    indexes = ActiveRecord::Base.connection.indexes("users_roles")
    composite = indexes.find do |i|
      i.columns == ["user_id", "role_id"]
    end
    assert composite,
           "missing composite index on users_roles [user_id, role_id]"
  end

  # --- Integridade: CRUD básico funciona ---

  test "can create a role" do
    role = Role.create!(name: "admin")
    assert role.persisted?
    assert_equal "admin", role.name
  end

  test "can create a role with polymorphic resource" do
    user = users(:one)
    role = Role.create!(name: "editor", resource: user)
    assert role.persisted?
    assert_equal user, role.resource
    assert_equal "User", role.resource_type
  end

  test "role resource is optional" do
    role = Role.create!(name: "viewer")
    assert role.persisted?
    assert_nil role.resource
  end

  # --- Join table: inserção direta via SQL ---

  test "can insert into users_roles join table" do
    user = users(:one)
    role = Role.create!(name: "admin")
    ActiveRecord::Base.connection.execute(
      "INSERT INTO users_roles (user_id, role_id) VALUES (#{user.id}, #{role.id})"
    )
    count = ActiveRecord::Base.connection.select_value(
      "SELECT COUNT(*) FROM users_roles WHERE user_id = #{user.id} AND role_id = #{role.id}"
    )
    assert_equal 1, count
  end

  test "join table entry can be queried from roles side" do
    user = users(:one)
    role = Role.create!(name: "editor")
    ActiveRecord::Base.connection.execute(
      "INSERT INTO users_roles (user_id, role_id) VALUES (#{user.id}, #{role.id})"
    )
    # Verifica que o HABTM do Role funciona (usa a join table)
    assert_includes role.reload.user_ids, user.id
  end
end
