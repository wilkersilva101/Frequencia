# Tarefa 29.6 (Sprint 29) — lista de frequentadores VISÍVEIS por um usuário
# (PRD §3; §9 item 1). É o IRMÃO SQL do PORO `AutorizacaoFrequencia`
# (task 29.4): o PORO responde por UM alvo (`pode_ver?`), e este object
# responde pela LISTA inteira (scope SQL), para alimentar
# `accessible_by`/listagens/relatórios sem vazar registros por paginação.
#
# ⚠️ Contrato de equivalência (critério da 29.6): para TODO par
# (usuário, frequentador) a lista devolvida aqui contém o frequentador sse
# `AutorizacaoFrequencia.new(usuario).pode_ver?(frequentador)` é `true`. A
# prova é o teste de propriedade em `test/models/frequentadores_visiveis_test.rb`.
# A FONTE DA VERDADE da regra é o PORO da 29.4 — este arquivo NÃO inventa
# semântica: ele REPLICA a cascata de 5 passos em SQL.
#
# ── Limite estrutural (leia antes de "melhorar") ────────────────────────────
# `users` (banco primário) e `pessoas`/`vinculos` (banco espelho do Pessoas)
# são bancos Postgres DISTINTOS (ver `config/database.yml`): não há JOIN
# cross-database. Por isso os passos que dependem de `users` (1 próprio e 4
# gestor individual) são resolvidos NESTE ARQUIVO, em Ruby, contra o banco
# primário, e o resultado (a lista de CPFs dos alvos) entra no SQL como um
# `IN (...)` literal. Os passos que vivem no Pessoas (3 terceirizado e 5
# hierarquia) viram SQL puro sobre `vinculos`. A regra de negócio permanece
# em UM só lugar (`condicoes_liberacao`); os mini-fragmentos de leitura de
# `users` são análogos aos do PORO (passos 1 e 4), não uma segunda regra.
#
# ── Fail-closed (espelha o PORO) ────────────────────────────────────────────
# Usuário nulo → lista vazia. Alvo/pessoa ausente, path corrompido ou
# Pessoas indisponível → a condição daquele passo não casa (nenhum acesso).
#
# Auditoria/shadow (débito D2, 2026-10-02): o PORO da 29.4 LOGA as NEGAÇÕES
# (`pessoa_ausente`, `pessoas_indisponivel`, `unidade_inelegivel`) — e só elas:
# não há log de concessão. O scope logava ZERO, então o shadow mode da 29.7
# (que observa negações antes de ligar a flag) veria METADE do sistema: a
# listagem, que serve as telas, era cega. Aqui o scope emite os MESMOS
# eventos/formatos do PORO, mas de forma AGREGADA — uma vez por chamada, nunca
# por linha: o scope devolve N vínculos, e um `warn` por alvo negado inflaria o
# log proporcionalmente ao universo de frequentadores. Ver `log_negacoes`.
#
# ── D6 replicada (unidade inelegível não libera; ausente não interrompe) ────
# A cadeia do alvo é lida do `ancestry` persistido (o path é a fonte da
# estrutura). Unidade INELEGÍVEL (`active` falso ou extinta) não libera pelos
# seus gestores — inclusive a própria unidade de lotação do alvo. Ancestral
# AUSENTE (id no path sem registro) é pulado e a subida CONTINUA (o JOIN
# simplesmente não acha a unidade). Path CORROMPIDO (formato inválido,
# auto-referência, id repetido) fecha em fail-closed: só a própria unidade
# conta — idêntico a `Pessoas::Unidade#cadeia_ascendente`.
class FrequentadoresVisiveis
  # Decisão D4 do CTO (2026-09-29): TERCEIRIZADO é o TIPO de vínculo
  # (`tipos_vinculo.nome`), nunca a categoria eSocial. Idêntico a
  # `Pessoas::Vinculo#terceirizado?`.
  TIPO_TERCEIRIZADO = "Terceirizado".freeze

  # Estado de vínculo "ativo" (espelha `Pessoas::Vinculo.ativos`).
  ESTADO_ATIVO = "em_exercicio".freeze

  # Ponto de entrada — devolve uma `ActiveRecord::Relation` de
  # `Pessoas::Vinculo` (o frequentador é um vínculo ativo com pessoa).
  def self.para(usuario)
    new(usuario).escopo
  end

  def initialize(usuario)
    @usuario = usuario
  end

  # Passo 2 do PORO: admin OU role `visualiza_frequentadores` → TODOS os
  # frequentadores (a role de terceirizados tem precedência menor e é
  # absorvida aqui, como no `return` do primeiro match do legado).
  def escopo
    return base.none if usuario.blank?

    # `.distinct` no resultado (critério da 29.6): a condição de hierarquia é
    # um EXISTS (não multiplica linhas), mas o filtro por CPF pode casar o
    # mesmo vínculo por mais de uma via (ex.: próprio ∪ gerido) e um LEFT
    # futuro não deve duplicar frequentadores na paginação.
    return base.distinct if role_geral?

    # D2: só o caminho NÃO-role-geral chega ao passo 5 do PORO; é lá que vivem
    # as negações auditadas (`pessoa_ausente`/`unidade_inelegivel`). Um usuário
    # `role_geral` curto-circuita no passo 2 para TODO alvo e o PORO não emite
    # negação nenhuma — emitir aqui seria log que o PORO nunca produz (e uma
    # query a mais). Emitimos uma vez por chamada, agregado.
    log_negacoes

    base.where(condicoes_liberacao).distinct
  end

  private

  attr_reader :usuario

  def base
    Pessoas::Vinculo.ativos.joins(:pessoa)
  end

  # --- passos 1 e 4 (banco primário: users/gestores_individuais) -------------

  # Passo 2 — `admin` é o único curto-circuito (idêntico ao `admin?` do PORO e
  # da `Ability`: coluna booleana OU role Rolify).
  def role_geral?
    admin? || usuario.has_role?(:visualiza_frequentadores)
  end

  def admin?
    usuario.admin? || usuario.has_role?(:admin)
  end

  # Passo 3 — a role sozinha só é significativa combinada com o tipo do alvo.
  def role_terceirizados?
    usuario.has_role?(:visualiza_terceirizados)
  end

  # Passo 1 (próprio) e passo 4 (gestor individual) reduzem-se a "quais CPFs
  # de alvo o usuário pode ver independentemente da hierarquia". O CPF é a
  # ponte entre o `User` local e o `Pessoas::Vinculo` (o frequentador).
  def cpfs_alvos
    @cpfs_alvos ||= ([ cpf_do_usuario ] + cpfs_dos_geridos).compact.uniq
  end

  def cpf_do_usuario
    @cpf_do_usuario ||= normalizar_cpf(usuario&.cpf)
  end

  # Passo 4 — geridos por `GestorIndividual` ATIVO (Bug 16/ADR-0008: sempre
  # via `GestorIndividualGerenciado.ativos`, que aciona o índice UNIQUE
  # parcial). Identidade do gestor: login local (`gestor_user_id`) quando
  # houver e a ponte `gestor_cpf` como fallback (29.3).
  def geridos_user_ids
    escopo = GestorIndividualGerenciado.ativos.joins(:gestor_individual)
    ids = []

    if usuario.id.present?
      ids |= escopo.where(gestores_individuais: { gestor_user_id: usuario.id }).pluck(:user_id)
    end
    if cpf_do_usuario.present?
      ids |= escopo.where(gestores_individuais: { gestor_cpf: cpf_do_usuario }).pluck(:user_id)
    end

    ids
  end

  # CPFs dos geridos. Só quem tem CPF existe como frequentador no Pessoas; um
  # `User` local sem CPF não tem pessoa/vínculo e não aparece na lista (é o
  # único ponto em que o conjunto de resultados do scope é menor que o do
  # PORO — documentado no teste de propriedade).
  def cpfs_dos_geridos
    ids = geridos_user_ids
    return [] if ids.empty?

    User.where(id: ids).where.not(cpf: nil).pluck(:cpf).map { |cpf| normalizar_cpf(cpf) }.compact
  end

  # --- montagem das condições de liberação -----------------------------------

  def condicoes_liberacao
    partes = []
    partes << "pessoas.cpf IN (#{lista_quoted(cpfs_alvos)})" if cpfs_alvos.any?
    if role_terceirizados?
      partes << "vinculos.configuracao_cadastro_id IN (#{subquery_tipos_terceirizado})"
    end
    partes << condicao_hierarquia if pessoa_do_usuario.present?

    return "1 = 0" if partes.empty?

    "(#{partes.join(' OR ')})"
  end

  # --- passo 5 (hierarquia) --------------------------------------------------

  # `pessoa` do usuário logado no Pessoas (identidade de gestor). `nil` quando
  # o usuário não tem CPF / não existe no Pessoas → passo 5 inaplicável,
  # idêntico ao PORO.
  def pessoa_do_usuario
    return @pessoa_do_usuario if defined?(@pessoa_do_usuario)

    @pessoa_do_usuario = Pessoas::Pessoa.por_user(usuario)
  rescue ActiveRecord::ActiveRecordError, PG::Error => e
    # Mesmo evento/formato do PORO (`resolver_pessoa_por_user`). Marca a falha
    # para que `log_ausencia` NÃO emita `pessoa_ausente` por cima — o PORO trata
    # `pessoa_ausente` e `pessoas_indisponivel` como mutuamente exclusivos
    # (ausência de registro × indisponibilidade do banco).
    Rails.logger.warn(
      evento: "autorizacao_frequencia.pessoas_indisponivel",
      papel: :usuario, cpf: cpf_do_usuario,
      erro: e.class.name, mensagem: e.message
    )
    @pessoas_indisponivel_usuario = true
    @pessoa_do_usuario = nil
  end

  # A condição de hierarquia: existe UMA lotação principal vigente da pessoa
  # do alvo (a mais recente, como no PORO) cuja UNIDADE cai na cadeia de
  # liberação. A subquery da lotação usa `vinculos.pessoa_id` para amarrar ao
  # alvo (correlação). Não usa CTE nem query por linha: é UMA condição SQL.
  def condicao_hierarquia
    ids = pessoa_ids_gestor
    return "1 = 0" if ids.empty?

    gerente = "un.gestor_id IN (#{lista_quoted(ids)}) OR " \
              "un.gestor_substituto_id IN (#{lista_quoted(ids)}) OR " \
              "un.gestor_excepcional_id IN (#{lista_quoted(ids)})"

    # Self: a própria unidade de lotação do alvo pode liberar — desde que
    # ELEGÍVEL (D6: vale também para a própria unidade de lotação).
    self_liberado = "(#{unidade_elegivel('un')} AND (#{gerente}))"

    # Ancestrais: pulados quando ausentes (o JOIN não acha a unidade), a
    # subida continua; a elegibilidade de cada ancestral é exigida (D6).
    ancestrais_liberados =
      "EXISTS (" \
        "SELECT 1 FROM unnest(string_to_array(un.ancestry, '/')::bigint[]) AS aid " \
        "JOIN unidades au ON au.id = aid " \
        "WHERE #{unidade_elegivel('au')} " \
        "AND (au.gestor_id IN (#{lista_quoted(ids)}) OR " \
        "au.gestor_substituto_id IN (#{lista_quoted(ids)}) OR " \
        "au.gestor_excepcional_id IN (#{lista_quoted(ids)})))"

    # Path corrompido → fail-closed: só o self conta.
    cadeia_liberada = "(#{self_liberado} OR (#{path_valido('un')} AND #{ancestrais_liberados}))"

    <<~SQL.squish
      EXISTS (
        SELECT 1
        FROM lotacoes lot
        JOIN vinculos vinc ON vinc.id = lot.vinculo_id
        JOIN vinculos_estados ve ON ve.id = vinc.vinculo_estado_id
        JOIN unidades un ON un.id = lot.unidade_id
        WHERE lot.principal IS TRUE
          AND (lot.fim IS NULL OR lot.fim >= CURRENT_DATE)
          AND vinc.pessoa_id = vinculos.pessoa_id
          AND ve.nome = '#{ESTADO_ATIVO}'
          AND (vinc.fim IS NULL OR vinc.fim >= CURRENT_DATE)
          AND lot.inicio = (
            SELECT MAX(lot2.inicio)
            FROM lotacoes lot2
            JOIN vinculos v2 ON v2.id = lot2.vinculo_id
            JOIN vinculos_estados ve2 ON ve2.id = v2.vinculo_estado_id
            WHERE lot2.principal IS TRUE
              AND (lot2.fim IS NULL OR lot2.fim >= CURRENT_DATE)
              AND v2.pessoa_id = vinculos.pessoa_id
              AND ve2.nome = '#{ESTADO_ATIVO}'
              AND (v2.fim IS NULL OR v2.fim >= CURRENT_DATE)
          )
          AND #{cadeia_liberada}
      )
    SQL
  end

  # Ids de `pessoas` que representam o usuário logado (identidade do gestor).
  def pessoa_ids_gestor
    @pessoa_ids_gestor ||= pessoa_do_usuario ? [ pessoa_do_usuario.id ] : []
  end

  # --- auditoria/shadow (D2): mesma semântica do PORO, agregada --------------

  # Emite os eventos de negação do PORO (`AutorizacaoFrequencia`) que são
  # observáveis numa chamada de conjunto, uma vez por chamada.
  def log_negacoes
    # `pessoa_do_usuario` (memo) resolve a identidade do gestor no Pessoas e é
    # consumida de qualquer modo na montagem das condições; chamá-la aqui NÃO
    # adiciona query — apenas antecipa a leitura e captura a negação.
    papel_usuario_ausente = pessoa_do_usuario.nil? && !@pessoas_indisponivel_usuario
    log_ausencia if papel_usuario_ausente
    log_unidades_inelegiveis
  end

  # Passo 5 — a pessoa do usuário logado não existe no Pessoas (CPF ausente do
  # espelho). Mesmo evento/formato do PORO (`resolver_pessoa_por_user`), papel
  # `:usuario` (é o gestor, não o alvo).
  def log_ausencia
    cpf = cpf_do_usuario
    return if cpf.blank?
    return unless pessoa_do_usuario.nil?

    Rails.logger.warn(
      evento: "autorizacao_frequencia.pessoa_ausente",
      papel: :usuario, cpf: cpf
    )
  end

  # Passo 5 / D6 — unidades de LOTAÇÃO dos alvos em que a cascata REALMENTE
  # chega ao passo 5 E a única unidade com gestor na cadeia é INELEGÍVEL. É a
  # mesma negação que o PORO registra em `log_unidade_inelegivel` (evento e
  # chave `unidade_id`), AGREGADA por chamada. Uma única query; nenhuma consulta
  # por alvo.
  #
  # FIDELIDADE DE PRECEDÊNCIA (fix do review, 2026-10-02): o PORO retorna no
  # PRIMEIRO match da cascata (`AutorizacaoFrequencia#motivo`) — um alvo
  # liberado pelos passos 1/2/3/4 NUNCA chega ao passo 5 e NUNCA loga. O
  # agregado, se rodasse o D6 direto, contaria esses alvos e inflaria o shadow
  # de forma SISTEMÁTICA (todo alvo liberado por 1/3/4 com unidade inelegível na
  # cadeia). Por isso a query EXCLUI os alvos que os passos 1–4 já liberariam
  # (`liberado_por_passos_1_a_4`). O passo 2 (role geral) não aparece porque este
  # log só é alcançado fora do curto-circuito `role_geral?`.
  #
  # Usa os MESMOS fragmentos do SQL de liberação (`unidade_elegivel`/
  # `path_valido`) e o MESMO conjunto de liberação por 1/3/4 (`cpfs_alvos` +
  # `subquery_tipos_terceirizado`) — nenhuma segunda definição.
  def log_unidades_inelegiveis
    ids = pessoa_ids_gestor
    return if ids.empty?

    inelegiveis = ids_unidades_inelegiveis_como_gestor(ids)
    return if inelegiveis.empty?

    Rails.logger.warn(
      evento: "autorizacao_frequencia.unidade_inelegivel",
      unidade_ids: inelegiveis,
      unidades: inelegiveis.size,
      usuario_id: usuario.id
    )
  end

  # Ids das unidades de LOTAÇÃO (o `unidade_id` que o PORO registra em
  # `log_unidade_inelegivel`) dos alvos cuja negação é por D6, RESTITOS ao passo
  # 5: (i) a cascata NÃO é resolvida pelos passos 1–4 (`liberado_por_passos_1_a_4`
  # é falso), (ii) a cadeia tem algum gestor-correspondente INELEGÍVEL e (iii)
  # NENHUM gestor-correspondente ELEGÍVEL. (ii)+(iii) são a condição exata de
  # `hierarquia?` que faz o PORO logar (`houve_unidade_inelegivel_com_gestor`).
  #
  # Devolve os `un.id` (unidade de lotação do alvo), como o PORO — e não os ids
  # das unidades inativas ancestrais: no caso `sub_inativa` (lotado numa unidade
  # ATIVA cujo ancestral é INATIVO), o PORO loga `sub_inativa`, não `inativa`.
  # ── Segurança (chore bump-rails-8.1, 2026-10-05) ───────────────────────────
  # O Brakeman apontava `SQL Injection` Medium aqui (Weak→Medium pela
  # interpolação `#{}` de string, embora o valor fosse uma constante). O ÚNICO
  # valor externo da query é o estado `ESTADO_ATIVO`; ele vira um BIND `?`
  # aplicado por `sanitize_sql_array` — a forma que QUOTEIA de fato e que o
  # scanner reconhece como segura. Os demais trechos interpolados (`un`/`au`,
  # `liberado_por_passos_1_a_4`, `cadeia_tem_gestor`) são FRAGMENTOS INTERNOS,
  # sem input de usuário:
  #   - `un`/`au` são aliases fixos;
  #   - `liberado_por_passos_1_a_4` monta `p.cpf IN (...)` com CPFs via
  #     `lista_quoted` (que usa `connection.quote`) e um EXISTS com nome de tipo
  #     constante (`subquery_tipos_terceirizado`);
  #   - `cadeia_tem_gestor` monta EXISTS sobre aliases internos com ids já
  #     `connection.quote`-ados.
  # Nenhum fragmento carrega `params`/input cru: a interpolação é ESTRUTURAL
  # (não parametrizável) e o bind cobre a única parte que era valor.
  def ids_unidades_inelegiveis_como_gestor(ids)
    sql = <<~SQL.squish
      SELECT DISTINCT un.id
      FROM lotacoes lot
      JOIN vinculos vinc ON vinc.id = lot.vinculo_id
      JOIN vinculos_estados ve ON ve.id = vinc.vinculo_estado_id
      JOIN unidades un ON un.id = lot.unidade_id
      JOIN pessoas p ON p.id = vinc.pessoa_id
      WHERE lot.principal IS TRUE
        AND (lot.fim IS NULL OR lot.fim >= CURRENT_DATE)
        AND ve.nome = ?
        AND (vinc.fim IS NULL OR vinc.fim >= CURRENT_DATE)
        AND lot.inicio = (
          SELECT MAX(lot2.inicio)
          FROM lotacoes lot2
          JOIN vinculos v2 ON v2.id = lot2.vinculo_id
          JOIN vinculos_estados ve2 ON ve2.id = v2.vinculo_estado_id
          WHERE lot2.principal IS TRUE
            AND (lot2.fim IS NULL OR lot2.fim >= CURRENT_DATE)
            AND v2.pessoa_id = vinc.pessoa_id
            AND ve2.nome = ?
            AND (v2.fim IS NULL OR v2.fim >= CURRENT_DATE)
        )
        AND NOT COALESCE((#{liberado_por_passos_1_a_4}), FALSE)
        AND (#{cadeia_tem_gestor('un', 'au', ids, elegivel: false)})
        AND NOT COALESCE((#{cadeia_tem_gestor('un', 'au', ids, elegivel: true)}), FALSE)
    SQL

    query = Pessoas::Unidade.sanitize_sql_array([ sql, ESTADO_ATIVO, ESTADO_ATIVO ])
    Pessoas::Unidade.connection.select_values(query).map(&:to_i)
  rescue ActiveRecord::ActiveRecordError, PG::Error => e
    # Diagnóstico NUNCA derruba a listagem (fail-open do log; a listagem em si
    # segue fail-closed pelas suas próprias condições).
    Rails.logger.warn(
      evento: "autorizacao_frequencia.pessoas_indisponivel",
      papel: :lotacao, erro: e.class.name, mensagem: e.message
    )
    []
  end

  # A pessoa do alvo seria liberada pelos passos 1–4 da cascata (logo o PORO
  # nunca alcança o passo 5 e nunca loga)? Reaproveita EXATAMENTE o que
  # `condicoes_liberacao` já usa:
  #   - passos 1+4: `pessoas.cpf IN (cpfs_alvos)` (próprio ∪ geridos);
  #   - passo 3: role de terceirizados E a pessoa tem ALGUM vínculo ativo
  #     Terceirizado (idêntico ao `p.in` por tipo de vínculo da liberação).
  # Devolve `nil` quando não há nenhuma condição (nenhum alvo liberável por
  # 1–4) — o chamador injeta `COALESCE(NULL, FALSE)` e nada é excluído.
  def liberado_por_passos_1_a_4
    conds = []
    conds << "p.cpf IN (#{lista_quoted(cpfs_alvos)})" if cpfs_alvos.any?

    if role_terceirizados?
      conds << "EXISTS (" \
        "SELECT 1 FROM vinculos vt " \
        "JOIN vinculos_estados vte ON vte.id = vt.vinculo_estado_id " \
        "WHERE vt.pessoa_id = p.id " \
        "AND (vt.fim IS NULL OR vt.fim >= CURRENT_DATE) " \
        "AND vte.nome = '#{ESTADO_ATIVO}' " \
        "AND vt.configuracao_cadastro_id IN (#{subquery_tipos_terceirizado}))"
    end

    return nil if conds.empty?

    "(#{conds.join(' OR ')})"
  end

  # `gestor_match(a)`: o usuário é gestor (atual/substituto/excepcional) da
  # unidade de alias `a`.
  def gestor_match(alias_unidade, ids)
    "#{alias_unidade}.gestor_id IN (#{lista_quoted(ids)}) OR " \
      "#{alias_unidade}.gestor_substituto_id IN (#{lista_quoted(ids)}) OR " \
      "#{alias_unidade}.gestor_excepcional_id IN (#{lista_quoted(ids)})"
  end

  # A cadeia de `alias_self` (self ∪ ancestrais, como `cadeia_ascendente`) tem
  # algum gestor-correspondente ELEGÍVEL (ou INELEGÍVEL). `alias_anc` é o alias
  # do JOIN dos ancestrais. Fail-closed do path: se o path é inválido,
  # `cadeia_ascendente` do PORO é só [self] — por isso os ancestrais entram
  # guardados por `path_valido`.
  def cadeia_tem_gestor(alias_self, alias_anc, ids, elegivel:)
    cond = ->(a) { elegivel ? unidade_elegivel(a) : "NOT (#{unidade_elegivel(a)})" }
    self_match = "(#{cond.call(alias_self)}) AND (#{gestor_match(alias_self, ids)})"

    a = "#{alias_self}.ancestry"
    ancestral = "EXISTS (" \
      "SELECT 1 FROM unnest(string_to_array(#{a}, '/')::bigint[]) AS aid " \
      "JOIN unidades #{alias_anc} ON #{alias_anc}.id = aid " \
      "WHERE (#{cond.call(alias_anc)}) AND (#{gestor_match(alias_anc, ids)}))"

    "(#{self_match} OR (#{path_valido(alias_self)} AND #{ancestral}))"
  end

  # Passo 3 — ids de `configuracoes_cadastro` cujo tipo de vínculo é
  # Terceirizado (D4).
  def subquery_tipos_terceirizado
    "SELECT cc.id FROM configuracoes_cadastro cc " \
      "JOIN tipos_vinculo tv ON tv.id = cc.tipo_vinculo_id " \
      "WHERE tv.nome = '#{TIPO_TERCEIRIZADO}'"
  end

  # --- fragmentos SQL reutilizáveis (espelham os métodos Ruby do PORO) -------

  # `Pessoas::Unidade#elegivel?` em SQL: ativa E sem extinção consumada.
  def unidade_elegivel(alias_unidade)
    "#{alias_unidade}.active IS TRUE AND " \
      "(#{alias_unidade}.data_extincao_serventia IS NULL " \
      "OR #{alias_unidade}.data_extincao_serventia > CURRENT_DATE)"
  end

  # `Pessoas::Unidade#cadeia_ascendente` — fail-closed do path: formato
  # (dígitos separados por "/"), sem auto-referência (comparação numérica,
  # Bug 1) e sem ids repetidos (Bug 2). Só quando isto é VÁLIDO os ancestrais
  # são considerados.
  def path_valido(alias_unidade)
    a = "#{alias_unidade}.ancestry"
    "(" \
      "#{a} IS NOT NULL " \
      "AND #{a} ~ '^\\d+(/\\d+)*$' " \
      "AND NOT (#{alias_unidade}.id = ANY(string_to_array(#{a}, '/')::bigint[])) " \
      "AND cardinality(string_to_array(#{a}, '/')::bigint[]) = " \
      "(SELECT count(DISTINCT x) FROM unnest(string_to_array(#{a}, '/')::bigint[]) AS x)" \
      ")"
  end

  # --- utilidades ------------------------------------------------------------

  def normalizar_cpf(valor)
    valor.to_s.gsub(/\D/, "").presence
  end

  # Quoting defensivo (os valores são cpfs/ids, mas nunca concatenamos cru).
  def lista_quoted(valores)
    valores.map { |valor| Pessoas::Vinculo.connection.quote(valor) }.join(", ")
  end
end
