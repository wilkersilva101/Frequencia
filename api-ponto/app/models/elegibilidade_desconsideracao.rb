# Tarefa 29.5 (Sprint 29) — regra de elegibilidade para DESCONSIDERAR um dia
# de frequência. Porta, para o Frequencia, o gate do legado
# `RegistroFrequenciaServices.podeDesconsiderarFrequencia(usuario, dia)`
# (`intranet/src/modules/presenca/services/RegistroFrequenciaServices.java:91-108`).
#
# É um PORO (Plain Old Ruby Object) de CONSULTA/decisão — mesmo padrão do
# `AutorizacaoFrequencia` da 29.4: NÃO altera a `Ability` (isso é a 29.7), NÃO
# altera o motor de cálculo e NÃO acopla o model `TimeRecord` à autorização. O
# contrato para a tela da 29.7 é: consultar `pode_desconsiderar?` ANTES de
# chamar `TimeRecord#desconsiderar!`. Hoje não há caller de produção (o fluxo
# `desconsiderar!` existe desde a Sprint 19, mas nenhum controller/rota/view o
# chama — medido: `grep` em `app/controllers/`, `app/views/`, `config/routes.rb`
# = zero); a regra fica pronta para quando a 29.7 expuser o fluxo.
#
# As cinco cláusulas do legado, na ordem (traduzidas de `podeDesconsiderarFrequencia`):
#   1. o dia tem registros (`dia.getRegistros().size() > 0`);
#   2. não é meta-zero (`dia.getCalculo().getMeta() == 0`);
#   3. não é falta (`isFalta()`) — no Frequencia: `calculo.falta`;
#   4. não é falta compensada / a descontar / descontado em folha
#      (`isFaltaCompensada() || isFaltaADescontar() || isDescontadoEmFolha()`);
#   5. nenhum registro do dia já foi desconsiderado (o loop em
#      `dia.getRegistros()`: `getHorario()` vazio, ou diferente de
#      `Horario.DESCONSIDERADO`);
#   6. o acionador é gestor do ÓRGÃO do alvo — passo 5 da cascata da 29.4
#      (`usuario.isGestorOrgao(...)`). Decisão D5 (CTO, 2026-10-01): SÓ o passo
#      5 — `GestorIndividual` (passo 4) VÊ mas NÃO desconsidera;
#   7. o acionador NÃO desconsidera o próprio ponto (`!gestorEhMesmoFrequentador`).
#
# ⚠️ CLÁUSULAS EFETIVAS HOJE (medido — ver relatório): hoje o cálculo diário
# (`CalculoDiarioService`, `app/services/calculo_diario_service.rb:23-25`) só
# preenche `falta` e `meta_segundos`; `falta_a_descontar`, `falta_compensada` e
# `descontado_em_folha` ficam no default `false` (pertencem à consolidação
# mensal, Sprint 17 — não implementada). Logo, no estado atual do motor, as
# cláusulas 4 (esses três campos) NUNCA bloqueiam sozinhas — são código morto
# até a consolidação mensal passar a preenchê-los. A regra é implementada fiel
# às cinco cláusulas (o dia em que o motor preencher os campos, ela já vale),
# mas a cobertura de teste desses três ramos prova o gate do PORO (com um
# `CalculoDiario` montado à mão), NÃO o comportamento do motor — que hoje não
# produz esse estado. A diferença é declarada, não escondida.
#
# Regras transversais (herdadas da 29.4):
#   - D8 (CTO, 2026-09-29): o caminho de leitura NUNCA chama `valid?`.
#   - Fail-closed: usuário/alvo/data ausente, `Dia` sem cálculo, ou Pessoas
#     indisponível no passo 5 → negação (não é `true` por default).
#   - A identidade do auto-bloqueio é medida por FREQUENTADOR (fiel ao
#     `gestorEhMesmoFrequentador` do legado), não só `User`/CPF — ver
#     `mesmo_frequentador?`.
class ElegibilidadeDesconsideracao
  def initialize(acionador)
    @acionador = acionador
  end

  # @param frequentador [User] alvo (dono do ponto) — SEMPRE um `User` local.
  # @param data [Date, Time, String] o dia avaliado
  # @return [Boolean] `true` sse o acionador pode desconsiderar o dia
  #
  # ── CONTRATO ESTRITO A `User` (fix do débito D1, 2026-10-02) ────────────────
  # O alvo tem de ser um `User`. `Dia#registros` chama `user.time_records`
  # (`app/models/dia.rb:44`) e SÓ `User` tem essa associação — `Pessoas::Pessoa`
  # NÃO tem (`app/models/pessoas/pessoa.rb`), então `Dia.para(pessoa, data)
  # .registros` levanta `NoMethodError`. A documentação anterior anunciava
  # `[User, Pessoas::Pessoa]`: era um CONTRATO FALSO, contradito pelo próprio
  # código do auto-bloqueio (que antecipa `alvo.is_a?(User)`).
  #
  # Por que estreitar (e não aceitar `Pessoa` e negar): o alvo REAL do fluxo da
  # 29.7 NÃO é um `Pessoas::Pessoa`. A listagem da 29.6 resolve terceirizado
  # por VÍNCULO e devolve `Pessoas::Vinculo` (readonly); o fluxo de
  # desconsiderar parte do registro a desconsiderar, que por natureza é um
  # `TimeRecord` de um `User` (a FK `time_records.user_id` aponta para `users`,
  # não para `pessoas`). Nenhum chamador legítimo tem um `Pessoas::Pessoa` em
  # mãos para passar aqui — mas um contrato amplo CONVIDARIA o próximo agente a
  # tentar. O fail-closed abaixo torna a entrada errada explícita e auditável.
  #
  # Há UM caminho interno em que um objeto com `cpf` (inclusive
  # `Pessoas::Pessoa`) é legítimo: a resolução de identidade
  # (`mesmo_frequentador?` → `frequentador_de`), que só lê `cpf`. Mas ele só é
  # alcançado DEPOIS do guard abaixo — no método público, um não-`User` nunca
  # chega lá.
  def pode_desconsiderar?(frequentador, data)
    # Fail-closed de entrada: sem acionador, sem alvo, sem data não há
    # autorização possível.
    return false if acionador.blank?
    return false if frequentador.nil?
    return false if data.blank?

    # D1: alvo que não é `User` é RECUSADO explicitamente. Sem este guard, a
    # entrada errada estourava `NoMethodError` em `Dia#registros` — e, com
    # acionador nulo, era MASCARADA pelo guard acima (devolvia `false` sem
    # tocar o alvo), de modo que o contrato falso só se manifestava num caminho
    # específico. O log torna a armadilha visível: um chamador que passar
    # `Pessoas::Pessoa`/`Pessoas::Vinculo` não tem `time_records` (a FK aponta
    # para `users`), então não existe dia a avaliar.
    unless frequentador.is_a?(User)
      Rails.logger.warn(
        evento: "elegibilidade_desconsideracao.alvo_nao_user",
        classe_alvo: frequentador.class.name,
        acionador_id: acionador.id
      )
      return false
    end

    dia = Dia.para(frequentador, data)

    return false if dia.registros.empty?

    calculo = dia.calculo
    # `dia.calculo` é `nil` até o motor de cálculo rodar para o dia. O legado
    # assume um `CalculoDiario` existente (`dia.getCalculo().getMeta()`); sem
    # cálculo não há como provar a elegibilidade → fail-closed.
    return false if calculo.nil?

    return false if calculo.meta_segundos.to_i.zero?
    return false if calculo.falta?
    return false if calculo.falta_compensada? || calculo.falta_a_descontar? || calculo.descontado_em_folha?

    # Cláusula 5 (loop do legado): um dia com QUALQUER registro já desconsiderado
    # não pode ser desconsiderado de novo. Portado de `!registro.getHorario().
    # equals(Horario.DESCONSIDERADO)` — no Frequencia a marcação é a própria
    # coluna `desconsiderado`.
    return false if dia.registros.any?(&:desconsiderado?)

    # Cláusula 7 — auto-bloqueio por identidade de FREQUENTADOR. Vem ANTES de
    # resolver a hierarquia (que pode consultar o banco do Pessoas): o
    # auto-bloqueio é a checagem mais barata e a mais sensível.
    return false if mesmo_frequentador?(frequentador)

    # Cláusula 6 — acionador é gestor do órgão do alvo (passo 5 da cascata).
    # D5: NÃO é `pode_ver?` — só a hierarquia desconsidera.
    AutorizacaoFrequencia.new(acionador).gestor_de_orgao_do?(frequentador)
  end

  private

  attr_reader :acionador

  # Fiel a `gestorEhMesmoFrequentador` do legado
  # (`RegistroFrequenciaServices.java:104`): o auto-bloqueio compara o
  # FREQUENTADOR do acionador com o FREQUENTADOR do cálculo do dia — dois ids
  # no espaço de `Frequentador` do legado, NÃO um par `User`/CPF.
  #
  # No Frequencia o acionador é sempre um `User` local (tem login — ele age
  # pela aplicação) e o alvo também é SEMPRE um `User` local (contrato D1 —
  # ver `pode_desconsiderar?`). A identidade de frequentador do acionador é
  # resolvida pela ponte `FrequentadorCache`, que espelha o `Frequentador` do
  # Intranet e se liga ao `User` pelo CPF (`User#frequentador_cache`,
  # `has_one ... foreign_key: :cpf`).
  #
  # Comparação em dois níveis, do mais forte ao mais fraco:
  #   (a) MESMO OBJETO/registro `User` (mesmo id): é o próprio ponto, sem
  #       ambiguidade — cobre o acionador que é um `User` sem CPF.
  #   (b) MESMO FREQUENTADOR do Intranet: o `FrequentadorCache` do acionador e
  #       o do alvo são o mesmo registro. Isto captura o caso em que acionador
  #       e alvo são `User` DIFERENTES mas representam o MESMO frequentador do
  #       Intranet — exatamente o que `gestorEhMesmoFrequentador` mede e que
  #       uma comparação só por `User`/CPF deixaria passar.
  #
  # `frequentador_de` funciona para qualquer objeto com `cpf` (é o que o ramo
  # (b) faz), mas no fluxo público da classe o alvo já passou pelo guard de
  # `User` — a resolução por CPF serve para capturar identidades que um
  # `User.id` sozinho não captura.
  #
  # Quando o acionador é um magistrado/servidor que NÃO é frequentador
  # (`frequentador_do_acionador` nulo — o `frequentadorDoGestor == null` do
  # legado), o auto-bloqueio NÃO se aplica: o legado só checa
  # `gestorEhMesmoFrequentador` no ramo em que o gestor TAMBÉM é frequentador.
  def mesmo_frequentador?(alvo)
    # (a) mesmo registro `User` — é literalmente o próprio ponto, sem
    # ambiguidade. Vem antes do ramo "magistrado" de propósito: mirar a si
    # mesmo nunca deve ser permitido, mesmo para um acionador que não é
    # frequentador (endurece o legado num caso que ele não cobre).
    return true if alvo.is_a?(User) && acionador.id.present? && alvo.id == acionador.id

    # Ramo "magistrado" do legado (`frequentadorDoGestor == null`): o acionador
    # NÃO é um frequentador, então não há auto-bloqueio a aplicar. Só o ramo em
    # que o gestor TAMBÉM é frequentador checa `gestorEhMesmoFrequentador`.
    return false if frequentador_do_acionador.nil?

    # (b) mesmo `Frequentador` do Intranet (ponte pelo CPF).
    frequentador_do_alvo = frequentador_de(alvo)
    frequentador_do_alvo.present? &&
      frequentador_do_alvo.id == frequentador_do_acionador.id
  end

  # `Frequentador` do Intranet correspondente ao acionador (o
  # `FrequentadorDoGestor` do legado). `nil` quando o acionador não é um
  # frequentador (sem CPF ou sem espelho local) — o ramo "magistrado".
  def frequentador_do_acionador
    return @frequentador_do_acionador if defined?(@frequentador_do_acionador)

    @frequentador_do_acionador = frequentador_de(acionador)
  end

  # `Frequentador` do Intranet correspondente a um objeto com CPF (o alvo).
  # A ponte é o CPF (`FrequentadorCache` é keyed por CPF, ver
  # `FrequentadorCache.find_by_user`), então funciona tanto para um `User`
  # quanto para um `Pessoas::Pessoa` — e é fiel ao `Frequentador` do legado,
  # que é resolvido do mesmo modo. `nil` quando não há CPF/espelho.
  def frequentador_de(subject)
    cpf = normalizar_cpf(subject&.cpf)
    return nil if cpf.blank?

    FrequentadorCache.find_by(cpf: cpf)
  end

  # Mesmo formato de CPF dos demais models (`/\A\d{11}\z/`).
  def normalizar_cpf(valor)
    valor.to_s.gsub(/\D/, "").presence
  end
end
