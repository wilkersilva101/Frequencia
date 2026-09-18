# Sprint 23, task 23.2/23.4 — Model Role (Rolify).
#
# Tabelas criadas na task 23.2 (migration `RolifyCreateRoles`):
#   - `roles`: name, resource_type (polymorphic), resource_id
#   - `users_roles`: user_id, role_id (join table sem `id`)
#
# Task 23.4 — Gem `rolify` instalada. Atualizações:
#   1. `scopify` habilita scopes dinâmicos (`Role.admin`, `Role.gestor`, etc.)
#   2. `validates :resource_type` REMOVIDA deliberadamente (decisão abaixo).
#
# DECISÃO: Validação `resource_type inclusion: { in: Rolify.resource_types }`
# NÃO foi adicionada. O Frequencia usa exclusivamente roles GLOBAIS (sem
# resource) para admin/gestor/operador — nunca faremos
# `user.add_role(:admin, SomeModel)`. Sem a validação:
#   - roles globais (`resource_type: nil`) funcionam sem restrição
#   - `scopify` não depende dessa validação
#   - evitamos a configuração de `Rolify.resource_types` (que para roles
#     puramente globais seria sempre vazia/irrelevante)
# Se no futuro o projeto precisar de roles por resource, adicione:
#   validates :resource_type, inclusion: { in: Rolify.resource_types }, allow_nil: true
class Role < ApplicationRecord
  has_and_belongs_to_many :users, join_table: :users_roles

  belongs_to :resource,
             polymorphic: true,
             optional: true

  scopify
end
