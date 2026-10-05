require "test_helper"

# Tarefa 29.5 — regra de elegibilidade para desconsiderar um dia de frequência
# (PRD §3; `RegistroFrequenciaServices.podeDesconsiderarFrequencia`, linhas
# 91-108; Decisão D5 do CTO 2026-10-01). Testa o PORO
# `ElegibilidadeDesconsideracao` sobre o SCHEMA REAL do espelho (ADR-0006).
# Pré-requisito: `RAILS_ENV=test bin/rails test:pessoas_schema:load`.
#
# Cada teste de bloqueio tem um CONTROLE positivo: o mesmo cenário com a
# cláusula neutralizada libera — prova que a cláusula é o que bloqueia, e não
# uma degeneração dos dados de fixture.
class ElegibilidadeDesconsideracaoTest < ActiveSupport::TestCase
  include PessoasEspelhoHelper

  # Segunda-feira, no passado (2026-09-07) — mesma data-âncora da suíte de
  # cálculo (o motor só marca `falta` quando a data já passou).
  DATA = Date.new(2026, 9, 7)
  META = 8 * 3600

  setup do
    skip_sem_espelho!
  end

  # ==========================================================================
  # Controle positivo — todas as condições satisfeitas
  # ==========================================================================

  test "libera um dia elegivel quando o acionador e gestor do orgao do alvo" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    registrar_dia_elegivel(alvo)

    acionador = criar_usuario(cpf: gestor_pessoa.cpf)

    assert elegivel(acionador).pode_desconsiderar?(alvo, DATA)
  end

  # ==========================================================================
  # Cláusula 1 — o dia tem registros
  # ==========================================================================

  test "nega um dia sem registros (mesmo com calculo elegivel e acionador gestor)" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    criar_calculo(alvo) # calculo existe, mas o dia NAO tem TimeRecord

    acionador = criar_usuario(cpf: gestor_pessoa.cpf)

    refute elegivel(acionador).pode_desconsiderar?(alvo, DATA)
  end

  # ==========================================================================
  # Cláusula: `dia.getCalculo()` existe
  # ==========================================================================

  test "nega quando o dia nao tem CalculoDiario (fail-closed)" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    criar_time_record(alvo) # registros, mas SEM CalculoDiario

    acionador = criar_usuario(cpf: gestor_pessoa.cpf)

    refute elegivel(acionador).pode_desconsiderar?(alvo, DATA)
  end

  # ==========================================================================
  # Cláusula 2 — meta zero
  # ==========================================================================

  test "nega quando a meta do dia e zero" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    registrar_dia_elegivel(alvo, meta_segundos: 0)

    acionador = criar_usuario(cpf: gestor_pessoa.cpf)

    refute elegivel(acionador).pode_desconsiderar?(alvo, DATA)
  end

  # ==========================================================================
  # Cláusula 3 — falta
  # ==========================================================================

  test "nega quando o dia e falta" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    registrar_dia_elegivel(alvo, falta: true)

    acionador = criar_usuario(cpf: gestor_pessoa.cpf)

    refute elegivel(acionador).pode_desconsiderar?(alvo, DATA)
  end

  # ==========================================================================
  # Cláusula 4 — falta_compensada / falta_a_descontar / descontado_em_folha
  # ==========================================================================
  #
  # ATENÇÃO (fato documentado no topo do PORO): hoje o `CalculoDiarioService`
  # NÃO preenche esses três campos (pertencem à consolidação mensal, Sprint 17).
  # Estes testes provam o GATE do PORO montando o `CalculoDiario` à mão — NÃO
  # provam que o motor produz esse estado (o teste `motor_nao_preenche_*`, mais
  # abaixo, prova justamente o contrário: que o motor os deixa `false`).

  test "nega quando falta_compensada esta marcada" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    registrar_dia_elegivel(alvo, falta_compensada: true)

    refute elegivel(criar_usuario(cpf: gestor_pessoa.cpf)).pode_desconsiderar?(alvo, DATA)
  end

  test "nega quando falta_a_descontar esta marcada" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    registrar_dia_elegivel(alvo, falta_a_descontar: true)

    refute elegivel(criar_usuario(cpf: gestor_pessoa.cpf)).pode_desconsiderar?(alvo, DATA)
  end

  test "nega quando descontado_em_folha esta marcado" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    registrar_dia_elegivel(alvo, descontado_em_folha: true)

    refute elegivel(criar_usuario(cpf: gestor_pessoa.cpf)).pode_desconsiderar?(alvo, DATA)
  end

  # Prova do buraco documentado: o motor de cálculo de HOJE deixa os três
  # campos no default. Este teste trava o fato — se a Sprint 17 passar a
  # preenchê-los, este teste falha e força a revisão da cobertura da cláusula 4
  # (aí sim os três ramos passam a ser alcançáveis pelo motor).
  test "o motor de calculo atual NAO preenche falta_compensada/falta_a_descontar/descontado_em_folha" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    criar_time_record(alvo)

    calculo = CalculoDiarioService.calcular(alvo, DATA)

    refute calculo.falta_compensada?, "consolidacao mensal (Sprint 17) ainda nao preenche este campo"
    refute calculo.falta_a_descontar?, "consolidacao mensal (Sprint 17) ainda nao preenche este campo"
    refute calculo.descontado_em_folha?, "consolidacao mensal (Sprint 17) ainda nao preenche este campo"
  end

  # ==========================================================================
  # Cláusula 5 — nenhum registro do dia já desconsiderado
  # ==========================================================================

  test "nega quando ALGUM registro do dia ja esta desconsiderado" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    registrar_dia_elegivel(alvo)
    # Um segundo registro do dia, ja desconsiderado (o loop do legado barra).
    criar_time_record(alvo, desconsiderado: true, hora: 18)

    acionador = criar_usuario(cpf: gestor_pessoa.cpf)

    refute elegivel(acionador).pode_desconsiderar?(alvo, DATA)
  end

  test "CONTROLE: o mesmo dia SEM o registro desconsiderado libera" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    registrar_dia_elegivel(alvo)

    acionador = criar_usuario(cpf: gestor_pessoa.cpf)

    assert elegivel(acionador).pode_desconsiderar?(alvo, DATA)
  end

  # ==========================================================================
  # Cláusula 6 — acionador é gestor do órgão (passo 5). D5: SÓ o passo 5.
  # ==========================================================================

  test "nega quando o acionador nao e gestor de nenhuma unidade da cadeia do alvo" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    # Unidade de OUTRO gestor, sem relação com a do alvo.
    criar_unidade(descricao: "Outro Orgao", active: true, gestor_id: gestor_pessoa.id)
    alvo_raiz = criar_unidade(descricao: "Raiz do alvo", active: true)
    alvo = alvo_lotado_em(alvo_raiz)
    registrar_dia_elegivel(alvo)

    acionador = criar_usuario(cpf: gestor_pessoa.cpf)

    refute elegivel(acionador).pode_desconsiderar?(alvo, DATA)
  end

  test "nega quando a unidade gestora esta INATIVA (regra D6)" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: false, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    registrar_dia_elegivel(alvo)

    acionador = criar_usuario(cpf: gestor_pessoa.cpf)

    refute elegivel(acionador).pode_desconsiderar?(alvo, DATA)
  end

  # --- D5: gestor individual (passo 4) VÊ mas NÃO desconsidera --------------

  test "D5: gestor individual (passo 4) VE o alvo mas NAO pode desconsiderar" do
    acionador = criar_usuario
    alvo = criar_usuario
    gestor_individual(gestor_user: acionador, gerido: alvo)
    registrar_dia_elegivel(alvo)

    # Passo 4: VE (a cascata de visualização inclui o gestor individual).
    assert AutorizacaoFrequencia.new(acionador).pode_ver?(alvo),
           "o gestor individual precisa VER (passo 4) — senao o gate da D5 nao prova nada"

    # Mas o GATE de desconsiderar é SÓ o passo 5 (hierarquia) — o acionador
    # não é gestor de órgão do alvo, então NAO desconsidera.
    refute elegivel(acionador).pode_desconsiderar?(alvo, DATA)
  end

  test "D5: admin/role geral (passo 2) VE mas NAO desconsidera sem ser gestor de orgao" do
    acionador = criar_usuario(roles: [ :visualiza_frequentadores ])
    alvo = criar_usuario
    registrar_dia_elegivel(alvo)

    assert AutorizacaoFrequencia.new(acionador).pode_ver?(alvo)
    refute elegivel(acionador).pode_desconsiderar?(alvo, DATA)
  end

  # ==========================================================================
  # Cláusula 7 — auto-bloqueio (não desconsidera o próprio ponto)
  # ==========================================================================

  test "Auto-bloqueio: o gestor NAO desconsidera o proprio ponto mesmo sendo gestor do orgao" do
    # O acionador É o dono do ponto E é gestor do órgão onde está lotado — o
    # cenário exato que o legado veda (`gestorEhMesmoFrequentador`).
    acionador = usuario_gestor_do_proprio_orgao
    registrar_dia_elegivel(acionador)

    # Sanidade: sem o auto-bloqueio, a hierarquia sozinha liberaria (o acionador
    # é gestor do órgão do alvo). Isto prova que o auto-bloqueio é o que nega.
    assert AutorizacaoFrequencia.new(acionador).gestor_de_orgao_do?(acionador),
           "o acionador PRECISA ser gestor do orgao do alvo, senao o teste nao prova o auto-bloqueio"

    refute elegivel(acionador).pode_desconsiderar?(acionador, DATA)
  end

  test "Auto-bloqueio por FREQUENTADOR: bloqueia mesmo quando acionador e alvo sao Users DIFERENTES" do
    # Fidelidade ao `gestorEhMesmoFrequentador`: a identidade do alvo é medida
    # pelo FREQUENTADOR do Intranet (ponte `FrequentadorCache`/CPF), não só pelo
    # `User.id`. Aqui acionador e alvo são `User` DIFERENTES (CPFs distintos)
    # que resolvem para o MESMO `Frequentador` — uma comparação só por
    # `User`/CPF deixaria passar.
    #
    # Como `users.cpf` é UNIQUE no schema, esse estado não é criável por caminho
    # normal; stubamos `FrequentadorCache.find_by` (método de classe,
    # restaurado no ensure pelo helper) para devolver o MESMO frequentador para
    # CPFs distintos, isolando a identidade por Frequentador da identidade por
    # User.
    #
    # O acionador É gestor do órgão do alvo (hierarquia verdadeira) — sem isso,
    # o `refute` passaria pela hierarquia negar, e não provaria a identidade.
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    registrar_dia_elegivel(alvo)
    acionador = criar_usuario(cpf: gestor_pessoa.cpf)
    refute_equal acionador.cpf, alvo.cpf

    # CONTROLE: sem frequentador compartilhado, a hierarquia sozinha LIBERA —
    # prova que o bloqueio abaixo vem da identidade de Frequentador, não da
    # hierarquia.
    assert elegivel(acionador).pode_desconsiderar?(alvo, DATA),
           "pre-condicao: sem o frequentador compartilhado, a hierarquia deve liberar"

    frequentador = criar_frequentador_cache(cpf: acionador.cpf)

    com_metodo_de_classe_stubado(FrequentadorCache, :find_by, ->(**_kwargs) { frequentador }) do
      assert_equal frequentador.id, elegivel(acionador).send(:frequentador_de, acionador)&.id,
                   "pre-condicao: o stub precisa ser consultado de fato"
      refute elegivel(acionador).pode_desconsiderar?(alvo, DATA),
             "acionador e alvo sao Users diferentes, mas o mesmo Frequentador -> deve bloquear"
    end
  end

  test "Auto-bloqueio por FREQUENTADOR: nao bloqueia no ramo magistrado (acionador sem FrequentadorCache)" do
    # Ramo `frequentadorDoGestor == null` do legado: se o ACIONADOR não é um
    # frequentador (sem `FrequentadorCache` correspondente), o auto-bloqueio
    # não se aplica — um terceiro não é "o próprio ponto" do acionador.
    #
    # O alvo TEM `FrequentadorCache` de propósito: sem o guard do ramo
    # magistrado, o código cairia na comparação por frequentador e chamaria
    # `.id` no acionador sem frequentador (NoMethodError) — este dado mata a
    # mutação que remove o guard.
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    criar_frequentador_cache(cpf: alvo.cpf) # alvo TEM frequentador; acionador NAO tem
    registrar_dia_elegivel(alvo)

    acionador = criar_usuario(cpf: gestor_pessoa.cpf) # TEM cpf, mas NAO tem FrequentadorCache
    refute_equal acionador.id, alvo.id

    assert elegivel(acionador).pode_desconsiderar?(alvo, DATA)
  end

  # ==========================================================================
  # Fail-closed de entrada
  # ==========================================================================

  test "nega com acionador nulo" do
    alvo = criar_usuario
    refute ElegibilidadeDesconsideracao.new(nil).pode_desconsiderar?(alvo, DATA)
  end

  test "nega com alvo nulo" do
    refute elegivel(criar_usuario).pode_desconsiderar?(nil, DATA)
  end

  test "nega com data nula" do
    alvo = criar_usuario
    refute elegivel(criar_usuario).pode_desconsiderar?(alvo, nil)
  end

  # ==========================================================================
  # D1 (débito pré-29.7) — o contrato é ESTRITO a `User`
  # ==========================================================================
  #
  # O `@param` anterior anunciava `[User, Pessoas::Pessoa]`, mas `Dia#registros`
  # chama `user.time_records` e `Pessoas::Pessoa` NÃO tem essa associação
  # (`NoMethodError`). A prova abaixo exerce o caminho com um alvo NÃO-`User`
  # REAL e fixa o comportamento ESCOLHIDO: fail-closed com log — não um erro
  # cru, e não um `false` silencioso mascarado pelo guard.

  test "D1: alvo nao-User (Pessoas::Pessoa) e fail-closed com log, sem NoMethodError" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    acionador = criar_usuario(cpf: gestor_pessoa.cpf)

    # Alvo REAL não-`User`: uma `Pessoas::Pessoa` (tem `cpf`, NÃO tem
    # `time_records`). É exatamente o objeto que o contrato falso convidava a
    # passar — e que estouraria `NoMethodError` sem o guard.
    alvo_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    refute alvo_pessoa.respond_to?(:time_records),
           "pre-condicao: Pessoas::Pessoa NAO tem time_records (por isso o contrato e' so User)"

    log = capturar_log do
      # Sem o guard, `Dia.para(pessoa, DATA).registros` levantaria NoMethodError.
      refute elegivel(acionador).pode_desconsiderar?(alvo_pessoa, DATA),
             "alvo nao-User deve ser recusado (fail-closed)"
    end

    assert_match(/elegibilidade_desconsideracao\.alvo_nao_user/, log,
                 "o fail-closed de alvo nao-User precisa ser auditavel (log)")
    assert_match(/Pessoas::Pessoa/, log, "o log deve registrar a classe do alvo recusado")
  end

  # CONTROLE POSITIVO: prova que o guard NÃO é um `return false` incondicional.
  # O MESMO cenário (mesmo acionador gestor do órgão) com um alvo `User`
  # legítimo — com o dia elegível montado — LIBERA. Sem este par, o teste acima
  # passaria mesmo se o método sempre negasse.
  test "D1 CONTROLE: o mesmo acionador LIBERA quando o alvo e' um User legitimo" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    acionador = criar_usuario(cpf: gestor_pessoa.cpf)
    alvo_user = alvo_lotado_em(raiz)
    registrar_dia_elegivel(alvo_user)

    assert elegivel(acionador).pode_desconsiderar?(alvo_user, DATA),
           "pre-condicao do controle: com alvo User o gate deve liberar"
  end

  # O contrato falso só se manifestava num caminho específico: com acionador
  # NULO o guard de entrada devolvia `false` ANTES de tocar o alvo — mascarando
  # o `NoMethodError`. Este teste fixa que, mesmo com acionador nulo e alvo
  # nao-User, nada levanta (mas tampouco loga o guard de tipo, que vem depois).
  test "D1: acionador nulo + alvo nao-User nega sem levantar (mascaramento documentado)" do
    alvo_pessoa = criar_pessoa(cpf: proximo_cpf_teste)

    assert_nothing_raised do
      refute ElegibilidadeDesconsideracao.new(nil).pode_desconsiderar?(alvo_pessoa, DATA)
    end
  end

  # ==========================================================================
  # Integração com o fluxo da Sprint 19 — o gate NAO altera o efeito
  # ==========================================================================

  test "consultar a elegibilidade NAO muta o dia (PORO de leitura)" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    registrar_dia_elegivel(alvo)
    acionador = criar_usuario(cpf: gestor_pessoa.cpf)

    assert_no_changes -> { TimeRecord.where(user: alvo).pluck(:desconsiderado, :ressalva) } do
      assert elegivel(acionador).pode_desconsiderar?(alvo, DATA)
    end
    assert_equal 0, IntervencaoFrequencia.where(time_record: TimeRecord.where(user: alvo)).count
  end

  test "apos o gate liberar, desconsiderar! mantem o efeito ja implementado na Sprint 19" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    registro = registrar_dia_elegivel(alvo)
    acionador = criar_usuario(cpf: gestor_pessoa.cpf)

    assert elegivel(acionador).pode_desconsiderar?(alvo, DATA)
    registro.desconsiderar!(justificativa: "Batida indevida", responsavel: acionador)

    registro.reload
    assert registro.desconsiderado?
    assert registro.ressalva?
    intervencao = IntervencaoFrequencia.find_by(time_record: registro)
    assert_equal "desconsideracao_ponto", intervencao.tipo
    assert_equal "registrado", intervencao.status
  end

  # ==========================================================================
  # D8 — o caminho de leitura nunca chama `valid?`
  # ==========================================================================

  test "D8: nenhum caminho do pode_desconsiderar? chama valid?" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo_libera = alvo_lotado_em(raiz)
    registrar_dia_elegivel(alvo_libera)
    alvo_nega = criar_usuario
    registrar_dia_elegivel(alvo_nega)
    acionador = criar_usuario(cpf: gestor_pessoa.cpf)

    sem_validar do
      assert elegivel(acionador).pode_desconsiderar?(alvo_libera, DATA)
      refute elegivel(acionador).pode_desconsiderar?(alvo_nega, DATA)
      refute elegivel(acionador).pode_desconsiderar?(alvo_libera, nil)
    end
  end

  private

  def elegivel(acionador)
    ElegibilidadeDesconsideracao.new(acionador)
  end

  # Captura o log de Rails durante o bloco (mesmo padrão do teste da 29.4) —
  # usado para provar os eventos de auditoria do D1/D2.
  def capturar_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end

  # --- fixtures (schema real do espelho, ADR-0006) --------------------------

  def criar_usuario(cpf: nil, admin: false, roles: [])
    user = User.create!(
      nome_completo: "Usuario #{SecureRandom.hex(3)}",
      password: "123456",
      cpf: cpf,
      admin: admin
    )
    roles.each { |role| user.add_role(role) }
    user
  end

  # Cria pelo menos UM TimeRecord elegível no dia-âncora (controle positivo) e
  # um `CalculoDiario` com meta > 0. Aceita overrides para cenários de bloqueio.
  def registrar_dia_elegivel(user, meta_segundos: META, **flags)
    registro = criar_time_record(user)
    criar_calculo(user, meta_segundos: meta_segundos, **flags)
    registro
  end

  def criar_time_record(user, desconsiderado: false, hora: 8)
    TimeRecord.create!(
      user: user,
      raw_data: "#{DATA} #{format('%02d', hora)}:00:00",
      punched_at: Time.zone.local(DATA.year, DATA.month, DATA.day, hora, 0),
      authentication_mode: "biometric",
      desconsiderado: desconsiderado
    )
  end

  def criar_calculo(user, meta_segundos: META, **flags)
    CalculoDiario.create!(
      user: user,
      data: DATA,
      meta_segundos: meta_segundos,
      **flags
    )
  end

  def criar_frequentador_cache(cpf:, nome: "Frequentador Teste")
    FrequentadorCache.create!(cpf: cpf, nome: nome)
  end

  # User local cuja pessoa no Pessoas tem lotacao principal vigente na unidade.
  def alvo_lotado_em(unidade, cpf: proximo_cpf_teste)
    criar_pessoa_lotada(unidade: unidade, cpf: cpf)
    criar_usuario(cpf: cpf)
  end

  # O acionador É o dono do ponto E é gestor do órgão onde está lotado — o
  # cenário exato que o legado veda.
  def usuario_gestor_do_proprio_orgao
    cpf = proximo_cpf_teste
    pessoa = criar_pessoa(cpf: cpf)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: pessoa.id)
    vinculo = inserir(
      Pessoas::Vinculo,
      pessoa_id: pessoa.id,
      vinculo_estado_id: criar_vinculo_estado(nome: "em_exercicio").id,
      matricula: "M#{pessoa.id}",
      inicio: Date.new(2020, 1, 1)
    )
    inserir(Pessoas::Lotacao, vinculo_id: vinculo.id, unidade_id: raiz.id, principal: true,
                               inicio: Date.new(2020, 1, 1))
    criar_usuario(cpf: cpf)
  end

  # --- GestorIndividual -----------------------------------------------------

  def gestor_individual(gerido:, gestor_user: nil, gestor_cpf: nil)
    gestor = GestorIndividual.create!(
      nome: "Gestor Teste",
      gestor_user: gestor_user,
      gestor_cpf: gestor_cpf
    )
    GestorIndividualGerenciado.create!(gestor_individual: gestor, user: gerido)
  end

  # --- infra ----------------------------------------------------------------

  def inserir(model, **atributos)
    id = model.insert_all([ atributos ], returning: :id).rows.first.first
    model.find(id)
  end

  # Substitui `valid?` de TODO `ActiveRecord::Base` por um levantamento, para
  # provar que nenhum caminho do PORO o chama (D8). Restaurado ao fim.
  def sem_validar
    original = ActiveRecord::Base.instance_method(:valid?)
    ActiveRecord::Base.define_method(:valid?) do
      raise "valid? foi chamado no caminho de leitura (viola a regra D8)"
    end
    yield
  ensure
    ActiveRecord::Base.send(:define_method, :valid?, original)
  end

  def proximo_cpf_teste
    PessoasEspelhoHelper.proximo_cpf
  end
end
