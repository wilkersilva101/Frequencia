class CreateFrequentadorCaches < ActiveRecord::Migration[8.0]
  def change
    create_table :frequentador_caches do |t|
      t.string :cpf
      t.integer :pessoa_id_pessoas
      t.string :nome
      t.string :orgao
      t.string :vinculo
      t.datetime :sincronizado_em

      t.timestamps
    end
    add_index :frequentador_caches, :cpf, unique: true
  end
end
