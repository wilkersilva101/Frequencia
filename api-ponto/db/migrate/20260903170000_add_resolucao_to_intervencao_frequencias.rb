# Sprint 19, task 19.3 (UC-10) — "autorizar horas extras" é o primeiro tipo
# de `IntervencaoFrequencia` em que o PEDIDO nasce sem um `responsavel`
# humano: é o próprio sistema quem abre a solicitação pendente quando o
# cálculo do dia indicaria acúmulo de horas extras (equivalente a
# `preencheIntervencaoLimitado`, que não recebe `Servidor responsavel` —
# diferente de `desconsiderar!`/`RegistroManualFrequenciaService`, sempre
# acionados por uma pessoa). `responsavel_id` foi criado `null: false` na
# task 19.1 (só existiam tipos com responsável humano na criação); agora
# precisa aceitar NULL para "acumulo_horas_extras".
#
# A RESOLUÇÃO (deferir!/indeferir!) é sempre feita por uma pessoa (um
# gestor), mas essa pessoa não é necessariamente quem criou o pedido —
# no caso de "acumulo_horas_extras" não existe "quem criou" (é o
# sistema). Por isso a resolução ganha um campo próprio,
# `resolvido_por_id`, em vez de reaproveitar `responsavel_id`
# (que descreve "quem é responsável pela criação/execução da ação
# registrada", não "quem decidiu um pedido pendente"). Nullable porque só
# é preenchido quando a intervenção é de fato resolvida (deferida ou
# indeferida) — fica NULL enquanto `status: "pendente"`.
class AddResolucaoToIntervencaoFrequencias < ActiveRecord::Migration[8.0]
  def change
    change_column_null :intervencao_frequencias, :responsavel_id, true

    add_reference :intervencao_frequencias, :resolvido_por, foreign_key: { to_table: :users }, null: true
  end
end
