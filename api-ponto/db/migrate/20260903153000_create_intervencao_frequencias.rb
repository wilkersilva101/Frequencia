class CreateIntervencaoFrequencias < ActiveRecord::Migration[8.0]
  def change
    create_table :intervencao_frequencias do |t|
      # Frequentador afetado pelo registro manual/errata.
      t.references :user, null: false, foreign_key: true
      # Admin que registrou/solicitou a intervenção.
      t.references :responsavel, null: false, foreign_key: { to_table: :users }

      # "batida_manual" (Sprint 19, task 19.1 — UC-08): admin insere um
      # TimeRecord novo na hora. "errata": fica pendente até resolução
      # futura (Sprint 19, tasks seguintes). Só esses 2 valores nesta task
      # — não replica os N tipos de PreVinculadoAcaoEnum do legado.
      t.string :tipo, null: false

      t.text :justificativa, null: false

      # Data/hora do registro sendo inserido/corrigido (não confundir com
      # created_at, que é quando a intervenção foi solicitada).
      t.datetime :momento, null: false

      t.string :punch_type

      # Presente só quando já existe um TimeRecord real (batida manual).
      # Ausente/pendente pra errata, até a resolução (task futura) criar o
      # TimeRecord ou apenas manter o histórico.
      t.references :time_record, null: true, foreign_key: true

      # "registrado" (batida manual, efetiva na hora) ou "pendente"
      # (errata, aguardando resolução — sem workflow de aprovação/rejeição
      # multi-estado ainda, isso é escopo das tasks 19.2-19.5).
      t.string :status, null: false, default: "pendente"

      t.timestamps
    end

    add_index :intervencao_frequencias, :tipo
    add_index :intervencao_frequencias, :status
  end
end
