class AddLegacyFieldsToEstacoesPonto < ActiveRecord::Migration[8.0]
  # Replica campos de estrutura de dados presentes no legado Intranet
  # (`presenca_estacaoponto`) e ainda ausentes em `estacoes_ponto` (pedido
  # direto do usuário, 2026-09-02 — ver SPRINT-PLAN.md). Não replicamos
  # `responsavel_id` (FK para Usuario do Intranet, sem equivalente aqui) nem
  # `ativo_bkp` (campo de backup/migração do legado, sem valor fora dele).
  def change
    add_column :estacoes_ponto, :codigo_unico_maquina, :string
    add_column :estacoes_ponto, :momento_inicio, :date
    add_column :estacoes_ponto, :momento_fim, :date
    add_column :estacoes_ponto, :liberado_batida_manual, :boolean, null: false, default: false
    add_column :estacoes_ponto, :ativo, :boolean, null: false, default: true
  end
end
