class CreateRegimeFrequentadores < ActiveRecord::Migration[8.0]
  def change
    create_table :regime_frequentadores do |t|
      t.references :user, null: false, foreign_key: true
      t.references :regime, null: false, foreign_key: true
      t.string :tipo
      t.datetime :momento_inicial
      t.datetime :momento_final

      t.timestamps
    end
  end
end
