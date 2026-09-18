class CreateRetificadorBancoHoras < ActiveRecord::Migration[8.0]
  # Sprint 18 (task 18.2) — schema do agregado `RetificadorBancoHoras`,
  # portado de `RetificadorDeBancoHoras.java` (bean) + `TipoRetificadorEnum.java`
  # (Intranet legada). Retificador é o mecanismo de correção manual do banco
  # de horas de um usuário num mês/ano específico — crédito ou débito de
  # segundos, sem precisar vincular a um `CalculoDiario` (paridade com o
  # comentário de topo do bean legado: DESCONTO_EM_FOLHA não precisa ficar
  # vinculado a um CalculoDiario).
  #
  # Campos do bean legado deliberadamente NÃO portados aqui:
  # - `calculoDiario` (referência opcional a um CalculoDiario específico):
  #   confirmado por grep que nenhum DAO/service do legado realmente usa
  #   esse vínculo pra nada (só existe `findByCalculoDiario`, sem chamador);
  #   fora de escopo, sem uso real a portar.
  def change
    create_table :retificador_banco_horas do |t|
      t.references :user, null: false, foreign_key: true
      # Quem registrou o retificador (usuário admin). Opcional — nem toda
      # via de criação (ex: seed/console/task administrativa futura) tem
      # necessariamente um usuário logado amarrado; ver nota no model.
      t.references :responsavel, null: true, foreign_key: { to_table: :users }

      t.integer :ano, null: false
      t.integer :mes, null: false, comment: "1..12"

      t.string :tipo, null: false
      t.integer :segundos_a_retificar, null: false

      t.text :observacao
      t.text :informacao

      # Soft-delete (paridade com `excluido` do bean legado) — nunca
      # `destroy` real, pra preservar histórico/auditoria do banco de horas.
      t.boolean :excluido, null: false, default: false

      t.timestamps
    end

    add_index :retificador_banco_horas, %i[user_id ano mes], name: "index_retificador_banco_horas_on_user_ano_mes"
  end
end
