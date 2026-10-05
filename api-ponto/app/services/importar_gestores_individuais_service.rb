# Tarefa 29.3 (Sprint 29) — importação idempotente dos gestores individuais
# do Intranet legado (PRD §2.5).
#
# O Intranet será descomissionado; a partir desta importação o Frequencia
# passa a ser a fonte de verdade do vínculo de gestão individual. Por isso o
# objetivo NÃO é "copiar uma vez", é poder reimportar quantas vezes for
# preciso sem duplicar nada ("segunda execução = 0 criações") e sem descartar
# o histórico: um registro excluído no legado entra como INATIVO, nunca é
# ignorado.
#
# Fonte: `SticapiClient::Intranet.gestores_individuais` — cada item traz
# `id, data_criacao, data_exclusao, observacao, id_vinculo_gestor,
# matricula_gestor, id_vinculo_gerido, matricula_gerido`. A listagem é uma
# tabela de LIGAÇÃO (uma linha = um par gestor→gerido), enquanto o modelo do
# Frequencia 29.2 separou o par em dois: `GestorIndividual` (o gestor, por
# pessoa) e `GestorIndividualGerenciado` (o vínculo gestor→gerido). Esta
# separação é o que torna o mapeamento de chave abaixo não-trivial.
#
# ── Mapeamento de identidade (decisão da importação, Bug 10 da 29.2) ────────
# A lista do Intranet tem N linhas por gestor (uma por gerido), mas o
# `GestorIndividual` do Frequencia é UMA linha por PESSOA (a tela
# `admin/gestores_individuais` lista gestores e conta `gerenciados` — N
# linhas da mesma pessoa apareceriam duplicadas). Logo as duas tabelas usam
# chaves estáveis DIFERENTES, ambas previstas nos índices UNIQUE da 29.2:
#
#   - `gestor_individual_gerenciados.id_legado` = `id` da linha legada
#     (a chave do PAR — o índice UNIQUE do par ativo/histórico depende disso);
#   - `gestores_individuais.id_legado` = `id_vinculo_gestor` (a chave da
#     PESSOA-gestor; estável por vínculo).
#   - `gestores_individuais.gestor_cpf` é a ponte de casamento documentada na
#     29.2 (Bug 10) — casa a linha legada com o gestor já importado quando o
#     `id_vinculo_gestor` vier ausente/divergente.
#
# ── Complemento 29.3-D1..D4 (ADR-0008, CTO 2026-09-30) ─────────────────────
# Quatro patches decididos pelos rulings do CTO, aplicados nesta mesma linha
# de entrega:
#   - D1 — `ativo`/`data_exclusao` do GESTOR são PROJEÇÃO determinística dos
#     vínculos, recalculada PÓS-LOOP (`recalcular_gestores_tocados`), nunca
#     "a última linha do payload vence". O `ativo` do PAR preserva 1:1 o dado
#     do Intranet. Lê via `GestorIndividualGerenciado.ativos` (índice parcial).
#   - D2 — guarda de identidade: se o `gestor_cpf` resolvido divergir do CPF do
#     gestor casado por `id_legado` do gestor, a linha vira `nao_resolvido`
#     (conflito de identidade) — nunca reescreve CPF/`gestor_user` do existente.
#   - D3 — nome não resolvido usa marcador explícito de sistema
#     `"(sem nome — CPF <cpf>)"`, substituível quando o Pessoas volta (nome
#     real sempre prevalece sobre o marcador).
#   - D4 — tolerância ao casing das chaves de data do payload legado
#     (`data_criacao` \|\| `dataCriacao`; idem exclusão), com verificação de
#     contrato que falha alto se nenhum casing conhecido estiver presente.
#
# ── Modo de escrita (CTO, 2026-09-29 / ADR-0007) ───────────────────────────
# ActiveRecord (create/update!), NUNCA `upsert_all`: o invariante de
# auto-gerência cruza duas tabelas e não é expressável em SQL, então um
# upsert em massa o contornaria. Consequência aceita: uma linha que viole o
# invariante (ex.: gestor = seu próprio gerido ativo) é RECUSADA aqui e sai
# no relatório de não-resolvidos — não é gravada "por baixo".
#
# Regras de borda que caem nesta tarefa (triagem do CTO):
#   - ⚪ 11: `id_legado > 0` — 0/negativo/ausente nunca vira chave de upsert;
#   - ⚪ 14: `gestor_cpf: ""` → `nil` (`presence`), sem mexer em `allow_nil`;
#   - 🟢 19: resgatar `DeleteRestrictionError` E `InvalidForeignKey` — a FK é
#     que segura o hard-delete (o `restrict_with_exception` do model não cobre
#     quem escreve fora do cache do `has_many`);
#   - Bug 8: `RecordInvalid` nunca vaza `e.message` cru (o locale só é seguro
#     com `errors.full_messages`);
#   - Bug 3 da D7 / A5: `ativo: nil` normalizado na borda (não pode "pular" a
#     validação de auto-gerência nem virar estado implausível para auditoria);
#   - `data_exclusao` legada é gravada DIRETO no atributo (via `update!`),
#     nunca via `desativar!` — o método data a exclusão ao momento da chamada,
#     que não é a data do legado (ADR-0007, regra 4).
class ImportarGestoresIndividuaisService
  # D3 (ADR-0008, regra 6) — marcador explícito de sistema para "nome não
  # resolvido no Pessoas". Diferente do antigo `"Gestor individual <CPF>"`
  # (que se parecia com nome real e "grudava" por `||=`), este é
  # inconfundível e substituível quando o Pessoas volta.
  MARCADOR_SEM_NOME = "(sem nome — CPF "

  # Relatório final da importação. `nao_resolvidos` é enumerável (nada é
  # silenciosamente ignorado) — cada item traz o id legado e o motivo.
  Resultado = Struct.new(:importados, :atualizados, :nao_resolvidos, :dry_run, keyword_init: true) do
    def total
      importados + atualizados + nao_resolvidos.size
    end

    # String pronta para o log da task/job e para a inspeção manual.
    def resumo
      modo = dry_run ? "DRY-RUN (nenhuma escrita)" : "execução real"
      linhas = [
        "Importação de gestores individuais do Intranet — #{modo}",
        "  linhas lidas:   #{total}",
        "  importados:     #{importados}",
        "  atualizados:    #{atualizados}",
        "  não resolvidos: #{nao_resolvidos.size}"
      ]

      nao_resolvidos.each do |n|
        linhas << "    - linha legada #{n.id_legado.inspect}: #{n.motivo}"
      end

      linhas.join("\n")
    end
  end

  NaoResolvido = Struct.new(:id_legado, :motivo, keyword_init: true)

  # `registros:` permite injetar a lista (testes, reexecução a partir de um
  # dump do Intranet) sem tocar a rede; `silencioso` evita logs de cada linha
  # em dry-run/uso programático.
  def self.call(registros: nil, dry_run: false)
    new(dry_run: dry_run).call(registros)
  end

  def initialize(dry_run: false)
    @dry_run = dry_run
    @importados = 0
    @atualizados = 0
    @nao_resolvidos = []
    # D1: ids dos gestores tocados nesta execução, para o recálculo PÓS-LOOP.
    # Guardamos só o id (e recarregamos no recálculo) — assim não dependemos da
    # instância Ruby (que pode estar stale se o mesmo gestor vier em várias
    # linhas).
    @gestores_tocados = {}
  end

  def call(registros = nil)
    # Normaliza TODAS as linhas antes de qualquer leitura por chave: o mapa
    # matrícula→CPF e as linhas precisam falar a mesma "língua" de chave
    # (indifferent access), senão `l[:matricula_gestor]` seria `nil` sobre um
    # Hash de chaves string — e a importação inteira viraria "não resolvido".
    linhas = Array(registros || carregar_registros).map { |linha| normalizar_linha(linha) }
    verificar_contrato!(linhas)
    pares = mapa_matricula_cpf(linhas)

    linhas.each { |linha| importar_linha(linha, pares) }

    # D1 (ADR-0008, Ruling 3): o `ativo`/`data_exclusao` do GESTOR é projeção
    # dos vínculos e só pode ser calculado DEPOIS de todas as linhas do gestor
    # (nunca "a última linha do payload vence"). Em dry-run não há escrita.
    recalcular_gestores_tocados unless @dry_run

    Resultado.new(
      importados: @importados,
      atualizados: @atualizados,
      nao_resolvidos: @nao_resolvidos,
      dry_run: @dry_run
    )
  end

  private

  def carregar_registros
    SticapiClient::Intranet.gestores_individuais
  end

  # A gem devolve Array de Hash com chaves string. `with_indifferent_access`
  # evita depender do tipo exato de chave devolvido em cada versão da API.
  def normalizar_linha(linha)
    hash = linha.respond_to?(:with_indifferent_access) ? linha : linha.to_h
    hash.with_indifferent_access
  end

  # --- D4 (F2): casing das chaves de data do payload legado ------------------
  #
  # A gem faz `JSON.parse(response.body)` CRU (sem `key_transform`), então o
  # casing das chaves é exatamente o que o servidor envia. Dois consumidores
  # reais do MESMO endpoint divergem: o Pessoas2 lê `dataCriacao`/`dataExclusao`
  # (camelCase, `pessoas2/app/models/gestao_individual.rb:23`) e a doc da gem
  # diz `data_criacao`/`data_exclusao` (snake_case). NÃO temos amostra real.
  # Se o real for camelCase e lermos só snake_case, `momento_exclusao` seria
  # sempre `nil` ⇒ todo excluído entraria ATIVO sem `data_exclusao` (corrupção
  # silenciosa de `ativo`, com a suíte verde). Solução: aceitar AMBOS os
  # casings, explicitamente.
  def valor_da_linha(linha, *chaves)
    chaves.each do |chave|
      valor = linha[chave]
      return valor if valor.present?
    end
    nil
  end

  def data_criacao_da_linha(linha)
    valor_da_linha(linha, :data_criacao, :dataCriacao)
  end

  def data_exclusao_da_linha(linha)
    valor_da_linha(linha, :data_exclusao, :dataExclusao)
  end

  # Contrato de dados (D4 reforçado — achado 🟡1 do review): a verificação é
  # POR CAMPO e POR LINHA, não por "alguma chave conhecida apareceu".
  #
  # O contrato anterior usava `any?` sobre a linha inteira: bastava UMA das 4
  # chaves casar para a linha ser "perdoada". Consequência medida: uma linha com
  # `data_criacao` (reconhecida) e a EXCLUSÃO num casing não previsto (ex.:
  # `dataExclusao2`, `data_exclusao_legado`) passava em silêncio e o vínculo
  # entrava ATIVO SEM `data_exclusao` — exatamente a corrupção silenciosa de
  # `ativo` que o F2/ADR-0008 existe para matar.
  #
  # Regra nova, por campo crítico:
  #   - se a linha traz o casing conhecido daquele campo → OK;
  #   - se NÃO traz, mas tem ALGUMA chave que "parece" com o campo (mesma
  #     palavra distintiva, ex.: contém `exclusao`) → é variante de casing
  #     desconhecida: falha ALTO (não vira `nil` silencioso);
  #   - se NÃO traz nada que se pareça com o campo → o campo está ausente de
  #     verdade (legítimo: nem todo vínculo tem exclusão) → OK.
  # A ausência legítima se distingue da variante desconhecida pela CHAVE, não
  # pelo valor — por isso o campo de exclusão ausente NÃO é falso positivo.
  #
  # `registros: []` não é violação.
  def verificar_contrato!(linhas)
    return if linhas.empty?

    linhas.each do |linha|
      verificar_campo_de_data!(linha, "exclusão", :data_exclusao, :dataExclusao, "exclusao")
      verificar_campo_de_data!(linha, "criação", :data_criacao, :dataCriacao, "criacao")
    end

    # Rede secundária: se NENHUMA linha trouxer qualquer casing conhecido, o
    # formato pode ter mudado por inteiro (nomes de campo reescritos, sem a
    # palavra distintiva). Mantém a proteção original contra essa troca global.
    reconhecido = linhas.any? do |linha|
      linha.key?(:data_criacao) || linha.key?(:dataCriacao) ||
        linha.key?(:data_exclusao) || linha.key?(:dataExclusao)
    end
    return if reconhecido

    raise ArgumentError,
          "payload de gestores_individuais fora do contrato: nenhuma linha traz " \
          "data_criacao/dataCriacao nem data_exclusao/dataExclusao (casing do endpoint mudou?)"
  end

  # Verifica UM campo de data em UMA linha (detalhes em `verificar_contrato!`).
  # `palavra` é o termo distintivo do campo, usado para reconhecer variantes de
  # casing desconhecidas (mesma palavra, chave diferente).
  def verificar_campo_de_data!(linha, rotulo, chave_snake, chave_camel, palavra)
    return if linha.key?(chave_snake) || linha.key?(chave_camel)

    variante = linha.keys.find { |chave| chave_normalizada(chave).include?(palavra) }
    return if variante.nil?

    raise ArgumentError,
          "payload de gestores_individuais fora do contrato: o campo de #{rotulo} " \
          "vem numa chave desconhecida (#{variante.inspect}); esperado #{chave_snake}/#{chave_camel}. " \
          "Casing do endpoint mudou?"
  end

  # Compara nomes de chave ignorando casing e separadores: `data_exclusao`,
  # `dataExclusao` e `DataExclusao` viram todos "dataexclusao". Assim uma
  # variante com o MESMO nome em outro casing é reconhecida (e rejeitada) em
  # vez de virar `nil` silencioso.
  def chave_normalizada(chave)
    chave.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end

  # Um único mapa matrícula→CPF para toda a importação (a folha é lida uma
  # vez, não por linha) — mesmo desenho do ImportarServidoresUnidadeJob.
  def mapa_matricula_cpf(linhas)
    matriculas = linhas.flat_map { |l| [ l[:matricula_gestor], l[:matricula_gerido] ] }
                       .compact
                       .map(&:to_s)
                       .reject(&:blank?)
                       .uniq
    return {} if matriculas.empty?

    ResolverCpfPorMatriculaService.mais_recente(matriculas)
  end

  # --- uma linha legada = um par gestor→gerido ------------------------------

  def importar_linha(linha, pares)
    id_registro = inteiro_positivo(linha[:id])
    if id_registro.nil?
      return registrar_nao_resolvido(linha[:id], "id legado inválido (ausente, zero ou negativo) — ⚪ 11")
    end

    gestor_cpf = resolver_cpf(linha[:matricula_gestor], pares, linha[:id_vinculo_gestor])
    if gestor_cpf.blank?
      return registrar_nao_resolvido(id_registro, "matrícula do gestor #{linha[:matricula_gestor].inspect} sem CPF")
    end

    gerido_cpf = resolver_cpf(linha[:matricula_gerido], pares, linha[:id_vinculo_gerido])
    if gerido_cpf.blank?
      return registrar_nao_resolvido(id_registro, "matrícula do gerido #{linha[:matricula_gerido].inspect} sem CPF")
    end

    gerido_user = User.find_by(cpf: gerido_cpf)
    if gerido_user.nil?
      return registrar_nao_resolvido(id_registro, "gerido (CPF #{gerido_cpf}) não tem User no Frequencia")
    end

    aplicar(id_registro, linha, gestor_cpf, gerido_user)
  end

  # A escrita real (ou a simulação, em dry-run). Isolada para que o dry-run
  # percorra EXATAMENTE o mesmo caminho de resolução — só não persiste.
  def aplicar(id_registro, linha, gestor_cpf, gerido_user)
    id_legado_do_gestor = chave_do_gestor(linha)
    gestor, origem = encontrar_gestor(gestor_cpf, id_legado_do_gestor)

    # D2 (ADR-0008, Ruling 1): linha casada por `id_legado` do gestor cujo CPF
    # resolvido DIVERGE do CPF gravado é conflito de identidade → não resolvido.
    # Nunca reescrever o CPF nem o `gestor_user` do gestor existente (evita
    # auto-autorização na cascata por id reaproveitado).
    if origem == :por_chave
      conflito = conflito_de_identidade(gestor, gestor_cpf)
      return registrar_nao_resolvido(id_registro, conflito) if conflito
    end

    vinculo = GestorIndividualGerenciado.find_or_initialize_by(id_legado: id_registro)
    criacao = gestor.new_record? || vinculo.new_record?

    if @dry_run
      registrar_resultado(criacao)
      return
    end

    gestor_user = User.find_by(cpf: gestor_cpf)
    momento_exclusao = tempo(data_exclusao_da_linha(linha))

    ActiveRecord::Base.transaction do
      aplicar_gestor(gestor, linha, gestor_cpf, gestor_user)
      aplicar_vinculo(vinculo, gestor, gerido_user, momento_exclusao)
    end

    @gestores_tocados[gestor.id] = true
    registrar_resultado(criacao)
  rescue ActiveRecord::RecordInvalid => e
    # Bug 8 (blocker da 29.3): `e.message` cru cai em "Translation missing"
    # quando o namespace do locale não resolve. `full_messages` é a fonte
    # confiável.
    registrar_nao_resolvido(id_registro, "registro inválido: #{e.record.errors.full_messages.to_sentence}")
  rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::InvalidForeignKey => e
    # 🟢 19: o `restrict_with_exception` do model só cobre quem destrói pelo
    # `has_many`; um vínculo/deleção fora desse cache levanta a FK crua. Ambos
    # os tipos são resgatados aqui — a FK é a garantia real do "nunca
    # hard-delete".
    registrar_nao_resolvido(id_registro, "violação de integridade referencial: #{e.class}")
  rescue StandardError => e
    # Mesma filosofia dos demais jobs de importação: uma linha ruim não pode
    # abortar a importação inteira. O erro sai no relatório, não no silêncio.
    registrar_nao_resolvido(id_registro, "#{e.class}: #{e.message}")
  end

  # Aplica os campos do GESTOR que vêm da linha legada. NÃO define
  # `ativo`/`data_exclusao` do gestor: isso é projeção pós-loop (D1).
  def aplicar_gestor(gestor, linha, gestor_cpf, gestor_user)
    novo = gestor.new_record?

    # F1 (ADR-0008, regra 5): o `id_legado` do gestor reancora SÓ na criação.
    # Uma linha com `id_vinculo_gestor` presente casa por `id_legado` (e um
    # gestor já existente encontrado assim já tem o id). Uma linha SEM
    # `id_vinculo_gestor` casa pela ponte CPF e NÃO reancora — reancorar em
    # toda linha movia o gestor entre linhas e colidia com o índice UNIQUE
    # parcial `index_gestor_individual_gerenciados_on_par_ativo`.
    gestor.id_legado = chave_do_gestor(linha) if novo

    # D2: o CPF de um gestor EXISTENTE nunca é reescrito (o conflito já foi
    # barrado em `aplicar`). Só a criação grava o CPF.
    gestor.gestor_cpf = normalizar_cpf(gestor_cpf) if novo

    aplicar_nome(gestor, gestor_cpf)
    gestor.observacao = linha[:observacao].presence
    gestor.data_criacao_legado = tempo(data_criacao_da_linha(linha))
    gestor.gestor_user = gestor_user

    gestor.save!
  end

  def aplicar_vinculo(vinculo, gestor, gerido_user, momento_exclusao)
    vinculo.gestor_individual = gestor
    vinculo.user = gerido_user
    aplicar_estado(vinculo, momento_exclusao)

    vinculo.save!
  end

  # Normalização de `ativo` na borda (Bug 3 da D7 / A5): um `ativo: nil` do
  # legado PULA a validação de auto-gerência (só o NOT NULL do banco segura) e
  # é um estado implausível. Regra: excluído no legado ⇒ inativo; senão ativo.
  # E `data_exclusao` é gravada direto no atributo — nunca `desativar!`.
  # Vale para o PAR (`GestorIndividualGerenciado`); o GESTOR é recalculado
  # pós-loop (D1).
  def aplicar_estado(registro, momento_exclusao)
    registro.data_exclusao = momento_exclusao
    registro.ativo = momento_exclusao.nil?
  end

  # --- D1 (ADR-0008, Ruling 3): projeção determinística do estado do gestor --

  def recalcular_gestores_tocados
    @gestores_tocados.each_key do |gestor_id|
      recalcular_gestor(GestorIndividual.find(gestor_id))
    end
  end

  # Semântica (ADR-0008, regra 1-2): `ativo` do gestor = true sse existe ≥ 1
  # vínculo ATIVO; `data_exclusao` do gestor reflete o conjunto de vínculos
  # ativos (nulos por construção) e, sem nenhum ativo, preserva a exclusão
  # mais recente entre os vínculos. Independe da ordem do payload.
  #
  # Usa `gestor_individual_gerenciados.ativos` — que aciona o índice UNIQUE
  # parcial `WHERE ativo` (fecha o Bug 16).
  def recalcular_gestor(gestor)
    escopo = GestorIndividualGerenciado.where(gestor_individual_id: gestor.id)

    if escopo.ativos.exists?
      gestor.ativo = true
      gestor.data_exclusao = nil
    else
      gestor.ativo = false
      ultima = escopo.maximum(:data_exclusao)
      gestor.data_exclusao = ultima if ultima.present?
    end

    gestor.save! if gestor.changed?
    gestor
  end

  # --- identidade -----------------------------------------------------------

  # Chave da PESSOA-gestor (ver cabeçalho): `id_vinculo_gestor` quando válido.
  def chave_do_gestor(linha)
    inteiro_positivo(linha[:id_vinculo_gestor])
  end

  # Upsert idempotente do gestor, tolerante a bases parcialmente importadas.
  # Retorna `[gestor, origem]` para que `aplicar` aplique a guarda de
  # identidade (D2) só quando o casamento veio pelo `id_legado`.
  #
  # F1 (ADR-0008, regra 5): linha com `id_vinculo_gestor` PRESENTE casa SÓ por
  # `id_legado` do gestor (`nil`/novo se não houver) — NÃO usa a ponte CPF, o
  # que evita reancorar/mover um gestor existente. Linha sem `id_vinculo_gestor`
  # usa a ponte `gestor_cpf` (base importada antes de o vínculo existir).
  def encontrar_gestor(gestor_cpf, id_legado)
    if id_legado.present?
      por_chave = GestorIndividual.find_by(id_legado: id_legado)
      return [ por_chave, :por_chave ] if por_chave

      [ GestorIndividual.new, :novo ]
    else
      por_ponte = GestorIndividual.where(gestor_cpf: normalizar_cpf(gestor_cpf)).order(:id).first
      return [ por_ponte, :por_ponte_cpf ] if por_ponte

      [ GestorIndividual.new, :novo ]
    end
  end

  # D2: motivo do conflito se o CPF resolvido divergir do CPF do gestor casado
  # por `id_legado` do gestor; `nil` se concordam (ou se o gestor não tem CPF).
  def conflito_de_identidade(gestor, gestor_cpf)
    resolvido = normalizar_cpf(gestor_cpf)
    return if gestor.gestor_cpf.blank? || gestor.gestor_cpf == resolvido

    "conflito de identidade: o id_legado do gestor pertence ao CPF #{gestor.gestor_cpf}, " \
      "mas esta linha resolveu o CPF #{resolvido} — CPF e login do gestor existente não foram tocados"
  end

  # --- resolução matrícula→CPF (espelha o pessoas2, incl. o fallback) -------

  # `matricula` vem da folha do GestoRH; quando ela não resolve, o legado
  # ainda dá o vínculo do Intranet, que o Pessoas2 casa por `codigo_de_para`
  # (mesmo fallback de `GestaoIndividual.create_gestor_individual`).
  def resolver_cpf(matricula, pares, id_vinculo)
    cpf = pares[matricula.to_s] if matricula.present?
    return cpf if cpf.present?

    cpf_por_vinculo_legado(id_vinculo)
  end

  def cpf_por_vinculo_legado(id_vinculo)
    return if id_vinculo.blank?

    vinculo = Pessoas::Vinculo.where(codigo_de_para: id_vinculo.to_s).order(inicio: :desc).first
    vinculo&.pessoa&.cpf
  rescue StandardError => e
    Rails.logger.warn("[ImportarGestoresIndividuaisService] falha ao resolver vinculo legado #{id_vinculo}: #{e.class} - #{e.message}")
    nil
  end

  # --- D3 (ADR-0008, regra 6-7): nome do gestor ------------------------------

  # O payload legado não traz o nome do gestor; o Pessoas é a autoridade
  # cadastral. `nome` é obrigatório no model, então quando não há nome real
  # gravamos um MARCADOR explícito de sistema — nunca descartamos a linha.
  # Regra de precedência: o nome real do Pessoas SEMPRE ganha do marcador (uma
  # reimportação substitui o marcador), mas o marcador NÃO sobrepõe um nome
  # real já gravado por outro caminho. Nunca reescrevemos um nome real por
  # outro valor que não seja o nome real do Pessoas.
  def aplicar_nome(gestor, gestor_cpf)
    cpf = normalizar_cpf(gestor_cpf)
    nome_real = nome_do_pessoas(cpf)

    if nome_real.present?
      gestor.nome = nome_real if gestor.nome.blank? || nome_de_sistema?(gestor.nome)
    elsif gestor.nome.blank?
      gestor.nome = "#{MARCADOR_SEM_NOME}#{cpf})"
    end
  end

  def nome_do_pessoas(cpf)
    Pessoas::Pessoa.find_by(cpf: cpf)&.nome.presence
  rescue StandardError => e
    Rails.logger.warn("[ImportarGestoresIndividuaisService] falha ao ler nome do gestor #{cpf}: #{e.class} - #{e.message}")
    nil
  end

  # Reconhece o marcador de sistema (D3), para não tratá-lo como nome real.
  def nome_de_sistema?(nome)
    nome.to_s.start_with?(MARCADOR_SEM_NOME)
  end

  # --- utilidades -----------------------------------------------------------

  # ⚪ 14: `""` → `nil` (`presence`), sem tocar no `allow_nil` do model.
  def normalizar_cpf(cpf)
    cpf.to_s.presence
  end

  # ⚪ 11: id legado só vale como chave se for inteiro > 0 (0 e negativo
  # colidiriam com id real; string numérica é aceita e convertida).
  def inteiro_positivo(valor)
    numero = Integer(valor, exception: false)
    numero if numero && numero.positive?
  end

  # Timestamps do legado vêm como "2019-10-30 10:03:25.0". Falha de parse
  # vira `nil` (não derruba a linha) — `Time.zone.parse` é o ponto que respeita
  # o timezone da aplicação.
  def tempo(valor)
    return if valor.blank?

    Time.zone.parse(valor.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def registrar_resultado(criacao)
    criacao ? @importados += 1 : @atualizados += 1
  end

  def registrar_nao_resolvido(id_legado, motivo)
    @nao_resolvidos << NaoResolvido.new(id_legado: id_legado, motivo: motivo)
    Rails.logger.warn("[ImportarGestoresIndividuaisService] linha legada #{id_legado.inspect} não resolvida: #{motivo}")
    nil
  end
end
