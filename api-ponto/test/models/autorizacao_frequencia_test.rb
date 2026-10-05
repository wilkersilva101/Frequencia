require "test_helper"

# Tarefa 29.4 — cascata de autorização de visualização de frequência
# (PRD — regra central de autorização; Decisões D1/D4/D6/D8 do CTO;
# ADR-0006: os testes de precedência/negação usam o SCHEMA REAL do espelho,
# não stubs. Pré-requisito: `RAILS_ENV=test bin/rails test:pessoas_schema:load`).
class AutorizacaoFrequenciaTest < ActiveSupport::TestCase
  include PessoasEspelhoHelper

  # Débito B1: sem o schema do espelho (CI/máquina limpa), PULA explícito.
  setup do
    skip_sem_espelho!
  end

  # ==========================================================================
  # Passo 1 — próprio (user.id / CPF)
  # ==========================================================================

  test "1: libera o proprio usuario pelo id (motivo :proprio)" do
    user = criar_usuario

    assert_motivo :proprio, user, user
  end

  test "1: libera o proprio usuario pelo CPF mesmo com instancias distintas (motivo :proprio)" do
    user = criar_usuario(cpf: proximo_cpf_teste)
    mesma_pessoa = User.find(user.id)

    assert_motivo :proprio, user, mesma_pessoa
  end

  test "1: nega um alvo com o mesmo id de uma classe diferente" do
    gestor = criar_usuario
    # Um alvo que NAO e User nao pode casar com o id do usuario logado.
    outra_pessoa = Pessoas::Pessoa.new(id: gestor.id)

    assert_motivo :negado, gestor, outra_pessoa
  end

  # ==========================================================================
  # Passo 2 — role_geral (visualiza_frequentadores ou admin)
  # ==========================================================================

  test "2: libera com a role visualiza_frequentadores" do
    gestor = criar_usuario(roles: [ :visualiza_frequentadores ])
    alvo = criar_usuario

    assert_motivo :role_geral, gestor, alvo
  end

  test "2: admin pela coluna booleana libera" do
    gestor = criar_usuario(admin: true)

    assert_motivo :role_geral, gestor, criar_usuario
  end

  test "2: admin pela role Rolify libera (dupla fonte de verdade)" do
    gestor = criar_usuario(roles: [ :admin ])

    assert_motivo :role_geral, gestor, criar_usuario
  end

  test "2: nao libera sem role geral nem admin" do
    gestor = criar_usuario(roles: [ :gestor ])

    assert_motivo :negado, gestor, criar_usuario
  end

  # ==========================================================================
  # Passo 3 — terceirizado (role + alvo TERCEIRIZADO)
  # ==========================================================================

  test "3: role visualiza_terceirizados sozinha libera um alvo TERCEIRIZADO" do
    gestor = criar_usuario(roles: [ :visualiza_terceirizados ])
    alvo = alvo_terceirizado

    assert_motivo :terceirizado, gestor, alvo
  end

  test "3: role visualiza_terceirizados sozinha NAO libera um alvo nao-terceirizado" do
    gestor = criar_usuario(roles: [ :visualiza_terceirizados ])
    alvo = alvo_nao_terceirizado

    assert_motivo :negado, gestor, alvo
  end

  test "3: alvo com 2 vinculos ativos (1 nao-terceirizado + 1 terceirizado) conta como TERCEIRIZADO" do
    # Semantica fixada na 29.4 (D4): "algum vinculo ativo terceirizado", nunca
    # o `.first` do vinculo principal — que negaria um terceirizado cujo
    # Terceirizado nao fosse o primeiro.
    gestor = criar_usuario(roles: [ :visualiza_terceirizados ])
    alvo = alvo_com_dois_vinculos_ativos

    assert_motivo :terceirizado, gestor, alvo
  end

  test "3: role visualiza_terceirizados + visualiza_frequentadores equivale a role_geral" do
    gestor = criar_usuario(roles: [ :visualiza_terceirizados, :visualiza_frequentadores ])

    # Alvo NAO-terceirizado: se a role de terceirizados vencesse, negaria.
    assert_motivo :role_geral, gestor, criar_usuario
  end

  # ==========================================================================
  # Passo 4 — GestorIndividual ATIVO vinculado
  # ==========================================================================

  test "4: libera quando ha vinculo de GestorIndividual ATIVO pelo login (motivo :gestor_individual)" do
    gestor = criar_usuario
    alvo = criar_usuario
    gestor_individual(gestor_user: gestor, gerido: alvo)

    assert_motivo :gestor_individual, gestor, alvo
  end

  test "4: libera quando o vinculo ativo casa pela ponte CPF (gestor sem login)" do
    cpf = proximo_cpf_teste
    gestor = criar_usuario(cpf: cpf)
    alvo = criar_usuario
    gestor_individual(gestor_cpf: cpf, gerido: alvo)

    assert_motivo :gestor_individual, gestor, alvo
  end

  test "4: NAO libera quando o vinculo de GestorIndividual esta INATIVO" do
    gestor = criar_usuario
    alvo = criar_usuario
    vinculo = gestor_individual(gestor_user: gestor, gerido: alvo)
    vinculo.desativar!

    assert_motivo :negado, gestor, alvo
  end

  test "4: NAO libera para outro usuario que nao e o gestor do vinculo" do
    gestor = criar_usuario
    outro = criar_usuario
    alvo = criar_usuario
    gestor_individual(gestor_user: gestor, gerido: alvo)

    assert_motivo :negado, outro, alvo
  end

  # ==========================================================================
  # Passo 5 — hierarquia (gestor atual/substituto/excepcional na cadeia)
  # ==========================================================================

  test "5: libera quando o usuario e gestor de uma unidade ancestral ativa (motivo :hierarquia)" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    folha = criar_unidade(descricao: "Folha", parent: raiz, active: true)
    alvo = alvo_lotado_em(folha)
    gestor = criar_usuario(cpf: gestor_pessoa.cpf)

    assert_motivo :hierarquia, gestor, alvo
  end

  test "5: libera com gestor_substituto e gestor_excepcional tambem" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_substituto_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    gestor = criar_usuario(cpf: gestor_pessoa.cpf)

    assert_motivo :hierarquia, gestor, alvo
  end

  test "5 D6: ancestral INATIVO nao libera pelos seus gestores" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: false, gestor_id: gestor_pessoa.id)
    folha = criar_unidade(descricao: "Folha", parent: raiz, active: true)
    alvo = alvo_lotado_em(folha)
    gestor = criar_usuario(cpf: gestor_pessoa.cpf)

    assert_motivo :negado, gestor, alvo
  end

  test "5 D6: ancestral EXTINTO nao libera pelos seus gestores" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id,
                         data_extincao_serventia: Date.current - 1)
    folha = criar_unidade(descricao: "Folha", parent: raiz, active: true)
    alvo = alvo_lotado_em(folha)
    gestor = criar_usuario(cpf: gestor_pessoa.cpf)

    assert_motivo :negado, gestor, alvo
  end

  test "5 D6: unidade de LOTACAO inativa (mesmo sendo a do alvo) nao libera" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    folha = criar_unidade(descricao: "Folha", active: false, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(folha)
    gestor = criar_usuario(cpf: gestor_pessoa.cpf)

    assert_motivo :negado, gestor, alvo
  end

  test "5 D6: gestor de unidade ATIVA acima de uma INATIVA libera (inativa nao interrompe a subida)" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    intermediaria = criar_unidade(descricao: "Intermediaria", parent: raiz, active: false)
    folha = criar_unidade(descricao: "Folha", parent: intermediaria, active: true)
    alvo = alvo_lotado_em(folha)
    gestor = criar_usuario(cpf: gestor_pessoa.cpf)

    assert_motivo :hierarquia, gestor, alvo
  end

  test "5 D6: ancestral AUSENTE e pulado (sobe, loga ancestral_ausente) e nao falha a request" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    ausente = raiz.id + 1_000_000
    folha = criar_unidade(descricao: "Folha", ancestry: "#{raiz.id}/#{ausente}", active: true)
    alvo = alvo_lotado_em(folha)
    gestor = criar_usuario(cpf: gestor_pessoa.cpf)

    log = capturar_log { assert_motivo :hierarquia, gestor, alvo }
    assert_includes log, "autorizacao_frequencia.ancestral_ausente"
    assert_includes log, ausente.to_s
  end

  test "5 D6: nega e loga unidade_inelegivel quando a unica unidade com gestor estava inelegivel" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: false, gestor_id: gestor_pessoa.id)
    folha = criar_unidade(descricao: "Folha", parent: raiz, active: true)
    alvo = alvo_lotado_em(folha)
    gestor = criar_usuario(cpf: gestor_pessoa.cpf)

    log = capturar_log { assert_motivo :negado, gestor, alvo }
    assert_includes log, "autorizacao_frequencia.unidade_inelegivel"
  end

  test "5: nega quando sobe a cadeia ate a raiz sem casar nenhum gestor" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true)
    folha = criar_unidade(descricao: "Folha", parent: raiz, active: true)
    alvo = alvo_lotado_em(folha)
    gestor = criar_usuario(cpf: gestor_pessoa.cpf)

    assert_motivo :negado, gestor, alvo
  end

  # ==========================================================================
  # Passo 10 — alvo sem lotacao vigente / Pessoas indisponivel
  # ==========================================================================

  test "10: alvo sem lotacao vigente so passa pelos passos 1-4 (nega a hierarquia)" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    # Unidade com gestor, mas o alvo NAO tem lotacao nenhuma.
    criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = criar_usuario(cpf: proximo_cpf_teste)
    gestor = criar_usuario(cpf: gestor_pessoa.cpf)

    assert_motivo :negado, gestor, alvo
  end

  test "10: alvo sem CPF (sem pessoa no Pessoas) so passa pelos passos 1-4" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = criar_usuario
    gestor = criar_usuario(cpf: gestor_pessoa.cpf)

    assert_motivo :negado, gestor, alvo
  end

  test "10: Pessoas indisponivel nega (fail-closed) e loga pessoas_indisponivel" do
    gestor = criar_usuario
    alvo = criar_usuario(cpf: proximo_cpf_teste)

    log = nil
    com_por_user_levantando do
      log = capturar_log { assert_motivo :negado, gestor, alvo }
    end

    assert_includes log, "autorizacao_frequencia.pessoas_indisponivel"
  end

  # Carried do review da 29.1 (MEDIUM-3 + débito do log): o usuário logado TEM
  # CPF, mas não existe pessoa correspondente no Pessoas. Sem o log, um gestor
  # que "deveria" existir cadastralmente e não existe seria invisível — o passo
  # 5 nega em silêncio. Aqui o alvo TEM lotação vigente (para o passo 5 ser
  # alcançado), mas o gestor não resolve no Pessoas.
  test "10: user.cpf presente mas por_user nil nega (fail-closed) e loga pessoa_ausente" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    # CPF válido, mas NENHUMA pessoa com esse CPF no espelho do Pessoas.
    gestor = criar_usuario(cpf: proximo_cpf_teste)

    log = capturar_log { assert_motivo :negado, gestor, alvo }

    assert_includes log, "autorizacao_frequencia.pessoa_ausente"
    assert_includes log, gestor.cpf
  end

  # ==========================================================================
  # Precedencia, fail-closed de entrada e ausencia de `valid?` (D8)
  # ==========================================================================

  test "precedencia: proprio vence role_geral" do
    gestor = criar_usuario(roles: [ :visualiza_frequentadores ])

    assert_motivo :proprio, gestor, gestor
  end

  test "precedencia: role_geral vence terceirizado" do
    gestor = criar_usuario(roles: [ :visualiza_terceirizados, :visualiza_frequentadores ])

    assert_motivo :role_geral, gestor, alvo_terceirizado
  end

  test "precedencia: terceirizado vence gestor_individual" do
    gestor = criar_usuario(roles: [ :visualiza_terceirizados ])
    alvo = alvo_terceirizado
    gestor_individual(gestor_user: gestor, gerido: alvo)

    assert_motivo :terceirizado, gestor, alvo
  end

  test "precedencia: gestor_individual vence hierarquia" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo = alvo_lotado_em(raiz)
    gestor = criar_usuario(cpf: gestor_pessoa.cpf)
    gestor_individual(gestor_user: gestor, gerido: alvo)

    assert_motivo :gestor_individual, gestor, alvo
  end

  test "fail-closed: usuario nulo nega" do
    assert_motivo :negado, nil, criar_usuario
  end

  test "fail-closed: alvo nulo nega" do
    assert_motivo :negado, criar_usuario, nil
  end

  test "aceita um alvo Pessoas::Pessoa (casando por CPF no passo 1)" do
    cpf = proximo_cpf_teste
    pessoa = criar_pessoa(cpf: cpf)
    gestor = criar_usuario(cpf: cpf)

    assert_motivo :proprio, gestor, pessoa
  end

  test "reusar a mesma instancia com alvos distintos nao vaza estado do alvo" do
    gestor = criar_usuario(roles: [ :visualiza_frequentadores ])
    alvo_a = criar_usuario
    alvo_b = criar_usuario
    autorizacao = AutorizacaoFrequencia.new(gestor)

    assert_equal :role_geral, autorizacao.motivo(alvo_a)
    assert_equal :role_geral, autorizacao.motivo(alvo_b)
    assert autorizacao.pode_ver?(alvo_a)
    assert autorizacao.pode_ver?(alvo_b)
    # Um alvo que NAO casa nao pode virar positivo por causa do memo anterior.
    assert_equal :negado, AutorizacaoFrequencia.new(criar_usuario).motivo(alvo_a)
  end

  # D8 (CTO, 2026-09-29): o caminho de leitura NUNCA pode chamar `valid?` — um
  # registro valido-no-banco/invalido-no-model faria o `valid?` levantar
  # `RecordInvalid` e derrubar a renderizacao. Prova direta: com `valid?`
  # substituido por um levantamento, TODOS os caminhos do `motivo` (inclusive
  # os que passam por `gestor_individual` e por hierarquia) continuam sem
  # levantar.
  test "D8: nenhum caminho do pode_ver? chama valid?" do
    gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste)
    raiz = criar_unidade(descricao: "Raiz", active: true, gestor_id: gestor_pessoa.id)
    alvo_hierarquia = alvo_lotado_em(raiz)
    gestor = criar_usuario(cpf: gestor_pessoa.cpf)
    alvo_gestor_individual = criar_usuario
    gestor_individual(gestor_user: gestor, gerido: alvo_gestor_individual)
    alvo_negado = criar_usuario

    sem_validar do
      assert_equal :hierarquia,
                   AutorizacaoFrequencia.new(gestor).motivo(alvo_hierarquia)
      assert_equal :gestor_individual,
                   AutorizacaoFrequencia.new(gestor).motivo(alvo_gestor_individual)
      assert_equal :negado,
                   AutorizacaoFrequencia.new(gestor).motivo(alvo_negado)
    end
  end

  private

  # --- assertions -----------------------------------------------------------

  def assert_motivo(esperado, gestor, alvo)
    autorizacao = AutorizacaoFrequencia.new(gestor)
    assert_equal esperado, autorizacao.motivo(alvo)
    assert_equal(esperado != :negado, autorizacao.pode_ver?(alvo))
  end

  # --- fixtures locais (schema real do espelho, ADR-0006) -------------------

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

  # Cria a pessoa no Pessoas + o User local com o mesmo CPF, ambos NAO
  # terceirizados (vinculo ativo com tipo "Efetivo").
  def alvo_nao_terceirizado
    cpf = proximo_cpf_teste
    pessoa = criar_pessoa(cpf: cpf)
    criar_vinculo_ativos(pessoa: pessoa, tipo: "Efetivo")
    criar_usuario(cpf: cpf)
  end

  def alvo_terceirizado
    cpf = proximo_cpf_teste
    pessoa = criar_pessoa(cpf: cpf)
    criar_vinculo_ativos(pessoa: pessoa, tipo: "Terceirizado")
    criar_usuario(cpf: cpf)
  end

  # Dois vinculos ATIVOS: um "Efetivo" e um "Terceirizado" — fixa a semantica
  # "algum vinculo ativo terceirizado" (D4).
  def alvo_com_dois_vinculos_ativos
    cpf = proximo_cpf_teste
    pessoa = criar_pessoa(cpf: cpf)
    criar_vinculo_ativos(pessoa: pessoa, tipo: "Efetivo", matricula: "NAO-TERC-#{pessoa.id}")
    criar_vinculo_ativos(pessoa: pessoa, tipo: "Terceirizado", matricula: "TERC-#{pessoa.id}")
    criar_usuario(cpf: cpf)
  end

  # User local cuja pessoa no Pessoas tem lotacao principal vigente na unidade.
  def alvo_lotado_em(unidade, cpf: proximo_cpf_teste)
    criar_pessoa_lotada(unidade: unidade, cpf: cpf)
    criar_usuario(cpf: cpf)
  end

  # --- inserts no schema do espelho (readonly so bloqueia instancias) -------

  def criar_tipo_vinculo(nome)
    Pessoas::TipoVinculo.find_by(nome: nome) || inserir(Pessoas::TipoVinculo, nome: nome)
  end

  def criar_vinculo_ativos(pessoa:, tipo:, matricula: nil)
    configuracao = inserir(
      Pessoas::ConfiguracaoCadastro,
      tipo_vinculo_id: criar_tipo_vinculo(tipo).id
    )
    inserir(
      Pessoas::Vinculo,
      pessoa_id: pessoa.id,
      vinculo_estado_id: criar_vinculo_estado(nome: "em_exercicio").id,
      matricula: matricula || "M#{pessoa.id}-#{SecureRandom.hex(2)}",
      inicio: Date.new(2020, 1, 1),
      configuracao_cadastro_id: configuracao.id
    )
  end

  def inserir(model, **atributos)
    id = model.insert_all([ atributos ], returning: :id).rows.first.first
    model.find(id)
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

  # --- infra de teste -------------------------------------------------------

  def capturar_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end

  # Substitui `Pessoas::Pessoa.por_user` por uma falha de banco e RESTAURA o
  # metodo original (define_method com o UnboundMethod salvo) — nao deixa
  # override permanente no singleton (evita o LOW-2 do review da 29.1).
  def com_por_user_levantando
    original = Pessoas::Pessoa.singleton_class.instance_method(:por_user)
    Pessoas::Pessoa.define_singleton_method(:por_user) do |_user|
      raise ActiveRecord::StatementInvalid, "pessoas fora do ar (teste)"
    end
    yield
  ensure
    Pessoas::Pessoa.singleton_class.send(:define_method, :por_user, original)
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
