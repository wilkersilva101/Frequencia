class RegistroMensalFrequencia < ApplicationRecord
  # AG-4 (docs/PRD-FREQUENCIA.md) — consolidação mensal dos `CalculoDiario`
  # (AG-3) de um usuário: saldo líquido e banco de horas (retido/acumulado).
  # Portado de `RegistroMensalFrequencia.java` +
  # `RegistroMensalFrequenciaServices.java` (Intranet legada) — ver
  # `ConsolidacaoMensalService` (Sprint 17, task 17.1) para o algoritmo de
  # agregação/cálculo em si; este model é só o agregado persistido.
  belongs_to :user

  validates :ano, presence: true
  validates :mes, presence: true, inclusion: { in: 1..12 }
  validates :mes, uniqueness: { scope: %i[user_id ano] }

  # Task 17.2 — mecanismo real de congelamento. No legado (bean
  # `RegistroMensalFrequencia.java`), `finalizado` nasce `false` e o
  # comentário do próprio bean diz que deveria virar `true` "apos rodar o
  # algoritmo de desconto em folha" — mas `setFinalizado(true)` nunca é
  # chamado em lugar nenhum do código-fonte do legado (confirmado por grep
  # exaustivo), então a trava nunca funcionou na prática. Como o Frequencia
  # não tem (e não deve inventar aqui) esse algoritmo de desconto em folha
  # como gatilho automático, o fechamento é uma ação explícita/manual —
  # ver `ConsolidacaoMensalService.finalizar`.
  def finalizar!
    update!(finalizado: true)
  end

  # Reabertura administrativa: decisão consciente de implementar (não
  # deixar como pendência), pensando em correção de um mês finalizado por
  # engano antes de existir o retificador (task 18.2). Depois que o
  # retificador existir, reabrir um mês passa a ser o caminho errado pra
  # correção (o comentário do bean legado já orienta usar retificadores
  # pra modificações passadas) — mas até lá, `reabrir!` é a única forma de
  # corrigir um mês fechado incorretamente.
  def reabrir!
    update!(finalizado: false)
  end

  # Task 18.1 — extraído do cálculo inline de `ConsolidacaoMensalService`
  # (`registro.trabalhado - registro.meta_mensal`, mesma fórmula do
  # `saldoBruto` calculado em `calcularSaldoAcumulo`/`getSaldoBruto` do
  # legado) pra ser reutilizável por `RelatorioFrequenciaFinalService`
  # (AG-5), que precisa do saldo bruto do mês sem recalcular a consolidação.
  def saldo_bruto
    trabalhado - meta_mensal
  end
end
