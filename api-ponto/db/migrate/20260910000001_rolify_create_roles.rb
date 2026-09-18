# Sprint 23, task 23.2 — Criar tabelas roles + users_roles (Rolify).
#
# Migration aditiva: cria as duas tabelas necessárias para o Rolify
# (roles + join table users_roles), seguindo o schema do basic8.
#
# NOTA: a gem `rolify` ainda NÃO está no Gemfile (task 23.4). Esta migration
# cria apenas a estrutura de banco — o model Role será funcional somente
# após a instalação da gem (task 23.4), que adiciona `scopify` e a validação
# de `resource_type`.
#
# Decisões:
#   - Migration única `RolifyCreateRoles` (padrão basic8, cria ambas as tabelas)
#   - `users_roles`: tabela join sem `id` (`id: false`), como padrão Rolify
#   - Índices compostos seguindo o basic8:
#     - `index_roles_on_name_and_resource_type_and_resource_id`
#     - `index_users_roles_on_user_id_and_role_id`
class RolifyCreateRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :roles do |t|
      t.string :name
      t.references :resource, polymorphic: true

      t.timestamps
    end

    create_table :users_roles, id: false do |t|
      t.references :user
      t.references :role
    end

    add_index :roles, [:name, :resource_type, :resource_id]
    add_index :users_roles, [:user_id, :role_id]
  end
end
