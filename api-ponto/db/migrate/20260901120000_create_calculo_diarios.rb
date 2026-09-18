class CreateCalculoDiarios < ActiveRecord::Migration[8.0]
  # Sprint 16 (task 16.1) — schema do agregado interno `CalculoDiario`
  # (membro do futuro AG-3 `Dia`), espelhando os campos reais de
  # `presenca_calculodiario` (CalculoDiario.java, Intranet legada).
  #
  # ESCOPO ESTRITO desta migration: só estrutura. Nenhuma linha de código
  # desta sprint escreve nestes campos — ficam `nil`/`false` (default) até
  # o motor de cálculo ser portado nas tasks 16.2/16.3. Ver nota da task
  # 16.1 no SPRINT-PLAN.md para a lista completa do que ainda falta portar
  # de `Regime.java` (metaSemanal, periodosSemana etc.).
  #
  # Diferente do legado: aqui a FK é direto pra `users` (Frequencia não tem
  # `Frequentador` como entidade própria — `User` já cumpre esse papel,
  # mesmo padrão usado por `RegimeFrequentador`/`TimeRecord`). Não há coluna
  # para `registro_mensal_id` (AG-4, `RegistroMensalFrequencia`) ainda —
  # isso só existe a partir da Sprint 17; será adicionada lá quando o
  # agregado mensal for modelado, para não antecipar estrutura sem uso.
  def change
    create_table :calculo_diarios do |t|
      t.references :user, null: false, foreign_key: true
      t.date :data, null: false

      # --- Totais em segundos (equivalentes a normal/excepcional/total/meta
      # do legado, que guardavam em milissegundos/inteiro cru). Nomeados
      # em segundos aqui para consistência com o resto do projeto
      # (ver comentário de `expediente`/`configuracao` em Regime). Todos
      # nullable — não populados nesta task. ---
      t.integer :normal_segundos
      t.integer :excepcional_segundos
      t.integer :total_segundos
      t.integer :meta_segundos

      # --- Flags de estado do dia (equivalentes 1:1 ao legado). Default
      # false (mesmo default dos construtores de CalculoDiario.java) —
      # ainda não escritas por nenhuma lógica nesta task. ---
      t.boolean :aberto, null: false, default: false
      t.boolean :ausencia, null: false, default: false
      t.boolean :falta, null: false, default: false
      t.boolean :falta_a_descontar, null: false, default: false
      t.boolean :falta_compensada, null: false, default: false
      t.boolean :descontado_em_folha, null: false, default: false

      # Texto livre (equivalente a `informacao` do legado) — usado pelo
      # motor de cálculo futuro para anotar observações do dia.
      t.string :informacao

      t.timestamps
    end

    add_index :calculo_diarios, %i[user_id data], unique: true
  end
end
