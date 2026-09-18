class CreateRegistroMensalFrequencias < ActiveRecord::Migration[8.0]
  # Sprint 17 (task 17.1) — schema do agregado `RegistroMensalFrequencia`
  # (AG-4), consolidação mensal dos `CalculoDiario` (AG-3) de um usuário,
  # espelhando os campos reais de `presenca_registromensalfrequencia`
  # (RegistroMensalFrequencia.java, Intranet legada).
  #
  # Campos NÃO portados (existem no bean legado mas sem uso real ainda no
  # Frequencia, ou pertencem a escopo de tasks futuras — ver nota da task
  # 17.1 no SPRINT-PLAN.md):
  # - `trabalhadoExcepcional`: `CalculoDiario#excepcional_segundos` é
  #   sempre 0 até hoje (sem expediente excepcional implementado) — não
  #   faz sentido persistir um agregado que nunca sai de 0.
  # - `tempoAusenteDeFalta`, `ausentes`, `faltasACompensar`,
  #   `faltasADescontar`, `creditoADevolver`: campos auxiliares do
  #   algoritmo de desconto em folha (fora do escopo desta task).
  # - `momentoUltimoCalculo`: paridade de auditoria, não usado pelo
  #   algoritmo de cálculo em si; pode ser adicionado depois se necessário.
  #
  # `retificado` fica sempre 0 nesta task — `RetificadorDeBancoHoras` não
  # existe no Frequencia ainda (task futura, Sprint 18 task 18.2).
  # `finalizado` só tem a coluna (default false) — o mecanismo real de
  # congelamento/trava de recálculo é a task 17.2, não implementado aqui.
  def change
    create_table :registro_mensal_frequencias do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :ano, null: false
      t.integer :mes, null: false
      t.date :data_inicio, null: false
      t.date :data_fim, null: false

      # --- Metas (em segundos) e contagem de dias com meta > 0 ---
      # `meta_mensal`/`meta_mensal_dias`: soma cega de todos os dias do
      # mês, inclusive futuros. `meta_atual`/`meta_atual_dias`: só os dias
      # já "computáveis" até o momento do cálculo (ver
      # ConsolidacaoMensalService#pode_calcular?).
      t.integer :meta_mensal, null: false, default: 0
      t.integer :meta_mensal_dias, null: false, default: 0
      t.integer :meta_atual, null: false, default: 0
      t.integer :meta_atual_dias, null: false, default: 0

      # --- Trabalhado (em segundos) e dias com total > 0 ---
      t.integer :trabalhado, null: false, default: 0
      t.integer :trabalhado_normal, null: false, default: 0
      t.integer :trabalhado_dias, null: false, default: 0

      t.integer :dias_em_aberto, null: false, default: 0
      t.integer :faltas, null: false, default: 0

      # --- Saldo / banco de horas (em segundos, podem ser negativos) ---
      t.integer :saldo_liquido, null: false, default: 0
      t.integer :retido, null: false, default: 0
      t.integer :acumulado, null: false, default: 0
      # Sempre 0 nesta task — ver nota acima (RetificadorDeBancoHoras).
      t.integer :retificado, null: false, default: 0

      # Congelamento real (impedir recálculo) é a task 17.2 — só a coluna
      # existe aqui, sempre `false` até lá.
      t.boolean :finalizado, null: false, default: false

      t.timestamps
    end

    add_index :registro_mensal_frequencias, %i[user_id ano mes], unique: true, name: "index_registro_mensal_frequencias_on_user_ano_mes"
  end
end
