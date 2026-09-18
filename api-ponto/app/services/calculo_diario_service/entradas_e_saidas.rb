# Sprint 16 (task 16.3) — modalidade HORAS_COM_INTERVALO. Portado (núcleo
# simplificado) de `EntradasESaidasV2.java`: trabalhado = soma dos pares
# completos de entrada/saída do dia (mesmo pareamento por índice par/ímpar
# de `Admin::TimeRecordsController#calcular_trabalhado`) — se sobrar uma
# marcação ímpar (entrada sem saída), ela é ignorada (mesmo espírito do
# `each_slice(2)` sem par completo, `saida` fica `nil`). Não replica
# interseção com períodos normais/excepcionais nem banco de horas diário —
# ver nota de escopo em `app/services/calculo_diario_service.rb`.
class CalculoDiarioService::EntradasESaidas < CalculoDiarioService::EstrategiaBase
  private

  def trabalhado_segundos
    total = 0
    registros.each_slice(2) do |par|
      entrada, saida = par
      total += (saida.punched_at - entrada.punched_at).to_i if saida
    end
    total
  end
end
