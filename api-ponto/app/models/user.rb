class User < ApplicationRecord
  # Sprint 23, task 23.4 — Rolify: habilita `has_role?`, `add_role`,
  # `with_role` e associação `has_many :roles` no model.
  # Posicionado antes de `has_secure_password` para que a cadeia de
  # ancestrais não tenha conflitos com módulos Devise/BCrypt.
  rolify

  has_secure_password

  # Sprint 23 (task 23.3): módulos Devise ativados no model. A autenticação
  # REAL continua passando pelo método `authenticate` custom (mais abaixo)
  # até a task 23.6 rotear o Devise — o `valid_password?` do
  # DatabaseAuthenticatable não é usado por enquanto (validaria contra
  # `encrypted_password` local, que para usuários com `cpf` NÃO pode ser a
  # fonte de verdade). `password_digest`/`has_secure_password` permanecem
  # ativos durante toda a transição (não remover — ver NOTA na iteration 23).
  devise :database_authenticatable, :registerable, :recoverable, :rememberable,
         :validatable, :trackable

  has_many :time_records, dependent: :restrict_with_exception
  has_many :regime_frequentadores, dependent: :restrict_with_exception
  has_many :regimes, through: :regime_frequentadores

  # Sprint 19 (task 19.1, UC-08): intervenções (batida manual/errata) que
  # afetaram este usuário, e as que este usuário registrou como responsável
  # (admin) — mesmo model, dois papéis diferentes.
  has_many :intervencoes_frequencia, class_name: "IntervencaoFrequencia", dependent: :restrict_with_exception
  has_many :intervencoes_frequencia_como_responsavel, class_name: "IntervencaoFrequencia",
                                                        foreign_key: :responsavel_id,
                                                        inverse_of: :responsavel,
                                                        dependent: :restrict_with_exception

  # Sprint 19 (task 19.3, UC-10): intervenções que este usuário resolveu
  # (deferiu/indeferiu) como gestor — papel distinto de "responsavel"
  # (quem criou o pedido; pode ser nulo quando é o sistema que cria).
  has_many :intervencoes_frequencia_como_resolvedor, class_name: "IntervencaoFrequencia",
                                                       foreign_key: :resolvido_por_id,
                                                       inverse_of: :resolvido_por,
                                                       dependent: :restrict_with_exception

  # Vínculo do Frequentador local (login da estação) com o espelho de dados
  # do Pessoas (Sprint 10) — via CPF, não FK numérica. optional porque
  # frequentadores cadastrados manualmente (sem cpf) continuam válidos.
  belongs_to :frequentador_cache, foreign_key: :cpf, primary_key: :cpf, inverse_of: :user, optional: true

  before_validation :generate_username, on: :create

  validates :nome_completo, presence: true
  validates :username, presence: true, uniqueness: { case_sensitive: false }
  validates :status, presence: true
  validates :password, length: { minimum: 6 }, if: -> { new_record? || !password.nil? }
  validates :cpf, uniqueness: true, format: { with: /\A\d{11}\z/ }, allow_nil: true

  scope :ativos, -> { where(status: 1) }
  scope :com_digitais, -> { where.not(digitais_hash: nil) }

  # Task 21.5 (Sprint 21): usuários vindos do Pessoas (têm `cpf`) autenticam
  # com a senha REAL do pessoas2, lendo o hash bcrypt (`encrypted_password`,
  # Devise `:database_authenticatable`) direto do banco via `Pessoas::User`
  # — sem depender da Sticapi/Devise estar de pé. Contas sem `cpf`
  # (admins/cadastros manuais) continuam usando `has_secure_password`
  # local, exatamente como antes (`super`).
  #
  # Decisão: se o usuário tem `cpf` mas não existe (mais) um registro
  # correspondente em `Pessoas::User` (ex.: conta removida no pessoas2),
  # o login falha (retorna `false`) — não cai em fallback pra senha local,
  # porque `password_digest` de uma conta com `cpf` não é mantido/atualizado
  # nesse fluxo (ver validação `password` abaixo, que só exige presença/
  # tamanho quando o valor é setado) e um fallback silencioso seria uma
  # porta de autenticação órfã, não documentada, e potencialmente com senha
  # desatualizada ou nunca definida.
  def authenticate(unencrypted_password)
    return super if cpf.blank?

    pessoas_user = Pessoas::User.buscar_por_cpf(cpf)
    return false if pessoas_user.blank?

    BCrypt::Password.new(pessoas_user.encrypted_password) == unencrypted_password ? self : false
  end

  # Sprint 23, task 23.3 — coexistência has_secure_password × Devise
  # (DatabaseAuthenticatable). Conflitos resolvidos e documentados:
  #
  # 1) `password=`: o `has_secure_password` (chamado ANTES do `devise`)
  #    gravava em `password_digest`; o módulo Devise (incluído DEPOIS, vence
  #    na cadeia de ancestrais) grava em `encrypted_password`. Se o writer do
  #    Devise vencesse, `User.create!(password:)` deixaria `password_digest`
  #    vazio e quebraria a auth local (`authenticate` → `super` →
  #    `password_digest`), que ainda é a fonte de verdade
  #    (Admin::SessionsController). Solução: writer próprio gravando AMBAS as
  #    colunas (mesma senha, ambos bcrypt) — `password_digest` para a
  #    transição atual, `encrypted_password` para o Devise futuro (23.6+).
  #
  # 2) `password_digest` reader/writer: o Devise define
  #    `password_digest(password)` (com argumento, para gerar hash) — isso
  #    faz o ActiveRecord considerar o nome "já implementado" e não gerar o
  #    accessor da coluna. Restauramos o reader (0 args) e o writer
  #    explícitos sobre a coluna real — sem isso `has_secure_password
  #    #authenticate` (via `super`, chama `public_send(:password_digest)`)
  #    quebraria com ArgumentError.
  #
  # 3) `validatable` + email nullable (decisão 23.1): usuários do Pessoas2
  #    podem não ter `email`; o `validatable` exige presença de email por
  #    padrão (`email_required?` → true). Durante a transição NENHUM usuário
  #    tem email obrigatório (coluna nullable; fixtures/seeds atuais sem
  #    email; sem tela de cadastro) — `email_required?` retorna false. A
  #    decisão de exigir email para admins locais (sem `cpf`) fica para as
  #    tasks 23.8/23.9, quando a regra pode virar `cpf.blank?` (receita
  #    sugerida na task). Unicidade/formato do email usam
  #    `devise_will_save_change_to_email?` (dirty tracking) — inócuos
  #    enquanto email não for setado.
  def password=(unencrypted_password)
    if unencrypted_password.nil?
      # `clean_up_passwords` (Devise) usa nil para limpar SÓ o atributo
      # virtual `password` — as colunas (digest) NÃO são apagadas aqui.
      @password = nil
      return
    end

    return if unencrypted_password.empty?

    @password = unencrypted_password
    self.password_digest = BCrypt::Password.create(unencrypted_password)
    self.encrypted_password = Devise::Encryptor.digest(self.class, unencrypted_password)
  end

  def password_digest
    self[:password_digest]
  end

  def password_digest=(value)
    self[:password_digest] = value
  end

  # Task 23.6 — roteamento do Devise por `username` (não `email`).
  # `config.authentication_keys = [:username]` no initializer; o Warden chama
  # este método na autenticação. Busca por username com o mesmo
  # case-insensitive do Devise.
  def self.find_for_database_authentication(warden_conditions)
    conditions = warden_conditions.dup
    username = conditions.delete(:username)
    where(conditions).find_by("lower(username) = ?", username.to_s.downcase)
  end

  # Task 23.6 — sobrescreve `valid_password?` do Devise para rotear a senha
  # dos usuários com `cpf` para o Pessoas2 (fonte de verdade da senha),
  # mantendo a validação local (encrypted_password) para os demais.
  def valid_password?(password)
    if cpf.present?
      pessoas_user = Pessoas::User.buscar_por_cpf(cpf)
      return false if pessoas_user.blank?

      BCrypt::Password.new(pessoas_user.encrypted_password) == password
    else
      super
    end
  end

  # Task 23.6 — usuário inativo (status != 1) não autentica pelo Devise.
  # Bloqueio antes de validar a senha (evita timing oracle de conta inativa
  # com senha válida) — mesmo contrato do Admin::SessionsController anterior.
  def active_for_authentication?
    super && status == 1
  end

  def email_required?
    false
  end

  private

  def generate_username
    return if username.present?

    parts = I18n.transliterate(nome_completo.to_s)
          .downcase
          .gsub(/[^a-z0-9\s]/, "")
          .split
          .compact

    return if parts.empty?

    base = parts.size == 1 ? parts.first : "#{parts.first}.#{parts.last}"

    return if base.blank?

    candidate = base
    suffix = 1
    while User.exists?(username: candidate)
      suffix += 1
      candidate = "#{base}.#{suffix}"
    end

    self.username = candidate
  end
end
