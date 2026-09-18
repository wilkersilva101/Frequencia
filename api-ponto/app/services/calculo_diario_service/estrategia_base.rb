# Sprint 16 (task 16.3) — classe base do Strategy pattern de cálculo
# diário por modalidade. Equivalente simplificado de `CalculoStrategyV2`
# (legado) — só o núcleo comum às 3 estratégias (meta do dia a partir do
# `Regime`, acesso às batidas do dia via `Dia`), sem as regras
# históricas/excepcionais do `CalculoStrategyV2` real (ver nota de escopo
# em `app/services/calculo_diario_service.rb`).
#
# Subclasses implementam só `#trabalhado_segundos` — a meta é comum e não
# depende da modalidade (o legado também usa a mesma fórmula de duração de
# período independente da modalidade; só o "trabalhado" muda por
# estratégia).
class CalculoDiarioService::EstrategiaBase
  def initialize(user:, data:, regime:)
    @user = user
    @data = data
    @regime = regime
  end

  # Resultado em segundos — `CalculoDiario` guarda tudo em `_segundos`,
  # não em minutos (diferente de `Regime#meta_semanal_em_minutos`, que é
  # semanal e não diário).
  def calcular
    { meta_segundos: meta_segundos, trabalhado_segundos: trabalhado_segundos }
  end

  private

  # Meta do dia = soma da duração dos períodos do `Regime` para o dia da
  # semana de `@data` (`Regime#periodos_por_dia_da_semana`, portado na
  # 16.2). Comum às 3 modalidades — `Horario.java` do legado também calcula
  # a duração do período independente da modalidade; só o cálculo do
  # "trabalhado" (`#trabalhado_segundos`) difere por estratégia.
  def meta_segundos
    periodos_do_dia.sum { |periodo| duracao_em_segundos(periodo) }
  end

  def periodos_do_dia
    @regime.periodos_por_dia_da_semana[@data.wday] || []
  end

  def duracao_em_segundos(periodo)
    inicio = periodo["inicio"].to_s
    fim = periodo["fim"].to_s
    return 0 if inicio.blank? || fim.blank?

    (minutos_desde_meia_noite(fim) - minutos_desde_meia_noite(inicio)) * 60
  end

  def minutos_desde_meia_noite(horario)
    hora, minuto = horario.split(":").map(&:to_i)
    (hora * 60) + minuto
  end

  # Batidas do dia, já ordenadas — reaproveita o agregado `Dia` (task 16.1)
  # em vez de consultar `TimeRecord` direto.
  #
  # Sprint 19 (task 19.2, UC-09): exclui `TimeRecord`s com
  # `desconsiderado: true` do cálculo. A exclusão é feita aqui (na camada
  # de cálculo), não em `Dia#registros` — `Dia` continua representando
  # TODAS as batidas reais do dia (o registro desconsiderado não é
  # soft-deleted, continua existindo/visível, só ganha `ressalva: true`,
  # ver `TimeRecord#desconsiderar!`); é o motor de cálculo que decide
  # ignorá-lo.
  def registros
    @registros ||= Dia.para(@user, @data).registros.reject(&:desconsiderado?)
  end

  def trabalhado_segundos
    raise NotImplementedError, "#{self.class} precisa implementar #trabalhado_segundos"
  end
end
