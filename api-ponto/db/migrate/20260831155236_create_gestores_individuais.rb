class CreateGestoresIndividuais < ActiveRecord::Migration[8.0]
  def change
    create_table :gestores_individuais do |t|
      t.string :nome
      t.string :orgao

      t.timestamps
    end
  end
end
