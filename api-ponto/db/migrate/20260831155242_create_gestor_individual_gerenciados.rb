class CreateGestorIndividualGerenciados < ActiveRecord::Migration[8.0]
  # `to_table: :gestores_individuais` explícito: a tabela real do
  # GestorIndividual usa o plural em português correto ("gestores
  # individuais"), diferente do que o Rails infere automaticamente a
  # partir do model (`self.table_name`, ver app/models/gestor_individual.rb)
  # — mesmo caso do `EstacaoPonto`/`estacoes_ponto` já usado no projeto.
  def change
    create_table :gestor_individual_gerenciados do |t|
      t.references :gestor_individual, null: false, foreign_key: { to_table: :gestores_individuais }
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
