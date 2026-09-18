class CreateRelatorioFrequentadores < ActiveRecord::Migration[8.0]
  def change
    create_table :relatorio_frequentadores do |t|
      t.references :user, null: false, foreign_key: true
      t.references :relatorio_frequencia_final, null: false, foreign_key: { to_table: :relatorio_frequencia_finais }
      t.integer :saldo_bruto, default: 0, null: false
      t.integer :valor_retroativo, default: 0, null: false
      t.integer :resultado, default: 0, null: false

      t.timestamps
    end
  end
end
