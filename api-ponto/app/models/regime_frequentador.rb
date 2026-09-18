class RegimeFrequentador < ApplicationRecord
  # Membro de AG-2 (docs/PRD-FREQUENCIA.md §4.2) — vínculo de um período de
  # regime a um frequentador. Corresponde ao legado
  # `presenca_regimefrequentador` (frequentador_id/regime_id/tipo/
  # momentoInicial/momentoFinal), sem os campos de auditoria de correção
  # (`momentoInicialOriginal`/`momentoFinalOriginal`/`dataAlteracao`), que
  # só fazem sentido quando existir edição retroativa (fora de escopo
  # desta sprint).

  belongs_to :user
  belongs_to :regime

  validates :momento_inicial, presence: true

  # --- Precedência (Sprint 16, task 16.3) ---------------------------------
  # Portado de `TipoRegimeFrequentadorEnum.java` (ordem) +
  # `RegimentoServices.getRegimeFrequentador` (linhas 75-88, legado): quando
  # um frequentador tem mais de um `RegimeFrequentador` vigente na mesma
  # data, vence o de MAIOR ordem — TEMPORARIO(2) > DIFERENCIADO(1) >
  # OFICIAL(0).
  OFICIAL = "OFICIAL"
  DIFERENCIADO = "DIFERENCIADO"
  TEMPORARIO = "TEMPORARIO"

  TIPOS_DISPONIVEIS = [ OFICIAL, DIFERENCIADO, TEMPORARIO ].freeze

  PRECEDENCIA = {
    OFICIAL => 0,
    DIFERENCIADO => 1,
    TEMPORARIO => 2
  }.freeze

  # `tipo` hoje é campo livre (sem validação de valores), e o banco de dev
  # já tem `RegimeFrequentador`s existentes com `tipo` nil ou fora dos 3
  # valores válidos (ex: dado de teste/legado). Decisão: não quebrar esses
  # registros — um `tipo` ausente/desconhecido é tratado como a MENOR
  # precedência possível (abaixo até de OFICIAL), nunca levanta erro aqui.
  # Não adicionamos `validates :tipo, inclusion: ...` nesta task (fora de
  # escopo — mudaria comportamento de cadastro existente sem pedido
  # explícito); só a leitura/ordenação é defensiva.
  PRECEDENCIA_DESCONHECIDA = -1

  # Portado de `RegimeFrequentador.java:138-146` (`contem(Calendar data)`):
  # o período do vínculo contém a data quando `momento_inicial <= data` e
  # (`momento_final` é nil OU `data <= momento_final`).
  scope :vigentes_em, ->(data) {
    where("momento_inicial <= ?", data.to_date.end_of_day)
      .where("momento_final IS NULL OR momento_final >= ?", data.to_date.beginning_of_day)
  }

  # Portado de `RegimentoServices.getRegimeFrequentador(Frequentador, Calendar)`
  # (linhas 75-88, legado): lista os `RegimeFrequentador`s do usuário
  # vigentes na data, ordena por precedência (`PRECEDENCIA`) e retorna o de
  # MAIOR precedência (`TEMPORARIO > DIFERENCIADO > OFICIAL`). `nil` quando
  # não há nenhum vigente na data.
  #
  # Decisão de estrutura: método de classe em `RegimeFrequentador` (não
  # `User#regime_frequentador_vigente`) — a regra de precedência pertence
  # inteiramente aos dados do próprio `RegimeFrequentador` (seu `tipo` e
  # período), então fica mais natural como uma consulta de classe deste
  # model, no mesmo espírito de `RegimentoServices` ser um service dedicado
  # a `RegimeFrequentador`/`Regime` no legado.
  def self.vigente_para(user, data)
    where(user: user).vigentes_em(data).max_by { |rf| PRECEDENCIA.fetch(rf.tipo, PRECEDENCIA_DESCONHECIDA) }
  end
end
