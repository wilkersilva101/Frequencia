# Sprint 23, task 23.1 — Adicionar colunas Devise ao users.
#
# Esta migration é PURAMENTE ADITIVA: não remove password_digest nem altera
# o model User (que continua usando has_secure_password + authenticate
# custom contra Pessoas2). As colunas aqui criadas ficarão inativas até a
# task 23.3, que adiciona `devise :database_authenticatable, ...` ao model.
#
# Decisões:
#   - email: nullable (tasks futuras decidirão unicidade) — o Pessoas2 não
#     fornece email para todos os servidores, e users sem email (ex.:
#     cadastros manuais) precisam existir sem quebrar NOT NULL.
#   - current_sign_in_ip / last_sign_in_ip: `string` (não `inet` do basic8)
#     para manter compatibilidade com endpoints legados que enviam IP como
#     texto. Devise aceita ambos — faz `.to_s` internamente.
#   - password_digest NÃO é removido: has_secure_password continua ativo
#     durante a transição (sprint 23.3+).
class AddDeviseToUsers < ActiveRecord::Migration[8.0]
  def change
    # Database authenticatable
    add_column :users, :email,              :string
    add_column :users, :encrypted_password, :string, default: ""

    # Recoverable
    add_column :users, :reset_password_token,    :string
    add_column :users, :reset_password_sent_at,  :datetime

    # Rememberable
    add_column :users, :remember_created_at, :datetime

    # Trackable
    add_column :users, :sign_in_count,      :integer, default: 0, null: false
    add_column :users, :current_sign_in_at, :datetime
    add_column :users, :last_sign_in_at,    :datetime
    add_column :users, :current_sign_in_ip, :string
    add_column :users, :last_sign_in_ip,    :string

    # Indexes
    add_index :users, :reset_password_token, unique: true
  end
end
