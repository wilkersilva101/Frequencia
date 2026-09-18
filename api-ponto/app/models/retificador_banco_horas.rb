class RetificadorBancoHoras < ApplicationRecord
  # Sprint 18 (task 18.2) — mecanismo de correção manual do banco de horas
  # (UC-12). Portado de `RetificadorDeBancoHoras.java` (bean) +
  # `TipoRetificadorEnum.java` (Intranet legada). Um usuário pode ter vários
  # retificadores, inclusive vários no mesmo mês/ano. Cada um credita ou
  # debita `segundos_a_retificar` no `retificado` de `RegistroMensalFrequencia`
  # (ver `ConsolidacaoMensalService`), sem precisar estar vinculado a um
  # `CalculoDiario` específico — paridade com o comentário de topo do bean
  # legado, que descreve os casos de uso reais:
  # - CREDITO_POR_DESCONTO_EM_FOLHA: horas descontadas em folha viram
  #   crédito no banco de horas (o frequentador deixa de "dever" aquelas
  #   horas).
  # - CREDITO_POR_TRABALHO_EXCEPCIONAL: `CalculoDiario` não contabiliza
  #   trabalho em dias com meta_segundos == 0 (ex: fim de semana/feriado);
  #   este retificador cobre o frequentador que trabalhou nesses dias e
  #   teve a contabilização requerida manualmente.
  # - CREDITO_POR_DEBITO_INDEVIDO / DEBITO_POR_CREDITO_INDEVIDO: correção de
  #   um lançamento indevido anterior (crédito indevido vira débito de
  #   estorno, e vice-versa).
  # - CREDITO_POR_DEBITO_EM_OUTRO_MES / DEBITO_POR_CREDITO_EM_OUTRO_MES: par
  #   usado pra transferir saldo entre meses (débita de um mês, credita em
  #   outro).
  # - DEBITO_PARA_COMPENSACAO: débito manual pra fins de compensação.
  #
  # Decisão de design — `responsavel` opcional: o bean legado tem
  # `responsavel` (`User`) obrigatório na prática (sempre o admin logado que
  # registrou o retificador pela tela). O Frequencia ainda não tem uma tela
  # admin pra isso (fora de escopo desta task — só a estrutura de dados e o
  # service) nem um conceito consolidado de "usuário logado" fácil de amarrar
  # aqui fora de um controller. Optado por `belongs_to :responsavel,
  # optional: true` — permite popular via console/seed/task administrativa
  # sem exigir um usuário admin artificial, e a tela futura (fora desta task)
  # pode torná-lo obrigatório na camada de formulário sem quebrar o schema.
  #
  # Decisão de design — sem `momento_registro` duplicado: o bean legado tem
  # `momentoRegistro` (default "agora" no construtor) só porque o JPA da
  # época não expunha automaticamente um equivalente a `created_at`. No
  # Rails, `created_at` (timestamps padrão) já cobre exatamente esse
  # propósito — duplicar um segundo campo só pra guardar o mesmo instante
  # seria redundância sem ganho. Onde o legado usaria `momentoRegistro`, use
  # `created_at`.
  belongs_to :user
  belongs_to :responsavel, class_name: "User", optional: true

  # Portado de `TipoRetificadorEnum.java` — 7 valores, cada um com um fator
  # de multiplicação (+1 crédito, -1 débito) aplicado a
  # `segundos_a_retificar` na hora de somar no `retificado` do
  # `RegistroMensalFrequencia` (ver `ConsolidacaoMensalService`). Mesmo
  # padrão de constantes de tipo já usado em `RegimeFrequentador::TIPOS_DISPONIVEIS`.
  CREDITO_POR_DESCONTO_EM_FOLHA = "CREDITO_POR_DESCONTO_EM_FOLHA"
  CREDITO_POR_TRABALHO_EXCEPCIONAL = "CREDITO_POR_TRABALHO_EXCEPCIONAL"
  CREDITO_POR_DEBITO_INDEVIDO = "CREDITO_POR_DEBITO_INDEVIDO"
  DEBITO_POR_CREDITO_INDEVIDO = "DEBITO_POR_CREDITO_INDEVIDO"
  CREDITO_POR_DEBITO_EM_OUTRO_MES = "CREDITO_POR_DEBITO_EM_OUTRO_MES"
  DEBITO_POR_CREDITO_EM_OUTRO_MES = "DEBITO_POR_CREDITO_EM_OUTRO_MES"
  DEBITO_PARA_COMPENSACAO = "DEBITO_PARA_COMPENSACAO"

  TIPOS_DISPONIVEIS = [
    CREDITO_POR_DESCONTO_EM_FOLHA,
    CREDITO_POR_TRABALHO_EXCEPCIONAL,
    CREDITO_POR_DEBITO_INDEVIDO,
    DEBITO_POR_CREDITO_INDEVIDO,
    CREDITO_POR_DEBITO_EM_OUTRO_MES,
    DEBITO_POR_CREDITO_EM_OUTRO_MES,
    DEBITO_PARA_COMPENSACAO
  ].freeze

  TIPOS_LABELS = {
    CREDITO_POR_DESCONTO_EM_FOLHA => "Crédito por desconto em folha",
    CREDITO_POR_TRABALHO_EXCEPCIONAL => "Crédito por trabalho excepcional",
    CREDITO_POR_DEBITO_INDEVIDO => "Crédito por débito indevido",
    DEBITO_POR_CREDITO_INDEVIDO => "Débito por crédito indevido",
    CREDITO_POR_DEBITO_EM_OUTRO_MES => "Crédito recebido de outro mês",
    DEBITO_POR_CREDITO_EM_OUTRO_MES => "Crédito enviado para outro mês",
    DEBITO_PARA_COMPENSACAO => "Débito para compensação"
  }.freeze

  FATOR_MULTIPLICACAO = {
    CREDITO_POR_DESCONTO_EM_FOLHA => 1,
    CREDITO_POR_TRABALHO_EXCEPCIONAL => 1,
    CREDITO_POR_DEBITO_INDEVIDO => 1,
    DEBITO_POR_CREDITO_INDEVIDO => -1,
    CREDITO_POR_DEBITO_EM_OUTRO_MES => 1,
    DEBITO_POR_CREDITO_EM_OUTRO_MES => -1,
    DEBITO_PARA_COMPENSACAO => -1
  }.freeze

  validates :ano, presence: true
  validates :mes, presence: true, inclusion: { in: 1..12 }
  validates :tipo, presence: true, inclusion: { in: TIPOS_DISPONIVEIS }
  validates :segundos_a_retificar, presence: true

  # Portado de `getFatorMultiplicacao` (`TipoRetificadorEnum.java`) — usado
  # por `ConsolidacaoMensalService` pra somar `segundos_a_retificar * fator`
  # no `retificado` do `RegistroMensalFrequencia`.
  def fator_multiplicacao
    FATOR_MULTIPLICACAO.fetch(tipo)
  end

  # Soft-delete (paridade com `excluido` do bean legado) — nunca `destroy`
  # real, mesmo espírito de `RegistroMensalFrequencia#finalizar!`/`#reabrir!`.
  # Um retificador excluído deixa de entrar na soma de
  # `ConsolidacaoMensalService`, mas o registro permanece pra auditoria.
  def excluir!
    update!(excluido: true)
  end
end
