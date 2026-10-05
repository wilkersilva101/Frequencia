# Tarefa 29.2 — exclusão lógica (soft-delete) compartilhada.
#
# A partir da importação do Intranet (29.3), gestores individuais e seus
# VÍNCULOS com geridos deixam de ser gerenciados sem que a linha seja apagada:
# o histórico operacional é preservado (regra global: "não remova histórico
# operacional sem arquivar"). As duas tabelas têm exatamente a mesma dupla
# `ativo`/`data_exclusao`, então a lógica vive aqui em um só lugar — sem isso,
# um ajuste no guard precisaria ser aplicado duas vezes e os models
# divergiriam.
#
# Requer no host: colunas boolean `ativo` (NOT NULL, default true) e datetime
# anulável `data_exclusao`.
module Desativavel
  extend ActiveSupport::Concern

  included do
    scope :ativos, -> { where(ativo: true) }
  end

  # Idempotente: preserva SEMPRE a data da primeira exclusão.
  #
  # Bugs 5 e 6 do Bug Finder da 29.2 (decisão do dev em 2026-09-29). O guard
  # anterior (`!ativo && data_exclusao.present?`) era inconsistente: com
  # `ativo=false` e `data_exclusao` nula ele PREENCHIA a data, e com
  # `ativo=true` e data já preenchida (registro legado desativado com a flag
  # divergente) ele SOBRESCREVIA a data real. Como a 29.3 importa a
  # `data_exclusao` do Intranet, sobrescrever apagaria a data verdadeira de
  # exclusão do legado.
  #
  # `momento ||= Time.current`: o default de argumento não cobre `nil` explícito,
  # que gravava "desativado sem data" (estado implausível para auditoria).
  #
  # Retorna SEMPRE `self` (Bug 13 do Bug Finder da 2ª rodada, 🟢): antes o ramo
  # de `update!` devolvia `true` e o ramo idempotente devolvia o registro — um
  # `if vinculo.desativar!` ou encadeamento se comportaria de dois jeitos.
  #
  # Observação para a 29.3: a importação deve gravar a `data_exclusao` legada
  # DIRETO (atributo), nunca via `desativar!` — este método data a exclusão ao
  # momento da chamada, que não é a data do legado.
  def desativar!(momento = nil)
    momento ||= Time.current

    return self if !ativo && data_exclusao.present?

    # Preserva a data já registrada (primeira exclusão), mesmo que a flag
    # `ativo` esteja divergente; ajusta só a flag nesse caso.
    update!(ativo: false, data_exclusao: data_exclusao || momento)
    self
  end
end
