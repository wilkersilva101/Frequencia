# Sprint 19, task 19.1 (UC-08) — registra a distinção que o legado faz em
# `RegistroFrequencia#manualFromForm` (intranet/src/modules/presenca/beans/
# RegistroFrequencia.java:214-246) entre dois conceitos relacionados:
#
# - "batida manual" (tipo: "batida_manual", errata=false no legado): um
#   admin insere um TimeRecord NOVO pra um frequentador (esqueceu de bater,
#   máquina com problema etc). O legado salva o registro (`Dao.save`) ANTES
#   de criar a intervenção — a intervenção é só a justificativa documentada.
#   Aqui: `status: "registrado"`, `time_record` sempre presente.
#
# - "errata" (tipo: "errata", errata=true no legado): uma CORREÇÃO — o
#   legado não salva o registro imediatamente (`Dao.save` só roda no
#   branch `!errata`), fica pendente até a intervenção ser
#   resolvida/aprovada. Aqui: `status: "pendente"`, sem `time_record`
#   (a resolução — aprovar cria o TimeRecord, rejeitar mantém só o
#   histórico — é escopo de task futura da Sprint 19, não desta).
#
# Decisão consciente de escopo (task 19.1, reafirmada na 19.2): o legado
# usa um mecanismo genérico de aprovação (`PreVinculadoIntervencao`, com N
# tipos de ação via `PreVinculadoAcaoEnum`) compartilhado por TODAS as UCs
# de gestão de exceções da Sprint 19 (batida manual/errata,
# desconsiderar/reconsiderar ponto, autorizar horas extras, autorizar
# batida em prédio não permitido). Generalizar esse framework inteiro
# arriscaria superdimensionar o escopo de cada task individual. Este model
# cobre incrementalmente só o necessário por task (nesta, +2 valores de
# `tipo` para UC-09) — mas com uma estrutura (responsável, justificativa,
# momento, status, time_record) pensada pra ser reaproveitada/estendida,
# não uma modelagem descartável.
#
# Sprint 19, task 19.2 (UC-09) — acrescenta "desconsideracao_ponto" e
# "reconsideracao_ponto", portados de `RegistroFrequencia#desconsiderar` e
# `#reconsiderar` (intranet, linhas 300-318 e 340-358). Diferente de
# "errata", esses 2 tipos sempre agem sobre um `TimeRecord` já existente
# (nunca criam um novo) — por isso entram no grupo que exige `time_record`
# presente, junto com "batida_manual". `justificativa` é obrigatória para
# todos os tipos MENOS "reconsideracao_ponto" — o legado não recebe
# `intervencaoObs` em `reconsiderar` (diferente de `desconsiderar`, que
# exige).
#
# Sprint 19, task 19.3 (UC-10) — acrescenta "acumulo_horas_extras",
# portado de `RegistroFrequencia#preencheIntervencaoLimitado` (intranet,
# linhas 248-266) + `PreVinculadoAcaoEnum` (ACAO_ACUMULO_DE_HORAS_EXTRAS /
# ACAO_AUTORIZACAO_ACUMULO_DE_HORAS_EXTRAS / ACAO_INDEFERIMENTO_...).
# Diferente de todos os tipos anteriores, este é o primeiro em que o
# PEDIDO nasce sem responsável humano (é o próprio sistema quem abre a
# solicitação — `preencheIntervencaoLimitado` não recebe
# `Servidor responsavel`) — por isso `responsavel` virou opcional e
# `TIPOS_SEM_RESPONSAVEL_OBRIGATORIO` existe. Pelo mesmo motivo, não
# exige `justificativa` na criação (o sistema não "justifica", só
# constata o acúmulo — diferente de `desconsiderar!`, onde é uma pessoa
# justificando uma ação). Sempre exige `time_record` (a marcação de
# saída específica que gerou o acúmulo).
#
# Taxonomia final de `status` (4 valores):
# - "registrado": ação humana já efetiva no momento da criação, sem
#   workflow de aprovação (batida_manual, desconsideracao_ponto,
#   reconsideracao_ponto).
# - "pendente": um pedido em aberto aguardando decisão (errata —
#   resolução ainda não implementada, task futura; acumulo_horas_extras
#   — resolução via #deferir!/#indeferir! nesta task).
# - "aprovado": pedido pendente que foi deferido (`resolvido_por`
#   preenchido). Não é redundante com "registrado": "registrado" nunca
#   passou por um estado pendente, "aprovado" sempre veio de "pendente".
# - "indeferido": pedido pendente que foi negado (`resolvido_por`
#   preenchido; as horas extras não contam).
#
# `resolvido_por` é um campo distinto de `responsavel` porque descrevem
# papéis diferentes: `responsavel` é "quem é responsável pela ação
# registrada" (pode ser nil quando é o sistema que gera o pedido);
# `resolvido_por` é "quem decidiu um pedido pendente" — sempre uma
# pessoa (um gestor), preenchido só na resolução (deferir!/indeferir!),
# independente de quem (ou o quê) criou o pedido.
#
# Sprint 19, task 19.4 (UC-11) — acrescenta "desconsideracao_predio" e
# "autorizacao_predio", portados de
# `RegistroFrequencia#desconsiderarPorPredioNaoPermitido` (intranet,
# linhas 320-338) e `#preencheIntervencaoBaterPontoEstacaoNaoPermitida`
# (linhas 268-286). "desconsideracao_predio" segue o mesmo grupo de
# "desconsideracao_ponto" (TIPOS_COM_TIME_RECORD, sempre "registrado",
# efetivo na hora) — é a mesma ação de excluir um TimeRecord do cálculo,
# só com motivo específico (prédio não autorizado, não correção manual).
# "autorizacao_predio" segue o mesmo padrão de "acumulo_horas_extras":
# pedido "pendente" resolvido por #deferir!/#indeferir! já existentes
# (a lógica de resolução não depende do tipo, só do status — confirmado
# nos testes desta task). Achado ao portar: o código real do legado usa
# por engano o enum `ACAO_ACUMULO_DE_HORAS_EXTRAS` dentro de
# `preencheIntervencaoBaterPontoEstacaoNaoPermitida` (bug de copy-paste —
# a mensagem fala de "bater ponto em prédio", mas o enum usado é o de
# horas extras); os nomes corretos pro conceito de prédio,
# `ACAO_AUTORIZACAO_PERMITIR_BATER_PONTO_OUTRO_PREDIO`/
# `ACAO_INDEFERIMENTOPERMITIR_BATER_PONTO_OUTRO_PREDIO`, existem em
# `PreVinculadoAcaoEnum` (linhas 79-80) mas nunca são usados pelo código
# real — o bug não foi replicado aqui, o tipo novo usa o conceito
# correto. Diferente de "acumulo_horas_extras", quem abre o pedido de
# autorização de prédio é sempre uma pessoa (um responsável aciona
# manualmente — não há detecção automática de "prédio não permitido"
# nesta sprint, ver nota da task no SPRINT-PLAN.md), então
# "autorizacao_predio" NÃO entra em `TIPOS_SEM_RESPONSAVEL_OBRIGATORIO`.
class IntervencaoFrequencia < ApplicationRecord
  TIPOS = %w[batida_manual errata desconsideracao_ponto reconsideracao_ponto acumulo_horas_extras
             desconsideracao_predio autorizacao_predio].freeze
  STATUSES = %w[registrado pendente aprovado indeferido].freeze

  # Tipos que sempre agem sobre/criam um TimeRecord real (nunca ficam sem
  # ele, diferente de "errata", que nesta sprint nunca tem).
  TIPOS_COM_TIME_RECORD = %w[batida_manual desconsideracao_ponto reconsideracao_ponto acumulo_horas_extras
                              desconsideracao_predio autorizacao_predio].freeze

  # Tipos cuja justificativa não é exigida pelo legado: "reconsideracao_ponto"
  # (`reconsiderar` não recebe `intervencaoObs`) e "acumulo_horas_extras"
  # (pedido gerado pelo sistema, não por uma pessoa se justificando).
  # "desconsideracao_predio" tem justificativa padrão gerada automaticamente
  # (ver `TimeRecord#desconsiderar_por_predio!`), por isso também dispensa a
  # obrigatoriedade aqui no model — quem chama pode customizar, mas o método
  # sempre garante um valor presente antes do `create!`. "autorizacao_predio"
  # segue o mesmo padrão de "acumulo_horas_extras": o pedido só constata um
  # fato (bateu num prédio não autorizado), sem exigir texto livre.
  TIPOS_SEM_JUSTIFICATIVA_OBRIGATORIA = %w[reconsideracao_ponto acumulo_horas_extras desconsideracao_predio
                                            autorizacao_predio].freeze

  # Tipos cujo pedido nasce sem responsável humano obrigatório na criação.
  # "acumulo_horas_extras": é o sistema quem abre a solicitação (ver
  # `.solicitar_autorizacao_horas_extras`). "autorizacao_predio": embora
  # a ativação seja sempre manual (um admin/gestor aciona — não há
  # detecção automática, ver nota da task 19.4), o método de classe segue
  # deliberadamente a mesma assinatura minimalista de
  # `.solicitar_autorizacao_horas_extras` (só `time_record`/
  # `estacao_ponto:`); quem chama pode registrar o responsável apontando
  # `responsavel:` na resolução (`#deferir!`/`#indeferir!` já exigem
  # `responsavel:` nesse momento) — não há perda de rastreabilidade, só
  # o mesmo desenho de "sistema/mecanismo abre o pedido, pessoa resolve".
  TIPOS_SEM_RESPONSAVEL_OBRIGATORIO = %w[acumulo_horas_extras autorizacao_predio].freeze

  # Levantado por #deferir!/#indeferir! quando a intervenção não está em
  # `status: "pendente"` — resolver algo que já foi resolvido, ou que
  # nunca foi um pedido pendente (ex.: "batida_manual", que já nasce
  # "registrado"), é erro de uso, não deve falhar silenciosamente.
  class ResolucaoInvalidaError < StandardError; end

  belongs_to :user
  belongs_to :responsavel, class_name: "User", optional: true
  belongs_to :resolvido_por, class_name: "User", optional: true
  belongs_to :time_record, optional: true

  validates :tipo, presence: true, inclusion: { in: TIPOS }
  validates :justificativa, presence: true, unless: -> { TIPOS_SEM_JUSTIFICATIVA_OBRIGATORIA.include?(tipo) }
  validates :momento, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :punch_type, inclusion: { in: %w[entry exit], allow_nil: true }
  validates :responsavel, presence: true, unless: -> { TIPOS_SEM_RESPONSAVEL_OBRIGATORIO.include?(tipo) }

  validates :time_record, presence: true, if: -> { TIPOS_COM_TIME_RECORD.include?(tipo) }
  validates :time_record, absence: true, if: -> { tipo == "errata" }

  # Sprint 19 (task 19.3, UC-10) — abre o pedido pendente de autorização
  # de acúmulo de horas extras pra um `TimeRecord` de saída específico.
  # Método de classe porque é o SISTEMA quem cria o pedido (equivalente a
  # `preencheIntervencaoLimitado` no legado), não uma pessoa — por isso
  # sem `responsavel:` nem `justificativa:` na assinatura.
  def self.solicitar_autorizacao_horas_extras(time_record)
    create!(
      user: time_record.user,
      tipo: "acumulo_horas_extras",
      momento: time_record.punched_at,
      punch_type: time_record.punch_type,
      time_record: time_record,
      status: "pendente"
    )
  end

  # Sprint 19 (task 19.4, UC-11) — abre o pedido pendente de autorização
  # pra um frequentador bater ponto num prédio hoje não permitido pra
  # ele, equivalente a
  # `preencheIntervencaoBaterPontoEstacaoNaoPermitida` no legado (sem
  # replicar o bug de enum trocado, ver nota no topo do arquivo). Método
  # de instância (não de classe, diferente de
  # `.solicitar_autorizacao_horas_extras`) porque aqui é sempre uma
  # PESSOA quem aciona manualmente — não há detecção automática de
  # "prédio não permitido" nesta sprint (o conceito de `Predio` não
  # existe no Frequencia, decisão já tomada na task 9.6).
  # `estacao_ponto:` não é persistida na intervenção — o `time_record`
  # já referencia sua `estacao_ponto` (desde a Sprint 13.1), acessível
  # via `time_record.estacao_ponto`, então guardar de novo aqui
  # duplicaria dado sem necessidade; o parâmetro existe só pra deixar a
  # intenção explícita na chamada e permitir validar consistência no
  # futuro, se necessário.
  def self.solicitar_autorizacao_predio(time_record, estacao_ponto:)
    create!(
      user: time_record.user,
      tipo: "autorizacao_predio",
      momento: time_record.punched_at,
      punch_type: time_record.punch_type,
      time_record: time_record,
      status: "pendente"
    )
  end

  # Sprint 19 (task 19.3, UC-10) — defere o pedido pendente: as horas
  # extras acumuladas passam a contar (equivalente a
  # `ACAO_AUTORIZACAO_ACUMULO_DE_HORAS_EXTRAS` no legado).
  def deferir!(responsavel:)
    resolver!(status: "aprovado", resolvido_por: responsavel)
  end

  # Sprint 19 (task 19.3, UC-10) — indefere o pedido pendente: as horas
  # extras acumuladas não contam, ficam limitadas na meta (equivalente a
  # `ACAO_INDEFERIMENTO_ACUMULO_DE_HORAS_EXTRAS` no legado).
  def indeferir!(responsavel:)
    resolver!(status: "indeferido", resolvido_por: responsavel)
  end

  private

  def resolver!(status:, resolvido_por:)
    unless self.status == "pendente"
      raise ResolucaoInvalidaError,
            "Só é possível resolver uma intervenção pendente (status atual: #{self.status.inspect})"
    end

    update!(status: status, resolvido_por: resolvido_por)
  end
end
