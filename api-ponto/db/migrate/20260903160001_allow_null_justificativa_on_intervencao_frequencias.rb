# Sprint 19, task 19.2 (UC-09) — `reconsiderar` no legado
# (`RegistroFrequencia#reconsiderar`, linhas 340-358) NÃO recebe
# `intervencaoObs`/justificativa como parâmetro (diferente de
# `desconsiderar`, que exige). A coluna `justificativa` foi criada
# `null: false` na task 19.1 (só existiam tipos que sempre a exigiam
# nessa época); agora que "reconsideracao_ponto" não a exige, a coluna
# precisa aceitar NULL. A obrigatoriedade continua garantida a nível de
# aplicação em `IntervencaoFrequencia` (validação condicional por `tipo`).
class AllowNullJustificativaOnIntervencaoFrequencias < ActiveRecord::Migration[8.0]
  def change
    change_column_null :intervencao_frequencias, :justificativa, true
  end
end
