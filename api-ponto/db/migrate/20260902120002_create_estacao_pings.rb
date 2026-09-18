class CreateEstacaoPings < ActiveRecord::Migration[8.0]
  # Estrutura equivalente à tabela legado `presenca_estacaoponto_ping`
  # (Intranet) — histórico completo de heartbeats de cada EstaçãoPonto
  # (diferente de `estacoes_ponto.ultimo_contato`, que guarda só o último).
  # Nasce vazia por decisão do usuário (2026-09-02): os ~46,7M registros
  # históricos do legado não são migrados, só a estrutura.
  def change
    create_table :estacao_pings do |t|
      t.string :ip
      t.datetime :momento
      t.string :versao
      t.references :estacao_ponto, null: false, foreign_key: { to_table: :estacoes_ponto }

      t.timestamps
    end
  end
end
