class AfastamentoCache < ApplicationRecord
  # Espelho local de dados de Afastamento/TipoAfastamento/MotivoAfastamento
  # do sistema Pessoas (via sticapi_client) — não é cadastro próprio.
  # Alimentado por um job de sincronização (Sprint 12), mesmo padrão de
  # FrequentadorCache (Sprint 10). Ver SPRINT-PLAN.md, Sprint 12.

  belongs_to :frequentador_cache, foreign_key: :cpf, primary_key: :cpf, inverse_of: :afastamento_caches, optional: true

  validates :afastamento_id_pessoas, presence: true, uniqueness: true
  validates :cpf, presence: true
end
