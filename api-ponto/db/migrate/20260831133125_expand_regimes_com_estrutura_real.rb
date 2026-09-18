class ExpandRegimesComEstruturaReal < ActiveRecord::Migration[8.0]
  # Traz os campos reais do Regime da Intranet legada (Regime.java,
  # ConfiguracaoFrequencia.java — @Embeddable), já que a Intranet será
  # descomissionada e o Frequencia precisa ser autossuficiente com as
  # mesmas regras de negócio. Ver docs/01-inventario/02-regime-jornada.md.
  #
  # Escopo desta migration: só estrutura/schema (SPRINT-PLAN.md, decisão
  # 2026-08-31) — o motor de cálculo que usa esses campos (metaSemanal,
  # periodosSemana, banco de horas) fica para a Fase B (Sprints 16+).
  def change
    change_table :regimes, bulk: true do |t|
      t.boolean :global, default: false, null: false
      t.date :inicio

      # ConfiguracaoFrequencia (era @Embeddable no legado — aqui, colunas
      # diretas na própria tabela, mesma abordagem "colapsada" do legado).
      t.boolean :pode_faltar, default: false, null: false
      t.boolean :liberado_limitacao_inicio_hora_extra, default: false, null: false
      t.boolean :permitido_acumular_horas, default: true, null: false
      t.boolean :permitido_compensar_falta, default: true, null: false
      t.boolean :permitido_contabilizar_horas_mesmo_com_meta_zero, default: true, null: false
      t.integer :maximo_banco_horas_diario_em_segundos, default: 7200, null: false
      t.integer :limite_credito, default: 0, null: false
      t.integer :limite_debito, default: 0, null: false
      t.integer :percentual_carga_minima, default: 0, null: false
      t.integer :limite_dias_carga_minima, default: 0, null: false

      # Expediente: no legado é uma List<Horario> serializada em JSON
      # (hashExpediente, @Lob) — aqui já nasce jsonb nativo do Postgres,
      # sem precisar de (de)serialização manual. Formato de cada item:
      # { "inicio", "fim", "limite_inicio", "limite_fim", "dias" }.
      t.jsonb :expediente, default: [], null: false

      # Versionamento/herança do legado (Regime.anterior / Regime.padrao).
      # Sem lógica de clonagem/corte de período ainda (RegimentoServices,
      # Fase B) — só a referência.
      t.references :anterior, foreign_key: { to_table: :regimes }
      t.references :padrao, foreign_key: { to_table: :regimes }
    end
  end
end
