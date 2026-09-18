class CreateEstacoesPonto < ActiveRecord::Migration[8.0]
  def change
    create_table :estacoes_ponto do |t|
      t.string :descricao, null: false
      t.string :versao
      t.datetime :ultimo_contato
      t.string :vnc
      t.string :anydesk
      t.string :teamviewer
      t.text :observacao
      t.string :cod_ativacao, null: false

      t.timestamps
    end
    add_index :estacoes_ponto, :cod_ativacao, unique: true
  end
end
