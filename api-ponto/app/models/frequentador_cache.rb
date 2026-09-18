class FrequentadorCache < ApplicationRecord
  # Espelho local de dados do sistema Pessoas (via sticapi_client) — não é
  # cadastro próprio do Frequencia. Alimentado por ImportarDadosPessoaJob
  # (Sprint 8) e sua extensão de sincronização (Sprint 10). Ver
  # docs/integracao-pessoas-sticapi.md.

  has_one :user, foreign_key: :cpf, primary_key: :cpf, inverse_of: :frequentador_cache
  has_many :afastamento_caches, foreign_key: :cpf, primary_key: :cpf, inverse_of: :frequentador_cache

  validates :cpf, presence: true, uniqueness: true, format: { with: /\A\d{11}\z/ }

  def self.find_by_user(user)
    find_by(cpf: user.cpf)
  end
end
