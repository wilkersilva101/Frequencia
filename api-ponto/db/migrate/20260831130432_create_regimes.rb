class CreateRegimes < ActiveRecord::Migration[8.0]
  def change
    create_table :regimes do |t|
      t.string :categoria
      t.string :nome
      t.string :modalidade
      t.string :resumo
      t.string :meta_semanal

      t.timestamps
    end
  end
end
