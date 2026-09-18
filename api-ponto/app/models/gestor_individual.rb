class GestorIndividual < ApplicationRecord
  # Corresponde ao legado `presenca_gestorindividual` — no legado é uma
  # tabela de ligação (vinculado_id do gestor, no domínio de Pessoas, →
  # frequentador_id do gerido, local), com o gestor identificado por seu
  # vínculo em Pessoas, não necessariamente um login local da estação.
  #
  # Sticapi expõe o equivalente real via
  # `SticapiClient::Intranet.gestores_individuais` (campos: id,
  # data_criacao, data_exclusao, observacao, id_vinculo_gestor,
  # matricula_gestor, id_vinculo_gerido, matricula_gerido) — importar isso
  # exigiria resolução de matrícula→CPF (mesmo problema da Sprint 10B) e
  # fica para uma sprint futura. Por ora (Fase A, "popular o front"), é
  # cadastro local simples — mesmo espírito de `Regime`/`EstacaoPonto`
  # antes de qualquer importação real.
  #
  # `self.table_name` explícito: "gestor individual" pluraliza em
  # português como "gestores individuais" (as duas palavras concordam),
  # diferente do que o Rails infere automaticamente a partir do nome da
  # classe — mesmo caso do `EstacaoPonto`.
  self.table_name = "gestores_individuais"

  has_many :gestor_individual_gerenciados, dependent: :destroy
  has_many :gerenciados, through: :gestor_individual_gerenciados, source: :user

  validates :nome, presence: true
end
