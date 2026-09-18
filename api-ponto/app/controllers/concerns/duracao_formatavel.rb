module DuracaoFormatavel
  extend ActiveSupport::Concern

  # Formata segundos como "HH:MM:SS". Extraído de
  # `Admin::TimeRecordsController` (task 17.3) pra ser reaproveitado também
  # em `Admin::FrequenciaPorOrgaoController` — mesmo formato, sem inventar
  # um segundo padrão de exibição de duração no projeto.
  def formatar_duracao(total_segundos)
    horas = total_segundos / 3600
    minutos = (total_segundos % 3600) / 60
    segundos = total_segundos % 60
    format("%02d:%02d:%02d", horas, minutos, segundos)
  end
end
