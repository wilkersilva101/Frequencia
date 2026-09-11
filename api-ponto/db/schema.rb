# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_09_10_185008) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "afastamento_caches", force: :cascade do |t|
    t.integer "afastamento_id_pessoas"
    t.string "cpf"
    t.string "tipo"
    t.string "cargo"
    t.string "lotacao"
    t.datetime "momento_inicial"
    t.datetime "momento_final"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["afastamento_id_pessoas"], name: "index_afastamento_caches_on_afastamento_id_pessoas", unique: true
    t.index ["cpf"], name: "index_afastamento_caches_on_cpf"
  end

  create_table "calculo_diarios", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.date "data", null: false
    t.integer "normal_segundos"
    t.integer "excepcional_segundos"
    t.integer "total_segundos"
    t.integer "meta_segundos"
    t.boolean "aberto", default: false, null: false
    t.boolean "ausencia", default: false, null: false
    t.boolean "falta", default: false, null: false
    t.boolean "falta_a_descontar", default: false, null: false
    t.boolean "falta_compensada", default: false, null: false
    t.boolean "descontado_em_folha", default: false, null: false
    t.string "informacao"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "data"], name: "index_calculo_diarios_on_user_id_and_data", unique: true
    t.index ["user_id"], name: "index_calculo_diarios_on_user_id"
  end

  create_table "estacoes_ponto", force: :cascade do |t|
    t.string "descricao", null: false
    t.string "versao"
    t.datetime "ultimo_contato"
    t.string "vnc"
    t.string "anydesk"
    t.string "teamviewer"
    t.text "observacao"
    t.string "cod_ativacao", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cod_ativacao"], name: "index_estacoes_ponto_on_cod_ativacao", unique: true
  end

  create_table "exception_tracks", force: :cascade do |t|
    t.string "title"
    t.text "body"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "frequentador_caches", force: :cascade do |t|
    t.string "cpf"
    t.integer "pessoa_id_pessoas"
    t.string "nome"
    t.string "orgao"
    t.string "vinculo"
    t.datetime "sincronizado_em"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cpf"], name: "index_frequentador_caches_on_cpf", unique: true
  end

  create_table "gestor_individual_gerenciados", force: :cascade do |t|
    t.bigint "gestor_individual_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gestor_individual_id"], name: "index_gestor_individual_gerenciados_on_gestor_individual_id"
    t.index ["user_id"], name: "index_gestor_individual_gerenciados_on_user_id"
  end

  create_table "gestores_individuais", force: :cascade do |t|
    t.string "nome"
    t.string "orgao"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "regime_categorias", force: :cascade do |t|
    t.bigint "regime_id", null: false
    t.string "categoria"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["regime_id"], name: "index_regime_categorias_on_regime_id"
  end

  create_table "regime_frequentadores", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "regime_id", null: false
    t.string "tipo"
    t.datetime "momento_inicial"
    t.datetime "momento_final"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["regime_id"], name: "index_regime_frequentadores_on_regime_id"
    t.index ["user_id"], name: "index_regime_frequentadores_on_user_id"
  end

  create_table "regimes", force: :cascade do |t|
    t.string "nome"
    t.string "modalidade"
    t.string "resumo"
    t.string "meta_semanal"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "global", default: false, null: false
    t.date "inicio"
    t.boolean "pode_faltar", default: false, null: false
    t.boolean "liberado_limitacao_inicio_hora_extra", default: false, null: false
    t.boolean "permitido_acumular_horas", default: true, null: false
    t.boolean "permitido_compensar_falta", default: true, null: false
    t.boolean "permitido_contabilizar_horas_mesmo_com_meta_zero", default: true, null: false
    t.integer "maximo_banco_horas_diario_em_segundos", default: 7200, null: false
    t.integer "limite_credito", default: 0, null: false
    t.integer "limite_debito", default: 0, null: false
    t.integer "percentual_carga_minima", default: 0, null: false
    t.integer "limite_dias_carga_minima", default: 0, null: false
    t.jsonb "expediente", default: [], null: false
    t.bigint "anterior_id"
    t.bigint "padrao_id"
    t.index ["anterior_id"], name: "index_regimes_on_anterior_id"
    t.index ["padrao_id"], name: "index_regimes_on_padrao_id"
  end

  create_table "time_records", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "raw_data"
    t.datetime "punched_at"
    t.string "authentication_mode"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "punch_type"
    t.boolean "punch_type_explicit", default: false, null: false
    t.bigint "estacao_ponto_id"
    t.index ["estacao_ponto_id"], name: "index_time_records_on_estacao_ponto_id"
    t.index ["punched_at"], name: "index_time_records_on_punched_at"
    t.index ["user_id"], name: "index_time_records_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "nome_completo", null: false
    t.string "username", null: false
    t.string "password_digest", null: false
    t.integer "status", default: 1, null: false
    t.text "digitais_hash"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "admin", default: false, null: false
    t.string "cpf"
    t.index ["admin"], name: "index_users_on_admin"
    t.index ["cpf"], name: "index_users_on_cpf", unique: true
    t.index ["status"], name: "index_users_on_status"
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "versoes", force: :cascade do |t|
    t.string "numero", null: false
    t.text "novidades"
    t.string "link"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "calculo_diarios", "users"
  add_foreign_key "gestor_individual_gerenciados", "gestores_individuais", column: "gestor_individual_id"
  add_foreign_key "gestor_individual_gerenciados", "users"
  add_foreign_key "regime_categorias", "regimes"
  add_foreign_key "regime_frequentadores", "regimes"
  add_foreign_key "regime_frequentadores", "users"
  add_foreign_key "regimes", "regimes", column: "anterior_id"
  add_foreign_key "regimes", "regimes", column: "padrao_id"
  add_foreign_key "time_records", "estacoes_ponto", column: "estacao_ponto_id"
  add_foreign_key "time_records", "users"
end
