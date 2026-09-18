class CreateVersoes < ActiveRecord::Migration[8.0]
  def change
    create_table :versoes do |t|
      t.string :numero, null: false
      t.text :novidades
      t.string :link

      t.timestamps
    end
  end
end
