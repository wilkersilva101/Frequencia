class CreateRegistroEstacaoPontos < ActiveRecord::Migration[8.0]
  # Estrutura equivalente à tabela legado `presenca_registroestacaoponto`
  # (Intranet) — log de cada sincronização recebida de uma EstaçãoPonto.
  # Nasce vazia por decisão do usuário (2026-09-02): os ~4,5M registros
  # históricos do legado não são migrados, só a estrutura.
  def change
    create_table :registro_estacao_pontos do |t|
      t.text :arquivo_criptografado
      t.datetime :momento_processamento
      t.datetime :momento_sinc
      t.boolean :processado, null: false, default: false
      t.references :estacao_ponto, null: false, foreign_key: { to_table: :estacoes_ponto }
      t.text :ip

      t.timestamps
    end
  end
end
