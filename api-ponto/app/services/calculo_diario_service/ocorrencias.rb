# Sprint 16 (task 16.3) — modalidade OCORRENCIAS. Portado (núcleo
# simplificado) de `OcorrenciasV2.java`: não é hora trabalhada, é
# presença/ausência binária no período esperado — `getCalculo(presente)`
# do legado (linhas 56-64) atribui `trabalhado = meta` quando há QUALQUER
# marcação no dia, e `0` quando não há nenhuma. Não replica o cálculo de
# horas extras quando há mais de uma batida
# (`calcularComHorasExtras`/`ajustarSegundosTrabalhados`, que dependem da
# carência de 15min e do banco de horas diário) — ver nota de escopo em
# `app/services/calculo_diario_service.rb`.
class CalculoDiarioService::Ocorrencias < CalculoDiarioService::EstrategiaBase
  private

  def trabalhado_segundos
    registros.any? ? meta_segundos : 0
  end
end
