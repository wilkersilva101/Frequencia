# Sprint 16 (task 16.3) — modalidade HORAS. Portado (núcleo simplificado)
# de `PrimeiraEntradaUltimaSaidaV2.java`: trabalhado = diferença entre a
# primeira e a última marcação do dia. Não replica limitação por
# `getPeriodosNormais`/interseção de período, carência de 15min, nem banco
# de horas diário — ver nota de escopo em
# `app/services/calculo_diario_service.rb`.
class CalculoDiarioService::PrimeiraEntradaUltimaSaida < CalculoDiarioService::EstrategiaBase
  private

  def trabalhado_segundos
    return 0 if registros.empty?

    (registros.last.punched_at - registros.first.punched_at).to_i
  end
end
