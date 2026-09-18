class CreateAfastamentoCaches < ActiveRecord::Migration[8.0]
  def change
    create_table :afastamento_caches do |t|
      t.integer :afastamento_id_pessoas
      t.string :cpf
      t.string :tipo
      t.string :cargo
      t.string :lotacao
      t.datetime :momento_inicial
      t.datetime :momento_final
      t.string :status

      t.timestamps
    end

    add_index :afastamento_caches, :afastamento_id_pessoas, unique: true
    add_index :afastamento_caches, :cpf
  end
end
