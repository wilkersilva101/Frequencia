class CreateRegimeCategorias < ActiveRecord::Migration[8.0]
  def change
    create_table :regime_categorias do |t|
      t.references :regime, null: false, foreign_key: true
      t.string :categoria

      t.timestamps
    end
  end
end
