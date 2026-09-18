require "test_helper"

# Sprint 23, task 23.2/23.4 — Testes do model Role.
#
# Task 23.2: testes básicos de ActiveRecord (HABTM, polymorphic, destruição).
# Task 23.4: `scopify` habilitado — validação de scopes globais/polymorphic.
class RoleTest < ActiveSupport::TestCase
  # --- Fixtures ---

  test "fixtures loaded" do
    assert_equal 3, Role.count
    assert_includes Role.pluck(:name), "admin"
    assert_includes Role.pluck(:name), "gestor"
    assert_includes Role.pluck(:name), "operador"
  end

  # --- Validações ---

  test "role is valid with a name" do
    role = Role.new(name: "viewer")
    assert role.valid?
  end

  test "role is valid without a resource" do
    role = Role.new(name: "viewer")
    assert role.valid?
    assert_nil role.resource
  end

  # --- Associações ---

  test "role can have many users via join table" do
    role = Role.find_by!(name: "admin")
    user1 = users(:one)
    user2 = User.create!(
      nome_completo: "Segundo Usuario",
      username: "segundo.usuario",
      password: "123456"
    )
    role.users << [ user1, user2 ]
    assert_equal 2, role.users.count
    assert_includes role.user_ids, user1.id
    assert_includes role.user_ids, user2.id
  end

  test "polymorphic association works" do
    user = users(:one)
    role = Role.create!(name: "owner", resource: user)
    assert_equal user, role.resource
    assert_equal "User", role.resource_type
  end

  test "polymorphic resource can be nil" do
    role = Role.create!(name: "global_admin")
    assert_nil role.resource
    assert_nil role.resource_type
  end

  # --- Destrução ---

  test "destroying role removes join table entries" do
    user = users(:one)
    role = Role.create!(name: "temp")
    role.users << user
    role_id = role.id
    assert_equal 1, Role.where(name: "temp").count
    role.destroy
    assert_equal 0, Role.where(id: role_id).count
    # join table entry should also be gone
    join_count = ActiveRecord::Base.connection.select_value(
      "SELECT COUNT(*) FROM users_roles WHERE role_id = #{role_id}"
    )
    assert_equal 0, join_count
  end

  # --- Rolify: scopify scopes (task 23.4) ---
  #
  # `scopify` adiciona ao model Role 3 scopes:
  #   - `global`: roles sem resource (resource_type e resource_id NULL)
  #   - `class_scoped`: roles com resource_type mas sem resource_id
  #   - `instance_scoped`: roles com resource_type E resource_id
  # Não cria scopes dinâmicos por nome (ex: Role.admin). O frequencia usa
  # roles globais (sem resource) para admin/gestor/operador.

  test "scopify adds global scope" do
    assert_respond_to Role, :global
  end

  test "scopify adds class_scoped scope" do
    assert_respond_to Role, :class_scoped
  end

  test "scopify adds instance_scoped scope" do
    assert_respond_to Role, :instance_scoped
  end

  test "global scope returns roles without resource" do
    global_roles = Role.global
    # Todas as roles fixtures são globais (sem resource)
    assert_equal 3, global_roles.count
    assert_includes global_roles.pluck(:name), "admin"
    assert_includes global_roles.pluck(:name), "gestor"
    assert_includes global_roles.pluck(:name), "operador"
  end

  test "instance_scoped returns empty when no roles have a specific resource" do
    assert_empty Role.instance_scoped
  end

  test "instance_scoped returns role when assigned to a specific resource" do
    user = users(:one)
    role = Role.find_by!(name: "admin")
    role.update!(resource: user)
    assert_equal 1, Role.instance_scoped.count
    assert_includes Role.instance_scoped, role
  end

  # --- Rolify: validações ---

  test "resource_type is optional (global roles work without resource)" do
    role = Role.new(name: "global_op")
    assert role.valid?
    assert_nil role.resource_type
  end

  test "resource_type accepts polymorphic association" do
    user = users(:one)
    role = Role.new(name: "scoped_role", resource: user)
    assert role.valid?
    assert_equal "User", role.resource_type
  end

  test "scope refreshes when role is created" do
    new_role = Role.create!(name: "supervisor")
    assert_includes Role.global, new_role
  end

  test "scope refreshes when role is destroyed" do
    role = Role.create!(name: "temp_role")
    assert_includes Role.global, role
    role.destroy
    assert_not_includes Role.global.map(&:id), role.id
  end
end
