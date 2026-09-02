class CalculoDiario < ApplicationRecord
  # Sprint 16 (task 16.1) — membro interno do agregado `Dia` (AG-3),
  # equivalente a `CalculoDiario.java` (Intranet legada, tabela
  # `presenca_calculodiario`). Guarda o resultado do cálculo diário
  # (horas trabalhadas, meta, falta, banco de horas etc.).
  #
  # ESCOPO ESTRITO desta task: só estrutura. Nenhuma lógica de cálculo foi
  # portada ainda — todos os campos numéricos/flags de resultado ficam
  # `nil`/`false` (default da coluna) até as tasks 16.2/16.3 (motor de
  # cálculo v2 + orquestração por modalidade). Ver SPRINT-PLAN.md.
  belongs_to :user

  validates :data, presence: true
  validates :user_id, uniqueness: { scope: :data }
end
