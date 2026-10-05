require "test_helper"

class GestorIndividualTest < ActiveSupport::TestCase
  test "valid with nome" do
    gestor = GestorIndividual.new(nome: "Fulano Gestor", orgao: "Vara Cível")
    assert gestor.valid?
  end

  test "invalid without nome" do
    gestor = GestorIndividual.new(orgao: "Vara Cível")
    assert_not gestor.valid?
    assert_includes gestor.errors[:nome], "não pode ficar em branco"
  end

  test "has many gerenciados through gestor_individual_gerenciados" do
    gestor = GestorIndividual.create!(nome: "Fulano Gestor")
    frequentador = User.create!(nome_completo: "Frequentador", password: "123456")
    GestorIndividualGerenciado.create!(gestor_individual: gestor, user: frequentador)

    assert_includes gestor.gerenciados, frequentador
  end

  test "gerenciados vazio por padrao" do
    gestor = GestorIndividual.create!(nome: "Fulano Gestor")
    assert_empty gestor.gerenciados
  end

  test "usa a tabela gestores_individuais" do
    assert_equal "gestores_individuais", GestorIndividual.table_name
  end

  # --- Tarefa 29.2: campos do legado -------------------------------------

  test "id_legado deve ser unico quando presente" do
    GestorIndividual.create!(nome: "Importado", id_legado: 501)

    duplicado = GestorIndividual.new(nome: "Importado 2", id_legado: 501)
    assert_not duplicado.valid?
    assert_includes duplicado.errors[:id_legado], "já está em uso"
  end

  test "varios registros sem id_legado sao validos" do
    gestor_a = GestorIndividual.create!(nome: "Local A")
    gestor_b = GestorIndividual.create!(nome: "Local B")

    assert gestor_a.valid?
    assert gestor_b.valid?
    assert_nil gestor_a.id_legado
    assert_nil gestor_b.id_legado
  end

  test "nasce ativo e sem data de exclusao" do
    gestor = GestorIndividual.create!(nome: "Novo Gestor")

    assert_equal true, gestor.ativo
    assert gestor.ativo?
    assert_nil gestor.data_exclusao
  end

  test "gestor_user é opcional (gestor sem login local)" do
    gestor = GestorIndividual.create!(nome: "Sem Login")
    assert_nil gestor.gestor_user
    assert gestor.valid?
  end

  # --- Bug 10 (⚪): formato de gestor_cpf ---------------------------------

  test "gestor_cpf aceita 11 dígitos e nulo, rejeita máscara e comprimento errado" do
    assert GestorIndividual.new(nome: "Com CPF", gestor_cpf: "12345678901").valid?
    assert GestorIndividual.new(nome: "Sem CPF").valid?, "gestor local não tem CPF"

    com_mascara = GestorIndividual.new(nome: "Mascarado", gestor_cpf: "123.456.789-01")
    assert_not com_mascara.valid?
    assert com_mascara.errors[:gestor_cpf].any?

    curto = GestorIndividual.new(nome: "Curto", gestor_cpf: "123")
    assert_not curto.valid?
  end

  test "gestor_user aceita o login local quando presente" do
    login = User.create!(nome_completo: "Gestor Logado", password: "123456")
    gestor = GestorIndividual.create!(nome: "Com Login", gestor_user: login)

    assert_equal login, gestor.reload.gestor_user
  end

  # --- Tarefa 29.2: soft-delete ------------------------------------------

  test "scope ativos exclui desativados" do
    ativo = GestorIndividual.create!(nome: "Ativo")
    inativo = GestorIndividual.create!(nome: "Inativo", ativo: false)

    assert_includes GestorIndividual.ativos, ativo
    assert_not_includes GestorIndividual.ativos, inativo
  end

  test "desativar! marca inativo com data e NAO apaga a linha" do
    gestor = GestorIndividual.create!(nome: "Sera Desativado")
    momento = Time.zone.local(2026, 9, 29, 10, 30)

    gestor.desativar!(momento)

    assert_not gestor.reload.ativo, "deve ficar inativo"
    assert_equal momento, gestor.data_exclusao
    assert GestorIndividual.exists?(gestor.id), "a linha não pode ser apagada (sem hard-delete)"
  end

  test "desativar! é idempotente e preserva a data da primeira exclusao" do
    gestor = GestorIndividual.create!(nome: "Ja Desativado")
    primeira = Time.zone.local(2026, 9, 29, 10, 30)
    segunda = Time.zone.local(2026, 9, 30, 8, 0)

    gestor.desativar!(primeira)
    gestor.desativar!(segunda)

    assert_equal primeira, gestor.reload.data_exclusao
  end

  # --- Bugs 5 e 6 (🟢): guard de desativar! nos estados limítrofes --------

  test "desativar! preserva data legada mesmo com a flag ativo divergente (Bug 5)" do
    # Registro legado desativado com data mas flag `ativo` ainda true: a data
    # real do Intranet NÃO pode ser sobrescrita pela data da chamada.
    legada = Time.zone.local(2020, 1, 1, 12, 0)
    gestor = GestorIndividual.create!(nome: "Legado Divergente", ativo: true, data_exclusao: legada)

    gestor.desativar!(Time.zone.local(2026, 9, 29, 10, 0))

    assert_equal legada, gestor.reload.data_exclusao, "a data legada deve ser preservada"
    assert_not gestor.ativo
  end

  test "desativar! com momento nil usa o tempo atual, não grava data nula (Bug 6)" do
    gestor = GestorIndividual.create!(nome: "Momento Nulo")

    gestor.desativar!(nil)

    assert_not gestor.reload.ativo
    assert_not_nil gestor.data_exclusao, "momento nulo não pode deixar a exclusão sem data"
  end

  test "desativar! sem argumento grava a data atual" do
    gestor = GestorIndividual.create!(nome: "Sem Argumento")

    gestor.desativar!

    assert_not_nil gestor.reload.data_exclusao
  end

  # Bug 13 do Bug Finder da 2ª rodada (🟢) — retorno consistente: sempre o
  # próprio registro, nunca o `true` do ramo de `update!`.
  test "desativar! retorna o próprio registro nos dois ramos (Bug 13)" do
    gestor = GestorIndividual.create!(nome: "Retorno Consistente")

    retorno_normal = gestor.desativar!
    assert_same gestor, retorno_normal, "o ramo de update! não pode devolver true"

    retorno_idempotente = gestor.desativar!
    assert_same gestor, retorno_idempotente, "o ramo idempotente também devolve self"
  end

  test "desativar! não afeta o gerenciado nem a linha do vínculo" do
    gestor = GestorIndividual.create!(nome: "Gestor com Gerido")
    gerido = User.create!(nome_completo: "Gerido Intacto", password: "123456")
    vinculo = GestorIndividualGerenciado.create!(gestor_individual: gestor, user: gerido)

    gestor.desativar!

    assert User.exists?(gerido.id), "o gerido não pode ser afetado"
    assert GestorIndividualGerenciado.exists?(vinculo.id), "o vínculo não pode ser apagado"
    assert vinculo.reload.ativo
  end

  # Bug 2 do Bug Finder (29.2, 🟠): `dependent: :destroy` executava hard-delete
  # em cascata dos vínculos, contornando o soft-delete. Agora é
  # `restrict_with_exception` — `destroy` do gestor com vínculos deve levantar,
  # nunca apagar o histórico.
  test "destroy do gestor é BLOQUEADO quando há vínculos (sem hard-delete em cascata)" do
    gestor = GestorIndividual.create!(nome: "Gestor Bloqueado")
    gerido = User.create!(nome_completo: "Gerido Preservado", password: "123456")
    vinculo = GestorIndividualGerenciado.create!(gestor_individual: gestor, user: gerido)

    assert_raises(ActiveRecord::DeleteRestrictionError) { gestor.destroy }

    assert GestorIndividual.exists?(gestor.id), "o gestor não pode ser apagado"
    assert GestorIndividualGerenciado.exists?(vinculo.id), "o vínculo NÃO pode ser apagado em cascata"
    assert User.exists?(gerido.id), "o gerido não pode ser afetado"
  end

  test "destroy do gestor sem vínculos continua funcionando" do
    gestor = GestorIndividual.create!(nome: "Gestor Sem Vínculo")

    gestor.destroy

    assert_not GestorIndividual.exists?(gestor.id)
  end

  # --- Bug 15 (🟢 → risco de auto-autorização): auto-gerência "tardia" -----

  test "gestor não pode ganhar login de alguém que já é seu gerido ativo (Bug 15)" do
    # Ordem natural do cadastro: cria o gestor, vincula os geridos, e SÓ DEPOIS
    # associa o login local. Antes, a validação do vínculo não era reexecutada
    # e a auto-gerência passava silenciosa.
    gerido = User.create!(nome_completo: "Futuro Gestor", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Sem Login")
    GestorIndividualGerenciado.create!(gestor_individual: gestor, user: gerido)

    gestor.gestor_user = gerido

    assert_not gestor.valid?, "dar login ao gestor não pode criar auto-gerência"
    assert_includes gestor.errors[:gestor_user_id].join, "auto-gerência"
    assert_raises(ActiveRecord::RecordInvalid) { gestor.save! }
  end

  # Bug 17 do Bug Finder da 3ª rodada (🟠) — REGRESSÃO do próprio Bug 15: como
  # a validação rodava em TODO save, um vínculo de auto-gerência "tardia" já
  # persistido travava o gestor por inteiro — não editava nem desativava pela
  # aplicação (sem caminho de recuperação in-app). O gatilho passou a ser o
  # evento que muda o invariante (registro novo ou `gestor_user_id` alterado).
  test "gestor com auto-gerência já persistida continua EDITÁVEL (Bug 17)" do
    login = User.create!(nome_completo: "Travado", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Travado", gestor_user: login)
    # Vínculo ruim criado por upsert (caminho documentado da 29.3).
    GestorIndividualGerenciado.insert_all!([ {
      gestor_individual_id: gestor.id, user_id: login.id, ativo: true,
      created_at: Time.current, updated_at: Time.current
    } ])

    gestor.reload
    assert gestor.update(nome: "Renomeado"), "renomear não pode falhar: #{gestor.errors.full_messages}"
    assert gestor.update(orgao: "Vara Nova"), "alterar orgao não pode falhar"
  end

  test "gestor com auto-gerência já persistida continua DESATIVÁVEL (Bug 17)" do
    login = User.create!(nome_completo: "Travado 2", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Travado 2", gestor_user: login)
    GestorIndividualGerenciado.insert_all!([ {
      gestor_individual_id: gestor.id, user_id: login.id, ativo: true,
      created_at: Time.current, updated_at: Time.current
    } ])

    gestor.reload.desativar!

    assert_not gestor.reload.ativo, "o soft-delete deve funcionar como saída de recuperação"
    assert_not_nil gestor.data_exclusao
  end

  test "a validação continua barrando quando o login é (re)definido (Bug 15 preservado)" do
    gerido = User.create!(nome_completo: "Gerido Ativo", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Sem Login")
    GestorIndividualGerenciado.create!(gestor_individual: gestor, user: gerido)

    gestor.gestor_user = gerido
    assert_not gestor.valid?, "mudar o login para um gerido ativo deve continuar sendo barrado"
  end

  # Fecha a lacuna de mutation testing declarada no iteration (o Bug Finder da
  # 3ª rodada provou que o ramo `else` — gestor AINDA NÃO persistido — é
  # alcançável e mortal). Aqui os vínculos estão só em memória, então a
  # validação precisa olhar o que foi construído, não o banco.
  test "gestor NOVO com vínculo em memória apontando para o próprio login é barrado" do
    login = User.create!(nome_completo: "Login e Gerido Novo", password: "123456")
    gestor = GestorIndividual.new(nome: "Gestor Novo", gestor_user: login)
    gestor.gestor_individual_gerenciados.build(user: login, ativo: true)

    assert_not gestor.valid?, "o ramo não-persistido deve acusar auto-gerência"
    assert_includes gestor.errors[:gestor_user_id].join, "auto-gerência"
  end

  test "gestor PODE ganhar login de gerido que já foi desativado (Bug 15)" do
    # Um gerido desativado não é gerenciado hoje — promover a categoria não
    # cria auto-autorização corrente, e a validação não pode ser um falso
    # positivo que trave promoções legítimas.
    antigo_gerido = User.create!(nome_completo: "Antigo Gerido", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Sem Login 2")
    vinculo = GestorIndividualGerenciado.create!(gestor_individual: gestor, user: antigo_gerido)
    vinculo.desativar!

    gestor.gestor_user = antigo_gerido

    assert gestor.valid?, "vínculo inativo não deve bloquear: #{gestor.errors.full_messages}"
    assert gestor.save
  end

  test "gestor PODE ganhar login de usuário que não é seu gerido (Bug 15)" do
    gestor = GestorIndividual.create!(nome: "Gestor Sem Login 3")
    gerido = User.create!(nome_completo: "Outro Gerido", password: "123456")
    GestorIndividualGerenciado.create!(gestor_individual: gestor, user: gerido)
    login = User.create!(nome_completo: "Login Legítimo", password: "123456")

    gestor.gestor_user = login

    assert gestor.valid?
    assert gestor.save
  end

  test "gestor sem gestor_user não é afetado pela validação (Bug 15)" do
    gestor = GestorIndividual.create!(nome: "Gestor Sem Login 4")
    gerido = User.create!(nome_completo: "Gerido Qualquer", password: "123456")
    GestorIndividualGerenciado.create!(gestor_individual: gestor, user: gerido)

    assert gestor.valid?
    assert gestor.update!(nome: "Gestor Sem Login 4 renomeado")
  end

  test "vínculo do próprio login em gestor já persistido é barrado pelo lado do vínculo (Bug 4)" do
    login = User.create!(nome_completo: "Login e Gerido", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Logado", gestor_user: login)

    vinculo = GestorIndividualGerenciado.new(gestor_individual: gestor, user: login)

    assert_not vinculo.valid?
  end

  # O invariante é guardado pelos dois lados, mas cada lado reage ao SEU evento
  # (Bug 17): o gestor acusa quando o LOGIN é definido/alterado; uma edição
  # qualquer do gestor não revalida — senão o registro fica travado.
  test "o lado do gestor acusa auto-gerência quando o login é redefinido (Bug 15 + Bug 17)" do
    login = User.create!(nome_completo: "Login Redefinido", password: "123456")
    gestor = GestorIndividual.create!(nome: "Gestor Sem Login 5")
    GestorIndividualGerenciado.create!(gestor_individual: gestor, user: login)

    gestor.gestor_user = login
    assert_not gestor.valid?, "mudar o login para um gerido ativo deve acusar"

    # E somente o evento do login revalida: renomear não reacusa (Bug 17).
    outro = GestorIndividual.create!(nome: "Outro Gestor Sem Login")
    assert outro.update(nome: "Renomeado"), "edição sem mexer no login não deve falhar"
  end
end
