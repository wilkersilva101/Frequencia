class CreateRelatorioFrequenciaFinais < ActiveRecord::Migration[8.0]
  def change
    create_table :relatorio_frequencia_finais do |t|
      t.integer :mes, null: false
      t.integer :ano, null: false
      t.datetime :data_geracao, null: false
      t.datetime :data_alteracao

      t.timestamps
    end

    add_index :relatorio_frequencia_finais, %i[ano mes], unique: true, name: "index_relatorio_frequencia_finais_on_ano_mes"
  end
end
