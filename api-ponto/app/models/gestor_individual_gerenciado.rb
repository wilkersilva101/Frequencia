class GestorIndividualGerenciado < ApplicationRecord
  # Join table: um GestorIndividual gerencia N Users (frequentadores).
  belongs_to :gestor_individual
  belongs_to :user

  # Tarefa 29.2 — prepara o vínculo para a importação idempotente do Intranet
  # (29.3). `id_legado` é único quando presente (índice UNIQUE no banco; os
  # vínculos criados localmente ficam nulos e convivem normalmente) e é a
  # chave de upsert do vínculo — sem ela, reimportar duplicaria o mesmo
  # gestor→gerido.
  validates :id_legado, uniqueness: true, allow_nil: true

  # Bug 3 do Bug Finder da 29.2 (🟡) — decisão do dev em 2026-09-29: no máximo
  # UM vínculo ATIVO por par gestor→gerido. A regra é aplicada pelo banco
  # (índice UNIQUE parcial `index_gestor_individual_gerenciados_on_par_ativo`,
  # migration `20260929130000`), que também cobre a corrida entre dois inserts
  # concorrentes — a validação abaixo é a mesma regra pelo lado do Rails, para
  # dar erro legível em vez de `RecordNotUnique` no fluxo normal.
  #
  # Bug 12 do Bug Finder da 29.2, 2ª rodada (🟡) — ASSIMETRIA validação × índice.
  # Sem o `if: :ativo?`, o `conditions` só filtrava as linhas EXISTENTES na
  # query; o Rails continuava validando o registro NOVO por completo, inclusive
  # quando ele era inativo. Resultado: um vínculo novo INATIVO (exatamente o
  # dado histórico que a importação da 29.3 traz do Intranet, com
  # `data_exclusao` legada) era barrado com "User já está em uso" num par que
  # já tivesse um ativo — embora o índice parcial do banco o aceitasse. Com
  # `if: :ativo?`, a validação espelha o índice nos QUATRO quadrantes
  # (ativo/ativo barra; ativo/inativo, inativo/ativo e inativo/inativo passam).
  validates :user_id,
            uniqueness: { scope: :gestor_individual_id, conditions: -> { where(ativo: true) } },
            if: :ativo?

  # Bug 4 do Bug Finder da 29.2 (🟡) — auto-gerência: o `gestor_user` do gestor
  # não pode figurar como seu próprio gerido. A regra E o gatilho vivem em UM
  # só lugar (29.2-D7, `InvarianteAutoGerencia`) porque cruza DUAS tabelas
  # (`gestores_individuais.gestor_user_id` ×
  # `gestor_individual_gerenciados.user_id`) e um CHECK do Postgres não pode
  # consultar outra tabela — então tinha de ser duplicada nos dois models, e a
  # duplicação gerou os Bugs 12/17/18. Este host usa a implementação padrão do
  # módulo (as duas colunas estão na mesma linha) e só declara a janela.
  include InvarianteAutoGerencia

  # Soft-delete do VÍNCULO (não do gestor nem do usuário): o gerido deixa de
  # ser gerenciado sem que a linha seja apagada. `destroy` não é sobrescrito
  # (ver mesmo racional em `GestorIndividual`). Predicado `ativo?` vem do
  # próprio ActiveRecord (coluna booleana).
  include Desativavel

  private

  # Revalidar só quando o próprio vínculo está ATIVO, espelhando o índice
  # UNIQUE parcial do banco (Bugs 12 e 18). Um vínculo inativo de
  # auto-gerência é histórico e precisa continuar reescrevível pela 29.3.
  # Este é o gatilho do `InvarianteAutoGerencia` (`included do validate ...
  # if: :janela_de_revalidacao`) — fica aqui, e não no `include`, para o
  # módulo ser dono do wiring.
  def janela_de_revalidacao
    ativo?
  end
end
