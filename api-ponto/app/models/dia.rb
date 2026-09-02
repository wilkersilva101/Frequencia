# Sprint 16 (task 16.1) — agregado `Dia` (AG-3), equivalente a `Dia.java`
# (Intranet legada, `modules.presenca.beans.Dia`).
#
# No legado, `Dia` NÃO é uma entidade JPA (não tem `@Entity`/tabela própria)
# — é um bean/agregador em memória que junta, para um `Frequentador` numa
# data: a lista de `RegistroFrequencia` (batidas do dia) e o `CalculoDiario`
# (resultado do cálculo daquele dia), além de direitos/dias excepcionais/
# feriados (fora do escopo desta task — pertencem a outros agregados/
# sprints, ex. AfastamentoCache na Sprint 12).
#
# Decisão de modelagem (persistido vs. calculado on-the-fly): `Dia` aqui é
# um PORO (plain old Ruby object), não um ActiveRecord com tabela própria —
# espelha fielmente o legado (que também nunca persiste `Dia`, só monta o
# objeto sob demanda a partir de `RegistroFrequencia` e `CalculoDiario`, que
# SIM são entidades reais). Persistir uma tabela `dias` duplicaria dado que
# já existe em `time_records` (equivalente a `RegistroFrequencia`, decisão
# tomada na Sprint 13/task 13.1) e criaria um problema de sincronização sem
# necessidade — não há, ainda, nenhum motor de cálculo (16.2/16.3) que
# precise gravar um "snapshot" do dia além do que `CalculoDiario` já cobre.
#
# `RegistroFrequencia` (legado) == `TimeRecord` (Frequencia) — confirmado
# na Sprint 13 (task 13.1). Não há model novo para isso: `Dia` agrega os
# `TimeRecord`s existentes do usuário na data via `#registros`.
#
# ESCOPO ESTRITO desta task: só a estrutura de agregação (relações,
# cardinalidade). Nenhuma lógica de cálculo de horas/meta/banco de horas —
# `#calculo` apenas expõe o `CalculoDiario` existente (ou nil, se o motor
# de cálculo ainda não rodou para esse dia); não cria nem popula nada.
class Dia
  attr_reader :user, :data

  def self.para(user, data)
    new(user: user, data: data)
  end

  def initialize(user:, data:)
    @user = user
    @data = data.to_date
  end

  # Batidas do frequentador nesse dia (equivalente a `Dia#getRegistros` /
  # `List<RegistroFrequencia>` do legado). Ordenado por horário da batida,
  # igual à leitura já feita pela Sprint 13.
  def registros
    @registros ||= user.time_records.by_date(data).order(:punched_at)
  end

  # Resultado do cálculo diário (equivalente a `Dia#getCalculo` /
  # `CalculoDiario` do legado). Não cria/popula — só busca o que já existe.
  # Permanece `nil` até o motor de cálculo (16.2/16.3) rodar para esse dia.
  def calculo
    @calculo ||= CalculoDiario.find_by(user: user, data: data)
  end

  def ==(other)
    other.is_a?(Dia) && other.user == user && other.data == data
  end
end
