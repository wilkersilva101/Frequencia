# Tarefa 29.4 (Sprint 29) — cascata de autorização de visualização de
# frequência (PRD — regra central de autorização, seção 3; PRD-REGRAS-NEGOCIO
# §3). Porta, para o Frequencia, a regra do legado
# `RegistroFrequenciaValidator.frequentador`: a PRIMEIRA condição que casar
# libera; se nada casar até a raiz da árvore, nega.
#
# É um PORO (Plain Old Ruby Object) de CONSULTA — não altera a `Ability` (isso
# é a 29.7). Nesta tarefa ele apenas LÊ roles e dados; a atribuição das 11
# roles legadas é Sprint 30. Ver Decisão D1 do CTO (2026-09-29).
#
# Ordem dos passos (primeiro match vence), idêntica à do legado:
#   1. próprio           (o alvo é o próprio usuário logado — id ou CPF)
#   2. role_geral        (admin OU role `visualiza_frequentadores`)
#   3. terceirizado      (role `visualiza_terceirizados` E alvo TERCEIRIZADO)
#   4. gestor_individual (vínculo ATIVO de GestorIndividual cujo gestor é o
#                         usuário logado — ADR-0008/29.3-D1)
#   5. hierarquia        (usuário é gestor atual/substituto/excepcional de
#                         alguma unidade ELEGÍVEL na cadeia ascendente da
#                         lotação principal vigente do alvo — regra D6)
#   6. :negado           (nada casou)
#
# Regras transversais:
#   - D8 (CTO, 2026-09-29): o caminho de leitura NUNCA chama `valid?`. Um
#     registro válido-no-banco/inválido-no-model faz `valid?` levantar
#     `RecordInvalid` e derrubar a renderização. Aqui só há `where`/`exists?`/
#     associações.
#   - Bug 16 / ADR-0008: os geridos são lidos via
#     `GestorIndividualGerenciado.ativos.where(...)` — nunca
#     `GestorIndividual#gerenciados` cru (que não filtra ativos nem usa o
#     índice parcial).
#   - Fail-closed: usuário/alvo ausente, ou Pessoas indisponível nos passos que
#     dependem dele (3 e 5), resulta em negação com log.
class AutorizacaoFrequencia
  # Motivos possíveis do primeiro match (auditoria — critério 9 da 29.4).
  MOTIVOS = %i[proprio role_geral terceirizado gestor_individual hierarquia negado].freeze

  def initialize(usuario)
    @usuario = usuario
    @decisoes = {}
  end

  # Critério 8 da 29.4: avalia na ordem e retorna no primeiro match.
  def pode_ver?(frequentador)
    @frequentador = frequentador
    motivo(frequentador) != :negado
  end

  # Critério 9: além do booleano, o MOTIVO do match (ou `:negado`) para
  # auditoria/shadow mode da 29.7.
  def motivo(frequentador)
    chave = frequentador.nil? ? :nil : frequentador.object_id
    @decisoes.fetch(chave) { @decisoes[chave] = decidir(frequentador) }
  end

  # Tarefa 29.5 (Decisão D5, CTO 2026-10-01) — expõe APENAS o passo 5
  # (hierarquia) como predicado público, para que a regra de elegibilidade
  # para DESCONSIDERAR um dia
  # (`ElegibilidadeDesconsideracao#pode_desconsiderar?`) reuse a MESMA
  # implementação da hierarquia em vez de reimplementá-la (o ruling D5 diz
  # explicitamente: "a 29.5 reusa o mesmo passo 5 da 29.4 — não reimplementa").
  #
  # É deliberadamente RESTRITO ao passo 5: NÃO é `pode_ver?`. O legado trata
  # ver e desconsiderar como regras DISTINTAS — `GestorIndividual` (passo 4)
  # VÊ mas NÃO desconsidera; admin/role geral (passo 2) e próprio (passo 1)
  # também não passam pelo gate de desconsiderar (que só chama `isGestorOrgao`).
  # Usar `pode_ver?` aqui AMPLIARIA a autorização — exatamente o erro que a D5
  # veda. Só a hierarquia (ser gestor do órgão do alvo) autoriza.
  #
  # Usa só o passo 5 da cascata (mesma resolução de lotação principal vigente,
  # `Pessoas::Lotacao.principais.vigentes`, e mesma regra D6 de elegibilidade
  # da unidade) — nenhuma lógica nova de hierarquia.
  def gestor_de_orgao_do?(frequentador)
    @frequentador = frequentador
    reset_estado_do_alvo!

    return false if usuario.blank?
    return false if frequentador.nil?

    hierarquia?
  end

  private

  attr_reader :usuario

  # O memo do alvo (`@alvo_pessoa`, `@alvo_user_id`, `@cpf_do_alvo`) depende de
  # qual alvo está sendo avaliado — limpo a cada `decidir` para que reusar a
  # mesma instância em alvos diferentes não devolva o motivo do anterior.
  def reset_estado_do_alvo!
    remove_instance_variable(:@alvo_pessoa) if defined?(@alvo_pessoa)
    remove_instance_variable(:@alvo_user_id) if defined?(@alvo_user_id)
    remove_instance_variable(:@cpf_do_alvo) if defined?(@cpf_do_alvo)
  end

  def decidir(frequentador)
    @frequentador = frequentador
    reset_estado_do_alvo!

    # Fail-closed: sem usuário logado não há autorização possível.
    return :negado if usuario.blank?
    # Fail-closed: alvo ausente.
    return :negado if frequentador.nil?

    return :proprio if proprio?
    return :role_geral if role_geral?
    return :terceirizado if terceirizado?
    return :gestor_individual if gestor_individual?
    return :hierarquia if hierarquia?

    :negado
  end

  # --- passo 1: o alvo é o próprio usuário logado ---------------------------

  # Legado: `userPersist.getLogin().equals(user.getLogin())`. No Frequencia a
  # identidade é o id local do `User` e/ou o CPF (ponte com o Pessoas).
  def proprio?
    return true if alvo_user_id.present? && alvo_user_id == usuario.id
    return false if cpf_do_usuario.blank?

    cpf_do_usuario == cpf_do_alvo
  end

  # --- passo 2: role geral (ou admin) ---------------------------------------

  # `admin` é o ÚNICO curto-circuito deste passo (`user.admin? ||
  # user.has_role?(:admin)`, idêntico ao `admin?` privado da `Ability`).
  # `visualiza_frequentadores` sozinha vê TODOS os alvos e tem precedência
  # sobre `visualiza_terceirizados` (o `return` do primeiro match do legado).
  def role_geral?
    admin? || usuario.has_role?(:visualiza_frequentadores)
  end

  # --- passo 3: role de terceirizados + alvo TERCEIRIZADO -------------------

  # `visualiza_terceirizados` sozinha vê APENAS alvos TERCEIRIZADOS (Decisão
  # D1). Quem tem a role geral já retornou no passo 2.
  def terceirizado?
    return false unless usuario.has_role?(:visualiza_terceirizados)

    alvo_pessoa&.terceirizado? || false
  end

  # --- passo 4: GestorIndividual ativo vinculado ----------------------------

  # ADR-0008/29.3-D1: o estado canônico do vínculo é o do PAR
  # (`gestor_individual_gerenciados.ativo`); o `ativo` do gestor é projeção
  # ("existe ≥1 vínculo ativo"), consequência automática do uso de `.ativos`.
  # Bug 16: consumir via o escopo `.ativos` aciona o índice UNIQUE parcial.
  #
  # Identidade do gestor: login local (`gestor_user_id`) quando houver, e a
  # ponte `gestor_cpf` como fallback (o gestor do Intranet pode ter sido
  # importado sem login — 29.3).
  def gestor_individual?
    return false if alvo_user_id.nil?

    escopo = GestorIndividualGerenciado.ativos
      .joins(:gestor_individual)
      .where(user_id: alvo_user_id)

    if usuario.id.present? &&
       escopo.where(gestores_individuais: { gestor_user_id: usuario.id }).exists?
      return true
    end

    return false if cpf_do_usuario.blank?

    escopo.where(gestores_individuais: { gestor_cpf: cpf_do_usuario }).exists?
  end

  # --- passo 5: hierarquia (cadeia ascendente da lotação principal) ---------

  # Sobe a cadeia da lotação principal vigente do alvo e checa se o usuário é
  # gestor atual/substituto/excepcional de alguma unidade ELEGÍVEL (D6).
  #
  # A CADEIA sobe inteira mesmo por unidades ausentes/inativas/extintas (o path
  # é a fonte da estrutura); o que a inelegibilidade muda é que uma unidade
  # inelegível NÃO libera pelos seus gestores — inclusive a própria unidade de
  # lotação do alvo.
  def hierarquia?
    unidade = unidade_da_lotacao_principal_vigente
    return false if unidade.nil?

    pessoa = pessoa_do_usuario
    return false if pessoa.nil?

    houve_unidade_inelegivel_com_gestor = false

    unidade.cadeia_ascendente.each do |no|
      next unless no.gestor?(pessoa)

      return true if no.elegivel?

      houve_unidade_inelegivel_com_gestor = true
    end

    log_unidade_inelegivel(unidade) if houve_unidade_inelegivel_com_gestor
    false
  end

  # --- resolução de dados do Pessoas (readonly) -----------------------------

  # Pessoa do Pessoas correspondente ao alvo. `nil` quando o alvo não tem CPF,
  # não existe no Pessoas, ou o Pessoas está indisponível (fail-closed).
  def alvo_pessoa
    return @alvo_pessoa if defined?(@alvo_pessoa)

    @alvo_pessoa =
      if @frequentador.is_a?(Pessoas::Pessoa)
        @frequentador
      else
        resolver_pessoa_por_user(@frequentador, papel: :alvo)
      end
  end

  # Pessoa do Pessoas do usuário LOGADO — usada só no passo 5 (identidade de
  # gestor). `nil` se o usuário não tem CPF, não existe no Pessoas, ou o
  # Pessoas está indisponível.
  def pessoa_do_usuario
    return @pessoa_do_usuario if defined?(@pessoa_do_usuario)

    @pessoa_do_usuario = resolver_pessoa_por_user(usuario, papel: :usuario)
  end

  # Wrapper de `Pessoas::Pessoa.por_user` com as duas guardas pedidas no review
  # da 29.1 (MEDIUM-3 + débito do log) e o fail-closed da D6:
  #   - CPF presente mas sem pessoa correspondente → `warn` (auditoria: um
  #     gestor que "deveria" existir no Pessoas e não existe é invisível sem
  #     isso);
  #   - falha de conexão/consulta no Pessoas → `warn` e `nil` (nega, não
  #     derruba a request).
  def resolver_pessoa_por_user(subject, papel:)
    cpf = normalizar_cpf(subject&.cpf)
    return nil if cpf.blank?

    pessoa = Pessoas::Pessoa.por_user(subject)

    if pessoa.nil?
      Rails.logger.warn(
        evento: "autorizacao_frequencia.pessoa_ausente",
        papel: papel, cpf: cpf
      )
    end

    pessoa
  rescue ActiveRecord::ActiveRecordError, PG::Error => e
    Rails.logger.warn(
      evento: "autorizacao_frequencia.pessoas_indisponivel",
      papel: papel, cpf: cpf,
      erro: e.class.name, mensagem: e.message
    )
    nil
  end

  # Unidade da lotação principal vigente do alvo — o ponto de partida da subida
  # do passo 5. Considera TODOS os vínculos ativos do alvo e pega a lotação
  # principal vigente mais recente (o espelho não materializa
  # `vinculo_principal`; ver D4). `nil` quando não há lotação vigente — nesse
  # caso o passo 5 não se aplica (só valem os passos 1–4).
  def unidade_da_lotacao_principal_vigente
    pessoa = alvo_pessoa
    return nil if pessoa.nil?

    Pessoas::Lotacao.principais
      .merge(Pessoas::Lotacao.vigentes)
      .where(vinculo_id: pessoa.vinculos_ativos.select(:id))
      .order(inicio: :desc)
      .includes(:unidade)
      .first
      &.unidade
  rescue ActiveRecord::ActiveRecordError, PG::Error => e
    Rails.logger.warn(
      evento: "autorizacao_frequencia.pessoas_indisponivel",
      papel: :lotacao, erro: e.class.name, mensagem: e.message
    )
    nil
  end

  # --- identidade do alvo ---------------------------------------------------

  # Só um `User` local tem id no espaço de `user_id` (FK de
  # `gestor_individual_gerenciados` e do passo 1). Um alvo `Pessoas::Pessoa`
  # tem id em OUTRO espaço — comparar por id ali seria um falso-positivo.
  def alvo_user_id
    return @alvo_user_id if defined?(@alvo_user_id)

    @alvo_user_id = @frequentador.is_a?(User) ? @frequentador.id : nil
  end

  def cpf_do_alvo
    return @cpf_do_alvo if defined?(@cpf_do_alvo)

    @cpf_do_alvo = normalizar_cpf(@frequentador&.cpf)
  end

  def cpf_do_usuario
    return @cpf_do_usuario if defined?(@cpf_do_usuario)

    @cpf_do_usuario = normalizar_cpf(usuario&.cpf)
  end

  # --- utilidades -----------------------------------------------------------

  # Espelha `Pessoas::Pessoa.por_user`: CPF sem máscara. Mantido aqui para o
  # passo 1 (identidade própria) e o passo 4 (ponte `gestor_cpf`) usarem o
  # mesmo formato do `User` (`/\A\d{11}\z/`).
  def normalizar_cpf(valor)
    valor.to_s.gsub(/\D/, "").presence
  end

  # Dupla fonte de verdade durante a transição (coluna booleana `admin` × role
  # Rolify `:admin`) — idêntica ao `admin?` privado da `Ability`.
  def admin?
    usuario.admin? || usuario.has_role?(:admin)
  end

  # Detalhe de auditoria da D6: negação em que a ÚNICA unidade com gestor
  # correspondente era inelegível (inativa/extinta). Alimenta o shadow da
  # 29.7/29.8.
  def log_unidade_inelegivel(unidade)
    Rails.logger.warn(
      evento: "autorizacao_frequencia.unidade_inelegivel",
      unidade_id: unidade.id,
      motivo: :unidade_inelegivel,
      usuario_id: usuario.id
    )
  end
end
