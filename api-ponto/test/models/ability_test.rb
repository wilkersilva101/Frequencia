require "test_helper"

# Sprint 23, task 23.5 — Testes do model Ability (CanCanCan).
# Atualizado na task 23.7: usuário autenticado sem role ganha baseline de
# leitura (`can :read, :all`) — ver DECISÃO na Ability. Guest continua sem nada.
#
# Matriz de permissões validada: cada role (admin/gestor/operador + guest +
# usuário autenticado sem role) × cada ação/recurso relevante. Baseado nos
# models reais do Frequencia (TimeRecord, IntervencaoFrequencia, User,
# EstacaoPonto, RelatorioFrequenciaFinal, Role...).
class AbilityTest < ActiveSupport::TestCase
  # --- Helpers ---

  def ability_for(user)
    Ability.new(user)
  end

  # --- Guest (User.new, sem id) ---

  test "guest has no permissions at all" do
    ability = ability_for(User.new)
    assert_not ability.can?(:read, TimeRecord)
    assert_not ability.can?(:read, User)
    assert_not ability.can?(:read, IntervencaoFrequencia)
    assert_not ability.can?(:read, EstacaoPonto)
    assert_not ability.can?(:manage, :all)
  end

  test "guest cannot manage any resource" do
    ability = ability_for(User.new)
    assert_not ability.can?(:manage, TimeRecord)
    assert_not ability.can?(:manage, User)
  end

  # --- Usuário autenticado sem role e sem admin? (baseline de transição 23.7) ---

  test "plain user without role keeps read access (transition baseline)" do
    ability = ability_for(users(:one))
    assert ability.can?(:read, TimeRecord)
    assert ability.can?(:read, User)
    assert ability.can?(:read, :all)
    assert_not ability.can?(:manage, :all)
    assert_not ability.can?(:manage, TimeRecord)
    assert_not ability.can?(:manage, User)
  end

  # --- Admin via role Rolify ---

  test "admin via rolify role can manage all" do
    user = users(:one)
    user.add_role(:admin)
    ability = ability_for(user)
    assert ability.can?(:manage, :all)
    assert ability.can?(:manage, TimeRecord)
    assert ability.can?(:manage, IntervencaoFrequencia)
    assert ability.can?(:manage, User)
    assert ability.can?(:manage, EstacaoPonto)
    assert ability.can?(:read, RelatorioFrequenciaFinal)
  end

  # --- Admin via coluna booleana legacy (transição) ---

  test "admin via legacy boolean column can manage all" do
    user = users(:one)
    user.update!(admin: true)
    ability = ability_for(user)
    assert ability.can?(:manage, :all)
    assert ability.can?(:manage, TimeRecord)
  end

  test "admin works via both paths (boolean OR role) during transition" do
    role_admin = users(:one)
    role_admin.add_role(:admin)
    boolean_admin = users(:two)
    boolean_admin.update!(admin: true)

    assert ability_for(role_admin).can?(:manage, :all)
    assert ability_for(boolean_admin).can?(:manage, :all)

    # Nenhum dos dois perde o acesso por ter/ não ter o outro mecanismo:
    role_admin.update!(admin: true)
    assert ability_for(role_admin).can?(:manage, :all)
    assert ability_for(boolean_admin.reload).can?(:manage, :all)
  end

  # --- Gestor ---

  test "gestor can read all resources" do
    user = users(:one)
    user.add_role(:gestor)
    ability = ability_for(user)
    assert ability.can?(:read, TimeRecord)
    assert ability.can?(:read, User)
    assert ability.can?(:read, IntervencaoFrequencia)
    assert ability.can?(:read, EstacaoPonto)
    assert ability.can?(:read, RelatorioFrequenciaFinal)
    assert ability.can?(:read, RegistroMensalFrequencia)
  end

  test "gestor can manage TimeRecord (frequencia)" do
    user = users(:one)
    user.add_role(:gestor)
    ability = ability_for(user)
    assert ability.can?(:manage, TimeRecord)
    assert ability.can?(:create, TimeRecord)
    assert ability.can?(:update, TimeRecord)
    assert ability.can?(:destroy, TimeRecord)
  end

  test "gestor can manage IntervencaoFrequencia" do
    user = users(:one)
    user.add_role(:gestor)
    ability = ability_for(user)
    assert ability.can?(:manage, IntervencaoFrequencia)
    assert ability.can?(:create, IntervencaoFrequencia)
    assert ability.can?(:update, IntervencaoFrequencia)
    assert ability.can?(:deferir, IntervencaoFrequencia)
  end

  test "gestor cannot manage resources outside his scope" do
    user = users(:one)
    user.add_role(:gestor)
    ability = ability_for(user)
    assert_not ability.can?(:manage, :all)
    assert_not ability.can?(:manage, User)
    assert_not ability.can?(:manage, EstacaoPonto)
    assert_not ability.can?(:manage, Role)
    assert_not ability.can?(:create, EstacaoPonto)
    assert_not ability.can?(:destroy, Role)
  end

  # --- Operador ---

  test "operador is read only (can read all, cannot manage anything)" do
    user = users(:one)
    user.add_role(:operador)
    ability = ability_for(user)
    assert ability.can?(:read, TimeRecord)
    assert ability.can?(:read, User)
    assert ability.can?(:read, IntervencaoFrequencia)
    assert ability.can?(:read, EstacaoPonto)
    assert ability.can?(:read, RelatorioFrequenciaFinal)

    assert_not ability.can?(:manage, :all)
    assert_not ability.can?(:manage, TimeRecord)
    assert_not ability.can?(:manage, IntervencaoFrequencia)
    assert_not ability.can?(:manage, User)
    assert_not ability.can?(:create, TimeRecord)
    assert_not ability.can?(:update, IntervencaoFrequencia)
    assert_not ability.can?(:destroy, EstacaoPonto)
  end

  # --- Matriz consolidada (role × ação × recurso) ---

  test "permission matrix matches expected rows" do
    guest = ability_for(User.new)
    plain = ability_for(users(:one))
    operador = ability_for(create_role_user(:operador))
    gestor = ability_for(create_role_user(:gestor))
    admin_role = ability_for(create_role_user(:admin))

    matriz = {
      # [ability, ação, recurso] => esperado
      [ guest, :read, :all ] => false,
      [ guest, :manage, :all ] => false,
      # Task 23.7 — baseline de transição: usuário autenticado sem role
      # mantém `can :read, :all` (preserva acesso read-only pré-CanCanCan).
      [ plain, :read, TimeRecord ] => true,
      [ plain, :manage, :all ] => false,

      [ operador, :read, :all ] => true,
      [ operador, :read, TimeRecord ] => true,
      [ operador, :read, IntervencaoFrequencia ] => true,
      [ operador, :manage, :all ] => false,
      [ operador, :create, TimeRecord ] => false,
      [ operador, :destroy, EstacaoPonto ] => false,

      [ gestor, :read, :all ] => true,
      [ gestor, :read, User ] => true,
      [ gestor, :manage, TimeRecord ] => true,
      [ gestor, :manage, IntervencaoFrequencia ] => true,
      [ gestor, :manage, :all ] => false,
      [ gestor, :manage, User ] => false,
      [ gestor, :manage, Role ] => false,

      [ admin_role, :manage, :all ] => true,
      [ admin_role, :manage, TimeRecord ] => true,
      [ admin_role, :manage, User ] => true,
      [ admin_role, :manage, EstacaoPonto ] => true,
      [ admin_role, :read, RelatorioFrequenciaFinal ] => true
    }

    matriz.each do |(ability, acao, recurso), esperado|
      assert_equal esperado, ability.can?(acao, recurso),
                   "esperado can?(#{acao.inspect}, #{recurso.inspect}) == #{esperado}"
    end
  end

  # --- Coexistência com auth (regressão da transição) ---

  test "ability coexists with rolify + admin? without touching authentication" do
    user = users(:one)
    user.add_role(:gestor)
    # Authentication paths untouched by Ability:
    assert user.authenticate("123456")
    assert_not user.authenticate("senha-errada")
    assert ability_for(user).can?(:read, TimeRecord)
  end

  private

  def create_role_user(role)
    user = users(:two)
    user.add_role(role)
    user
  end
end
