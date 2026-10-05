require "test_helper"

# Tarefa 29.2 — prepara o vínculo gestor→gerido para a importação idempotente
# do Intranet (29.3): `id_legado` como chave de upsert e soft-delete do
# vínculo (não do gestor nem do usuário).
class GestorIndividualGerenciadoTest < ActiveSupport::TestCase
  setup do
    @gestor = GestorIndividual.create!(nome: "Gestor Teste")
    @gerido = User.create!(nome_completo: "Gerido Teste", password: "123456")
  end

  test "vinculo nasce ativo e sem data de exclusao" do
    vinculo = GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido)

    assert_equal true, vinculo.ativo
    assert vinculo.ativo?
    assert_nil vinculo.data_exclusao
  end

  test "id_legado deve ser unico quando presente" do
    GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido, id_legado: 301)
    outro = User.create!(nome_completo: "Outro Gerido", password: "123456")

    duplicado = GestorIndividualGerenciado.new(gestor_individual: @gestor, user: outro, id_legado: 301)
    assert_not duplicado.valid?
    assert_includes duplicado.errors[:id_legado], "já está em uso"
  end

  test "varios vinculos locais sem id_legado convivem" do
    outro = User.create!(nome_completo: "Segundo Gerido", password: "123456")

    primeiro = GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido)
    segundo = GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: outro)

    assert_nil primeiro.id_legado
    assert_nil segundo.id_legado
    assert_equal 2, GestorIndividualGerenciado.where(gestor_individual: @gestor).count
  end

  test "scope ativos exclui vinculos desativados" do
    ativo = GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido)
    outro = User.create!(nome_completo: "Gerido Inativo", password: "123456")
    inativo = GestorIndividualGerenciado.create!(
      gestor_individual: @gestor, user: outro, ativo: false
    )

    assert_includes GestorIndividualGerenciado.ativos, ativo
    assert_not_includes GestorIndividualGerenciado.ativos, inativo
  end

  test "desativar! marca inativo com data e NAO apaga a linha nem as pontas" do
    vinculo = GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido)
    momento = Time.zone.local(2026, 9, 29, 11, 0)

    vinculo.desativar!(momento)

    assert_not vinculo.reload.ativo
    assert_equal momento, vinculo.data_exclusao
    assert GestorIndividualGerenciado.exists?(vinculo.id), "o vínculo não pode ser apagado"
    assert GestorIndividual.exists?(@gestor.id), "o gestor não pode ser afetado"
    assert User.exists?(@gerido.id), "o usuário gerido não pode ser afetado"
  end

  test "desativar! é idempotente e preserva a data da primeira exclusao" do
    vinculo = GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido)
    primeira = Time.zone.local(2026, 9, 29, 11, 0)
    segunda = Time.zone.local(2026, 9, 30, 9, 0)

    vinculo.desativar!(primeira)
    vinculo.desativar!(segunda)

    assert_equal primeira, vinculo.reload.data_exclusao
  end

  # Bug 1 do Bug Finder da D7 (🟠) — REGRESSÃO do `reload` que corrigia o
  # achado 1 do Code Reviewer. A leitura do login do gestor fazia
  # `gestor.reload`, que **muta a instância do chamador** e **descarta
  # mudanças pendentes**: no caminho normal da 29.3 (carrega o gestor →
  # resolve o login → grava o vínculo, sem salvar antes) o `reload` apagava o
  # `gestor_user` atribuído e o código GRAVAVA auto-gerência ATIVA. Agora a
  # leitura soma memória + banco com `pick`, sem recarregar nada.
  test "login pendente (não salvo) não é descartado nem burla a auto-gerência (Bug 1)" do
    login = User.create!(nome_completo: "Login Pendente", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Pendente")
    gestor.gestor_user = login # atribuído, AINDA NÃO salvo

    vinculo = GestorIndividualGerenciado.new(
      gestor_individual: gestor, user: login, ativo: true
    )

    assert_not vinculo.save, "o login pendente deve ser considerado"
    assert_includes vinculo.errors[:user_id].join, "auto-gerência"
    assert_equal login.id, gestor.gestor_user_id, "o reload não pode descartar a mudança pendente"
    assert_equal 0, GestorIndividualGerenciado.where(
      gestor_individual_id: gestor.id, user_id: login.id, ativo: true
    ).count, "nenhuma auto-gerência ATIVA pode ser gravada"
  end

  test "mudanças pendentes em outros atributos sobrevivem à validação (Bug 1)" do
    login = User.create!(nome_completo: "Login Outro", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Original")
    gestor.nome = "Gestor Renomeado"
    gestor.orgao = "Vara Nova"

    GestorIndividualGerenciado.new(gestor_individual: gestor, user: login, ativo: true).valid?

    assert_equal "Gestor Renomeado", gestor.nome, "o reload descartava atributos pendentes"
    assert_equal "Vara Nova", gestor.orgao
    assert_includes gestor.changed, "nome"
  end

  test "instância stale do gestor continua sendo detectada (achado 1 do reviewer)" do
    login = User.create!(nome_completo: "Login Stale", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Stale")
    stale = GestorIndividual.find(gestor.id)
    GestorIndividual.find(gestor.id).update!(gestor_user: login) # salvo por outra instância

    vinculo = GestorIndividualGerenciado.new(gestor_individual: stale, user: login, ativo: true)

    assert_not vinculo.save, "o valor do banco deve cobrir a instância stale"
    assert_equal 0, GestorIndividualGerenciado.where(
      gestor_individual_id: gestor.id, user_id: login.id, ativo: true
    ).count
  end

  test "vínculo cujo gestor foi apagado por outra sessão não levanta RecordNotFound (Bug 2 da D7)" do
    login = User.create!(nome_completo: "Login Órfão", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Órfão")
    GestorIndividualGerenciado.create!(gestor_individual: gestor, user: login).delete
    GestorIndividual.where(id: gestor.id).delete_all

    vinculo = GestorIndividualGerenciado.new(gestor_individual: gestor, user: login, ativo: true)

    # O `pick` devolve nil em vez de estourar RecordNotFound no callback.
    assert vinculo.valid?, "gestor ausente não pode derrubar a validação: #{vinculo.errors.full_messages}"
  end

  # Achado 2 e 10 do Code Reviewer (2026-09-29) — a associação `gerenciados`
  # devolve TODOS os vínculos (inclusive inativos), e como o índice UNIQUE
  # parcial permite que o mesmo par exista várias vezes (inativo antigo +
  # ativo novo), o mesmo usuário aparece DUPLICADO. `gerenciados.size` é
  # consumido por `app/views/admin/gestores_individuais/index.html.erb:28`
  # ("Gerenciados"), que passaria a contar a mesma pessoa duas vezes.
  #
  # Comportamento mantido de propósito na 29.2 (a associação não filtra por
  # `ativos`; quem consome escolhe o scope), mas AGORA está travado por um
  # teste cujo nome descreve o comportamento real — o teste anterior tinha
  # nome contradizendo a própria asserção (achado 10).
  test "gestor.gerenciados nao filtra por ativos e pode DUPLICAR o mesmo usuario" do
    vinculo = GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido)
    vinculo.desativar!
    # Re-vínculo do mesmo par: permitido pelo índice parcial (histórico).
    GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido)

    gerenciados = @gestor.reload.gerenciados

    assert_includes gerenciados, @gerido
    assert_equal 2, gerenciados.size,
                 "a associação devolve as duas linhas (inativa + ativa) — débito da 29.4"
    assert_equal 1, gerenciados.uniq.size, "ambas apontam para o MESMO usuário"
  end

  test "vínculo desativado continua na associação gerenciados (scope é do consumidor)" do
    vinculo = GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido)
    vinculo.desativar!

    assert_includes @gestor.reload.gerenciados, @gerido
  end

  # --- Bug 3 (🟡): um único vínculo ATIVO por par gestor→gerido -----------

  test "segundo vínculo ATIVO do mesmo par é rejeitado com erro claro" do
    GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido)

    duplicado = GestorIndividualGerenciado.new(gestor_individual: @gestor, user: @gerido)

    assert_not duplicado.valid?
    assert duplicado.errors[:user_id].any?, "deve acusar erro no par já vinculado"
  end

  test "re-vincular o mesmo par após desativar é permitido (histórico preservado)" do
    antigo = GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido)
    antigo.desativar!

    novo = GestorIndividualGerenciado.new(gestor_individual: @gestor, user: @gerido)

    assert novo.valid?, "vínculo inativo não pode bloquear o re-vínculo"
    assert novo.save
    assert_equal 2, GestorIndividualGerenciado.where(gestor_individual: @gestor, user: @gerido).count
  end

  # Bug 12 do Bug Finder da 29.2, 2ª rodada (🟡) — a validação de par deve
  # espelhar o índice PARCIAL do banco nos quatro quadrantes. O caso que
  # faltava: criar um vínculo NOVO **INATIVO** quando já existe um ATIVO do
  # mesmo par (é o dado histórico que a importação da 29.3 traz do Intranet).
  # Antes, o Rails barrava com "User já está em uso" embora o banco aceitasse.
  test "vínculo NOVO INATIVO é aceito quando o par já tem um ATIVO (Bug 12)" do
    GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido)

    historico = GestorIndividualGerenciado.new(
      gestor_individual: @gestor, user: @gerido,
      ativo: false, data_exclusao: Time.zone.local(2020, 1, 1)
    )

    assert historico.valid?,
           "vínculo inativo (histórico legado) não pode ser barrado por par ativo existente: #{historico.errors.full_messages}"
    assert historico.save, "a importação da 29.3 precisa gravar o vínculo histórico"
    assert_equal 1, GestorIndividualGerenciado.where(
      gestor_individual: @gestor, user: @gerido, ativo: true
    ).count
  end

  test "vínculo NOVO ATIVO continua barrado quando o par já tem ATIVO (Bug 3 preservado)" do
    GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido)

    duplicado_ativo = GestorIndividualGerenciado.new(gestor_individual: @gestor, user: @gerido)

    assert_not duplicado_ativo.valid?, "a regra de um único vínculo ATIVO por par deve continuar valendo"
  end

  test "vínculo NOVO ATIVO é aceito quando o par só tem INATIVO" do
    antigo = GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido)
    antigo.desativar!

    reativado = GestorIndividualGerenciado.new(gestor_individual: @gestor, user: @gerido)

    assert reativado.valid?
    assert reativado.save
  end

  test "dois vínculos INATIVOS do mesmo par convivem (histórico)" do
    primeiro = GestorIndividualGerenciado.create!(
      gestor_individual: @gestor, user: @gerido, ativo: false, data_exclusao: Time.zone.local(2020, 1, 1)
    )
    segundo = GestorIndividualGerenciado.new(
      gestor_individual: @gestor, user: @gerido, ativo: false, data_exclusao: Time.zone.local(2021, 1, 1)
    )

    assert segundo.valid?
    assert primeiro.persisted?
  end

  test "vínculos de pares diferentes continuam válidos" do
    outro = User.create!(nome_completo: "Outro Par", password: "123456")

    primeiro = GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: @gerido)
    segundo = GestorIndividualGerenciado.create!(gestor_individual: @gestor, user: outro)

    assert primeiro.persisted?
    assert segundo.persisted?
  end

  # --- Bug 4 (🟡): auto-gerência ------------------------------------------

  test "gestor não pode ser gerido de si mesmo" do
    gestor_logado = User.create!(nome_completo: "Gestor De Si", password: "123456")
    gestor = GestorIndividual.create!(nome: "Auto Gestor", gestor_user: gestor_logado)

    auto_vinculo = GestorIndividualGerenciado.new(gestor_individual: gestor, user: gestor_logado)

    assert_not auto_vinculo.valid?
    assert_includes auto_vinculo.errors[:user_id].join, "auto-gerência"
  end

  # Bug 18 do Bug Finder da 3ª rodada (🟠) — ASSIMETRIA INVERSA: o lado do
  # gestor ignora vínculos INATIVOS (promover ex-gerido é legítimo desde o Bug
  # 15) e o banco também, mas este lado barrava o inativo — os dois lados
  # discordavam e a 29.3 não conseguiria reconciliar o vínculo histórico via
  # ActiveRecord. O invariante agora é idêntico nos dois lados: nenhum vínculo
  # ATIVO liga o gestor a si mesmo.
  test "vínculo INATIVO de auto-gerência é permitido (histórico legado) — Bug 18" do
    login = User.create!(nome_completo: "Ex Gerido", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Ex Gerido")
    vinculo = GestorIndividualGerenciado.create!(gestor_individual: gestor, user: login)
    vinculo.desativar!
    gestor.update!(gestor_user: login)

    assert vinculo.reload.valid?, "vínculo inativo não é auto-autorização corrente"
    assert vinculo.save, "a 29.3 precisa poder reescrever o vínculo histórico"
    assert_equal false, vinculo.ativo
  end

  test "vínculo NOVO INATIVO de auto-gerência é permitido — Bug 18" do
    login = User.create!(nome_completo: "Ex Gerido 2", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Ex Gerido 2", gestor_user: login)

    historico = GestorIndividualGerenciado.new(
      gestor_individual: gestor, user: login,
      ativo: false, data_exclusao: Time.zone.local(2020, 1, 1)
    )

    assert historico.valid?, "dado histórico legado: #{historico.errors.full_messages}"
  end

  test "vínculo ATIVO de auto-gerência continua barrado nos dois lados — Bug 18 preserva Bug 4" do
    login = User.create!(nome_completo: "Ativo Auto", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Ativo Auto", gestor_user: login)

    ativo = GestorIndividualGerenciado.new(gestor_individual: gestor, user: login)

    assert_not ativo.valid?, "auto-gerência ATIVA deve continuar barrada"
    assert gestor.valid?, "e o lado do gestor concorda"
  end

  test "gestor sem login local pode ter vínculos normalmente (sem falso positivo)" do
    gestor = GestorIndividual.create!(nome: "Gestor Sem Login", gestor_cpf: "12345678901")
    vinculo = GestorIndividualGerenciado.new(gestor_individual: gestor, user: @gerido)

    assert vinculo.valid?, "sem gestor_user não há auto-gerência a bloquear"
  end

  test "outro usuário pode ser gerido por gestor que tem login local" do
    gestor_logado = User.create!(nome_completo: "Gestor Logado", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Com Login", gestor_user: gestor_logado)

    vinculo = GestorIndividualGerenciado.create!(gestor_individual: gestor, user: @gerido)

    assert vinculo.persisted?
  end
end
