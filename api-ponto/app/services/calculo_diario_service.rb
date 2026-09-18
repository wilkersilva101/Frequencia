# Sprint 16 (task 16.3) — orquestração do cálculo diário v2 (DUV-005: v2 é
# o motor oficial, não as classes antigas sem sufixo). Portado de
# `CalculoDiarioServiceV2.java#calcularDia` (linhas 264-288, legado).
#
# Dado um `User` e uma `Date`: resolve o `RegimeFrequentador` vigente
# (`RegimeFrequentador.vigente_para`, task 16.3 parte 1); se não houver,
# grava a mesma informação do legado ("Nenhum regime ativo nesta data",
# `CalculoDiarioServiceV2.java:285`) e meta/trabalhado zerados; se houver,
# despacha para a estratégia certa conforme `regime.modalidade`
# (`CalculoDiarioService::ESTRATEGIAS`) e persiste o resultado em
# `CalculoDiario` (find_or_initialize_by usuário+data).
#
# ESCOPO ESTRITO desta task — deliberadamente NÃO implementado aqui (ver
# nota da 16.3 no SPRINT-PLAN.md para a lista completa e o motivo):
# - Regras históricas de data fixa (banco de horas GCET 2018-2022, carência
#   de 15min desde maio/2017, datas liberadas de novembro/2022);
# - Banco de horas / acúmulo de saldo entre dias (Sprint 17);
# - Expediente excepcional / feriados / abonos (`PresencaExcepcional` no
#   legado, sem conceito equivalente ainda no Frequencia);
# - `aberto` (turno em andamento) e `ausencia` (percentual de carga mínima
#   via `Regime::configuracao`) — ambos exigiriam portar mais regras do
#   `CalculoStrategyV2` do que o núcleo pedido nesta task; ficam `false`
#   (default da coluna) até uma task futura que os escopo explicitamente;
# - `falta_a_descontar`/`falta_compensada`/`descontado_em_folha` — pertencem
#   à consolidação mensal (Sprint 17), não ao cálculo diário isolado.
class CalculoDiarioService
  NENHUM_REGIME_ATIVO = "Nenhum regime ativo nesta data"

  def self.calcular(user, data)
    new(user, data).calcular
  end

  def initialize(user, data)
    @user = user
    @data = data.to_date
  end

  def calcular
    calculo = CalculoDiario.find_or_initialize_by(user: @user, data: @data)
    regime_frequentador = RegimeFrequentador.vigente_para(@user, @data)

    if regime_frequentador.nil?
      aplicar_sem_regime(calculo)
    else
      aplicar_resultado(calculo, regime_frequentador.regime)
    end

    calculo.save!
    calculo
  end

  private

  def aplicar_sem_regime(calculo)
    calculo.informacao = NENHUM_REGIME_ATIVO
    calculo.meta_segundos = 0
    calculo.normal_segundos = 0
    calculo.excepcional_segundos = 0
    calculo.total_segundos = 0
    calculo.falta = false
  end

  def aplicar_resultado(calculo, regime)
    estrategia_classe = CalculoDiarioService.estrategia_para(regime.modalidade)
    resultado = estrategia_classe.new(user: @user, data: @data, regime: regime).calcular

    calculo.informacao = nil
    calculo.meta_segundos = resultado[:meta_segundos]
    calculo.normal_segundos = resultado[:trabalhado_segundos]
    calculo.excepcional_segundos = 0
    calculo.total_segundos = resultado[:trabalhado_segundos]
    calculo.falta = falta?(resultado)
  end

  # Versão simplificada de `CalculoStrategyV2#configuraFalta` (linhas
  # 133-165, legado): meta > 0, nada trabalhado, e a data já passou. Não
  # replica a checagem de `aberto` (turno em andamento) nem a comparação
  # fina de horário quando a data é hoje — fora de escopo desta task (ver
  # nota de topo do arquivo).
  def falta?(resultado)
    resultado[:meta_segundos].to_i.positive? && resultado[:trabalhado_segundos].to_i.zero? && @data < Date.current
  end

  # Dispatch por modalidade — `CalculoDiarioServiceV2.java:264-288`
  # (`calcularDia`). Só usa as versões v2 das estratégias (DUV-005).
  def self.estrategia_para(modalidade)
    {
      "HORAS" => CalculoDiarioService::PrimeiraEntradaUltimaSaida,
      "HORAS_COM_INTERVALO" => CalculoDiarioService::EntradasESaidas,
      "OCORRENCIAS" => CalculoDiarioService::Ocorrencias
    }.fetch(modalidade) do
      raise ArgumentError, "Modalidade de regime desconhecida: #{modalidade.inspect}"
    end
  end
end
