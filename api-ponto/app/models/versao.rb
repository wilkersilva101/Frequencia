class Versao < ApplicationRecord
  # Cadastro local simples das versões da EstaçãoPonto/app (Sprint 14,
  # Task 14.4) — Fase A: apenas listagem/registro manual de release notes
  # e link de download, sem nenhuma integração externa (não depende de
  # Sticapi/Pessoas, ao contrário da maioria dos outros models do
  # Frequencia).
  validates :numero, presence: true
end
