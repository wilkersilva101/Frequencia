class CreateValorRetroativos < ActiveRecord::Migration[8.0]
  # Sprint 18 (task 18.3) — schema do agregado `ValorRetroativo`, portado de
  # `ValorRetroativo.java` (bean) + `ValorRetroativoDao.java` (Intranet
  # legada). Correção retroativa de folha aplicada a um usuário num mês/ano
  # específico (`processo` = referência administrativa/judicial que originou
  # o valor, `numero_hora` = quantidade de horas retroativas).
  #
  # `belongs_to :user` sem restrição de unicidade (nem em `user_id` isolado,
  # nem em `user_id+ano+mes`): o bean legado usa `@OneToOne` entre
  # `Frequentador` e `ValorRetroativo`, o que é estranho pra um valor
  # mensal — um usuário só poderia ter UM valor retroativo em toda a vida
  # no legado. Confirmado no DAO (`ValorRetroativoDao#getByMesAno`) que o
  # próprio código legado já lida com `List<ValorRetroativo>` de tamanho > 1
  # pro mesmo mês/ano (é exatamente o cenário do bug DUV-011, ver
  # `ValorRetroativo#soma_do_mes` no model) — ou seja, na prática o legado já
  # não respeitava a própria restrição `@OneToOne` (provavelmente
  # modelagem ruim do bean, não uma limitação de negócio real). Aqui,
  # `belongs_to :user` simples permite múltiplos valores retroativos por
  # usuário ao longo do tempo, inclusive vários no mesmo mês/ano — que é o
  # cenário que o teste do bug precisa exercitar.
  def change
    create_table :valor_retroativos do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :ano, null: false
      t.integer :mes, null: false, comment: "1..12"
      t.datetime :data_geracao, null: false
      t.string :processo
      t.integer :numero_hora, null: false

      t.timestamps
    end

    add_index :valor_retroativos, %i[user_id ano mes], name: "index_valor_retroativos_on_user_ano_mes"
  end
end
