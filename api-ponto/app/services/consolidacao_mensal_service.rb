# Sprint 17 (task 17.1) — consolidação mensal: agrega os `CalculoDiario`
# (AG-3) de um usuário num mês em `RegistroMensalFrequencia` (AG-4) e
# calcula saldo líquido / banco de horas (retido/acumulado). Portado de
# `RegistroMensalFrequenciaServices.java` (`calcular`/`aplicarCalculosDiarios`/
# `calcularSaldoAcumulo`, Intranet legada, linhas 41-104 e 106-152).
#
# ESCOPO ESTRITO da task 17.1 — deliberadamente NÃO implementado ali (ver
# nota da task 17.1 no SPRINT-PLAN.md):
# - Algoritmo de desconto em folha (faltasACompensar/faltasADescontar/
#   creditoADevolver do bean legado) — continua fora de escopo, sem campo
#   equivalente na tabela.
#
# Task 17.2 — congelamento real de `finalizado` (corrige o bug do legado:
# `setFinalizado(true)` nunca era chamado em lugar nenhum do
# `RegistroMensalFrequencia.java`/`RegistroMensalFrequenciaServices.java`
# original, então a trava de "mês fechado, não recalcula mais" nunca
# funcionou na prática — todo mês era recalculável pra sempre). Agora
# `consolidar` recusa recalcular um mês já `finalizado?`, levantando
# `MesFinalizadoError` em vez de silenciosamente devolver o registro
# existente sem tocar nos campos — uma API que falha silenciosamente
# voltando um valor "errado"/desatualizado sem avisar quem chamou seria
# pior que um erro explícito aqui, já que o chamador pode estar assumindo
# que os campos foram recalculados. `ConsolidacaoMensalService.finalizar`
# é o novo ponto de entrada pra fechar um mês explicitamente (ação manual
# — o Frequencia não tem o "algoritmo de desconto em folha" que o legado
# usava como gatilho automático de fechamento).
#
# Task 18.2 — `RetificadorBancoHoras` (UC-12) passa a alimentar `retificado`
# de verdade (antes sempre 0). `consolidar` soma os retificadores não
# excluídos do usuário no mês/ano (`aplicar_retificadores`), na fórmula já
# existente `saldo_liquido = saldo_acumulado_mes_anterior + saldo_bruto +
# retificado` (nenhuma mudança na fórmula em si).
#
# Decisão de design — retificar um mês FINALIZADO: o comentário do bean
# legado (`RegistroMensalFrequencia.java`) já descrevia a intenção
# original: "modificacoes passadas devem ser feitas utilizando
# retificadores" — ou seja, o retificador É o caminho pretendido pra
# corrigir um mês já fechado, sem precisar reabri-lo. Mas `consolidar`
# continua bloqueado por `MesFinalizadoError` em mês finalizado — ele
# reagrega os `CalculoDiario` do zero, e reagregar destruiria o
# congelamento de `trabalhado`/`meta_mensal`/etc. que `finalizar!` deveria
# preservar (essa é a garantia real da 17.2: nada muda depois de
# finalizado, exceto pela via explícita do retificador). Por isso, criado
# `ConsolidacaoMensalService.aplicar_retificador(user, ano, mes)` como
# ponto de entrada SEPARADO: reaplica só a soma de retificadores e
# recalcula saldo/banco de horas (`retificado`/`saldo_liquido`/`retido`/
# `acumulado`), preservando os totais de trabalhado/meta já "congelados"
# — funciona inclusive com `finalizado? == true` (não passa pela trava do
# `consolidar`), porque é exatamente o caminho que a trava deveria permitir
# passar. Exige que o registro já exista (não faz sentido retificar um mês
# nunca consolidado).
class ConsolidacaoMensalService
  class MesFinalizadoError < StandardError; end

  def self.consolidar(user, ano, mes, hoje: Date.current)
    new(user, ano, mes, hoje: hoje).consolidar
  end

  # Fecha um mês já consolidado, travando-o contra recálculo (`consolidar`
  # passa a levantar `MesFinalizadoError` pra esse mês). Exige que o
  # registro já exista (não faz sentido finalizar um mês nunca calculado).
  def self.finalizar(user, ano, mes)
    registro = RegistroMensalFrequencia.find_by!(user: user, ano: ano, mes: mes)
    registro.finalizar!
    registro
  end

  # Task 18.2 — reaplica só a soma de retificadores e recalcula
  # saldo/banco de horas de um mês JÁ consolidado, sem reagregar os
  # `CalculoDiario` do zero (preserva trabalhado/meta/faltas/dias_em_aberto
  # já persistidos). Funciona mesmo com o mês `finalizado?` — ver decisão
  # de design no comentário de topo da classe. Exige registro existente.
  def self.aplicar_retificador(user, ano, mes)
    new(user, ano, mes).aplicar_retificador
  end

  def initialize(user, ano, mes, hoje: Date.current)
    @user = user
    @ano = ano
    @mes = mes
    @hoje = hoje
  end

  def consolidar
    registro = RegistroMensalFrequencia.find_or_initialize_by(user: @user, ano: @ano, mes: @mes)

    if registro.persisted? && registro.finalizado?
      raise MesFinalizadoError,
            "Mês #{@mes}/#{@ano} do usuário #{@user.id} já está finalizado e não pode ser recalculado. " \
            "Reabra o registro (RegistroMensalFrequencia#reabrir!) antes de recalcular, se necessário."
    end

    registro.data_inicio = data_inicio
    registro.data_fim = data_fim

    zerar(registro)
    aplicar_calculos_diarios(registro)
    registro.retificado = soma_retificadores
    aplicar_saldo(registro)

    registro.save!
    registro
  end

  # Task 18.2 — ver decisão de design no comentário de topo da classe. Só
  # recalcula `retificado`/`saldo_liquido`/`retido`/`acumulado`; não zera
  # nem reagrega `trabalhado`/`meta_mensal`/`faltas`/`dias_em_aberto`
  # (preserva o que já foi "congelado", inclusive em mês finalizado).
  def aplicar_retificador
    registro = RegistroMensalFrequencia.find_by!(user: @user, ano: @ano, mes: @mes)

    registro.retificado = soma_retificadores
    aplicar_saldo(registro)

    registro.save!
    registro
  end

  private

  def data_inicio
    Date.new(@ano, @mes, 1)
  end

  def data_fim
    data_inicio.end_of_month
  end

  # Portado de `zerarRegistro` (linhas 67-82, legado) — reseta os campos
  # calculados antes de reagregar, pra que um recálculo não acumule em
  # cima de um resultado anterior.
  def zerar(registro)
    registro.assign_attributes(
      dias_em_aberto: 0,
      meta_atual: 0,
      meta_atual_dias: 0,
      meta_mensal: 0,
      meta_mensal_dias: 0,
      saldo_liquido: 0,
      trabalhado: 0,
      trabalhado_dias: 0,
      trabalhado_normal: 0,
      faltas: 0,
      acumulado: 0,
      retido: 0,
      retificado: 0
    )
  end

  def calculos_do_mes
    CalculoDiario.where(user: @user, data: data_inicio..data_fim).order(:data)
  end

  # Task 18.2 — portado de `RegistroMensalFrequencia.java#aplicarRetificadoresDeBancoHoras`
  # (paridade com `RetificadorDeBancoHorasDao.listDoFrequentadorNoMesEAno`,
  # que já filtra `excluido = false`): soma
  # `segundos_a_retificar * fator_multiplicacao` de todos os retificadores
  # não excluídos do usuário nesse mês/ano específico. Usa `sum` com bloco
  # (não `+=` num laço) deliberadamente — evita por construção a classe de
  # bug do legado DUV-011 (`cont=+valor` em vez de `cont+=valor`, task
  # 18.3), já que `Enumerable#sum` sempre acumula.
  def soma_retificadores
    RetificadorBancoHoras
      .where(user: @user, ano: @ano, mes: @mes, excluido: false)
      .sum { |retificador| retificador.segundos_a_retificar * retificador.fator_multiplicacao }
  end

  # Portado de `aplicarCalculosDiarios` (linhas 106-152, legado).
  def aplicar_calculos_diarios(registro)
    calculos_do_mes.each do |calculo|
      registro.dias_em_aberto += 1 if calculo.aberto

      if pode_calcular?(calculo)
        if calculo.meta_segundos.to_i.positive?
          registro.meta_atual_dias += 1
          registro.meta_mensal_dias += 1
        end
        registro.meta_atual += calculo.meta_segundos.to_i
      end

      if calculo.falta
        registro.faltas += 1
      elsif calculo.total_segundos.to_i.positive?
        registro.trabalhado_dias += 1
      end

      registro.meta_mensal += calculo.meta_segundos.to_i
      registro.trabalhado_normal += calculo.normal_segundos.to_i
      registro.trabalhado += calculo.total_segundos.to_i
    end
  end

  # Portado de `isPodeCalcular` (linhas 123-132, legado): só conta a meta
  # do dia em `meta_atual`/`meta_atual_dias` quando a data já passou, ou é
  # hoje mas o dia não está mais aberto e teve algo trabalhado
  # (`total != 0`). É isso que distingue "meta mensal" (soma cega de todos
  # os dias, inclusive futuros) de "meta atual" (só o que já é exigível
  # até agora). Comparação direta de `Date` (`<`/`==`) é equivalente à
  # comparação de ano + dia-do-ano feita pelo legado.
  def pode_calcular?(calculo)
    calculo.data < @hoje || (calculo.data == @hoje && !calculo.aberto && calculo.total_segundos.to_i != 0)
  end

  def aplicar_saldo(registro)
    regime_frequentador = RegimeFrequentador.vigente_para(@user, data_fim)
    return if regime_frequentador.nil?

    calcular_saldo_acumulo(registro, regime_frequentador.regime, buscar_saldo_mes_anterior)
  end

  # Portado de `RegistroMensalFrequenciaServices#getSaldoMesAnterior`
  # (linhas 154-162, versão do SERVICE, mais simples — é a que `calcular`
  # realmente usa, não a versão homônima do bean que soma retido/retificado
  # de novo). Usa o `acumulado` do mês anterior diretamente; 0 quando não
  # existe registro do mês anterior.
  def buscar_saldo_mes_anterior
    mes_anterior = data_inicio.prev_month
    registro_anterior = RegistroMensalFrequencia.find_by(user: @user, ano: mes_anterior.year, mes: mes_anterior.month)
    registro_anterior&.acumulado.to_i
  end

  # Portado de `calcularSaldoAcumulo` (linhas 84-104, legado): saldo
  # líquido = saldo do mês anterior + saldo bruto (trabalhado - meta
  # mensal) + retificado (soma dos `RetificadorBancoHoras` não excluídos do
  # mês/ano, task 18.2 — ver `soma_retificadores`). Limite de banco de horas:
  # `limite_credito` (se saldo >= 0) ou `-limite_debito` (se saldo < 0) do
  # regime — ambos guardados em HORAS, convertidos pra segundos (* 3600,
  # mesmo fator do legado). O que exceder o limite vira `retido`;
  # `acumulado` é o saldo líquido já descontado o retido (nunca ultrapassa
  # o limite, positivo ou negativo).
  def calcular_saldo_acumulo(registro, regime, saldo_mes_anterior)
    saldo_bruto = registro.trabalhado - registro.meta_mensal
    saldo_liquido = saldo_mes_anterior + saldo_bruto + registro.retificado

    if saldo_liquido >= 0
      limite = regime.limite_credito * 3600
      excedente = saldo_liquido > limite
    else
      limite = -regime.limite_debito * 3600
      excedente = saldo_liquido < limite
    end

    retido = excedente ? saldo_liquido - limite : 0

    registro.saldo_liquido = saldo_liquido
    registro.retido = retido
    registro.acumulado = saldo_liquido - retido
  end
end
