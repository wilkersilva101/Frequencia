# Sprint 19, task 19.2 (UC-09) — campos portados de `RegistroFrequencia`
# (intranet/src/modules/presenca/beans/RegistroFrequencia.java), onde
# `ressalva` já existe como boolean próprio do registro (linha ~44:
# "Verdadeiro: ponto batido em estação diferente do local de trabalho ou
# tem alguma pendência") e o estado "desconsiderado" é hoje representado
# via `horario = TipoRegistroFrequenciaEnum.Horario.DESCONSIDERADO`
# (enum de vários valores). Aqui simplificamos para um boolean dedicado
# (`desconsiderado`) em vez de portar o enum `Horario` inteiro — esta task
# só precisa distinguir "conta no cálculo" vs. "não conta", não os demais
# valores do enum (ex. `DESCONSIDERADO_PREDIO`, fora de escopo — task
# 19.4).
class AddDesconsideradoERessalvaToTimeRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :time_records, :desconsiderado, :boolean, null: false, default: false
    add_column :time_records, :ressalva, :boolean, null: false, default: false

    add_index :time_records, :desconsiderado
  end
end
