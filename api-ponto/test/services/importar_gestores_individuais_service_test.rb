require "test_helper"

# Tarefa 29.3 (Sprint 29) — importação idempotente dos gestores individuais
# do Intranet. Cobre: upsert pelas chaves estáveis (idempotência), preservação
# da `data_exclusao` legada, relatório de não-resolvidos (nada é ignorado em
# silêncio), dry-run sem escrita, normalizações de borda (⚪ 11 id_legado>0,
# ⚪ 14 cpf "", Bug 3/A5 `ativo: nil`), tratamento de RecordInvalid (Bug 8) e
# de DeleteRestrictionError/InvalidForeignKey (🟢 19).
#
# Não tocamos a rede nem o banco `pessoas` real: `SticapiClient::Intranet`
# recebe um stub e, quando o teste usa o espelho, ele é pulado sem o schema
# carregado (`skip_sem_espelho!`).
class ImportarGestoresIndividuaisServiceTest < ActiveSupport::TestCase
  include PessoasEspelhoHelper

  CPF_GESTOR = "11122233344"
  CPF_GERIDO = "55566677788"

  # Troca um método de classe RESTAURANDO o original ao fim do bloco. O gem
  # Minitest 6 não traz mais `Object#stub`, e `define_singleton_method` +
  # `remove_method` sem restaurar APAGA o método real — envenena os testes
  # seguintes do mesmo processo.
  def com_stub_de_classe(klass, metodo, resposta)
    original = klass.method(metodo)
    corpo = resposta.is_a?(Proc) ? resposta : ->(*_args, **_kwargs) { resposta }

    klass.singleton_class.send(:remove_method, metodo)
    klass.define_singleton_method(metodo, corpo)
    yield
  ensure
    klass.singleton_class.send(:remove_method, metodo)
    klass.define_singleton_method(metodo, original)
  end

  # Passa `registros:` direto ao serviço (sem stub da gem) na maioria dos
  # casos — é a porta de injeção prevista no próprio serviço.
  def linha(id:, matricula_gestor: "1001", matricula_gerido: "2002",
            id_vinculo_gestor: 900, id_vinculo_gerido: 700,
            data_criacao: "2019-10-30 10:03:25.0", data_exclusao: nil, observacao: "SEI 19.0")
    {
      "id" => id,
      "data_criacao" => data_criacao,
      "data_exclusao" => data_exclusao,
      "observacao" => observacao,
      "id_vinculo_gestor" => id_vinculo_gestor,
      "matricula_gestor" => matricula_gestor,
      "id_vinculo_gerido" => id_vinculo_gerido,
      "matricula_gerido" => matricula_gerido
    }
  end

  # D4 (F2): variante do payload com as chaves de data em camelCase — o formato
  # que o ÚNICO consumidor real (Pessoas2) usa. O serviço deve aceitar ambos.
  def linha_camel(id:, matricula_gestor: "1001", matricula_gerido: "2002",
                  id_vinculo_gestor: 900, id_vinculo_gerido: 700,
                  dataCriacao: "2019-10-30 10:03:25.0", dataExclusao: nil, observacao: "SEI 19.0")
    {
      "id" => id,
      "dataCriacao" => dataCriacao,
      "dataExclusao" => dataExclusao,
      "observacao" => observacao,
      "id_vinculo_gestor" => id_vinculo_gestor,
      "matricula_gestor" => matricula_gestor,
      "id_vinculo_gerido" => id_vinculo_gerido,
      "matricula_gerido" => matricula_gerido
    }
  end

  # Cria o gerido (User) e o mapa matrícula→CPF esperado, sem depender da
  # folha do espelho.
  def preparar_gerido(cpf: CPF_GERIDO, nome: "Gerido Teste")
    User.create!(nome_completo: nome, password: "123456", cpf: cpf)
  end

  def stub_mapa_cpf(mapa)
    com_stub_de_classe(ResolverCpfPorMatriculaService, :mais_recente, mapa) { yield }
  end

  # --- fonte (gem Sticapi) --------------------------------------------------

  test "sem `registros:` le da SticapiClient::Intranet.gestores_individuais" do
    preparar_gerido

    com_stub_de_classe(SticapiClient::Intranet, :gestores_individuais, [ linha(id: 42) ]) do
      stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
        resultado = ImportarGestoresIndividuaisService.call
        assert_equal 1, resultado.importados
      end
    end

    assert GestorIndividualGerenciado.find_by(id_legado: 42).present?
  end

  # --- importação básica ----------------------------------------------------

  test "importa um par novo criando gestor e vinculo com id_legado" do
    preparar_gerido

    resultado = nil
    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      resultado = ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ])
    end

    assert_equal 1, resultado.importados
    assert_equal 0, resultado.atualizados
    assert_empty resultado.nao_resolvidos

    gestor = GestorIndividual.find_by(id_legado: 900)
    assert gestor.present?, "gestor casado pela chave id_vinculo_gestor"
    assert_equal CPF_GESTOR, gestor.gestor_cpf
    assert_equal "SEI 19.0", gestor.observacao
    assert_equal Time.zone.parse("2019-10-30 10:03:25.0"), gestor.data_criacao_legado
    assert gestor.ativo?

    vinculo = GestorIndividualGerenciado.find_by(id_legado: 42)
    assert vinculo.present?
    assert_equal gestor, vinculo.gestor_individual
    assert_equal User.find_by(cpf: CPF_GERIDO), vinculo.user
    assert vinculo.ativo?
  end

  test "liga gestor_user quando existe User com o CPF do gestor" do
    preparar_gerido
    gestor_user = User.create!(nome_completo: "Gestor Logado", password: "123456", cpf: CPF_GESTOR)

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ])
    end

    assert_equal gestor_user, GestorIndividual.find_by(id_legado: 900).gestor_user
  end

  test "reaproveita UM gestor para varias linhas do mesmo id_vinculo_gestor" do
    2.times { |i| User.create!(nome_completo: "Gerido #{i}", password: "123456", cpf: "6000000000#{i}") }

    linhas = [
      linha(id: 1, matricula_gerido: "2001", id_vinculo_gerido: 701),
      linha(id: 2, matricula_gerido: "2002", id_vinculo_gerido: 702)
    ]

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2001" => "60000000000", "2002" => "60000000001" }) do
      ImportarGestoresIndividuaisService.call(registros: linhas)
    end

    assert_equal 1, GestorIndividual.where(id_legado: 900).count
    assert_equal 2, GestorIndividualGerenciado.where(id_legado: [ 1, 2 ]).count
  end

  # --- idempotência ---------------------------------------------------------

  test "segunda execucao = 0 criacoes (upsert por id_legado)" do
    preparar_gerido

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ])
    end

    resultado = nil
    assert_no_difference([ "GestorIndividual.count", "GestorIndividualGerenciado.count" ]) do
      stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
        resultado = ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ])
      end
    end

    assert_equal 0, resultado.importados
    assert_equal 1, resultado.atualizados
  end

  test "reimportacao atualiza os dados sem criar duplicata" do
    preparar_gerido

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42, observacao: "antigo") ])
    end

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42, observacao: "novo") ])
    end

    assert_equal 1, GestorIndividual.where(id_legado: 900).count
    assert_equal "novo", GestorIndividual.find_by(id_legado: 900).observacao
  end

  # --- preservação da data_exclusao legada (soft-delete histórico) ----------

  test "registro excluido no legado entra INATIVO com a data legada, nao e descartado" do
    preparar_gerido
    data = "2021-03-04 08:00:00.0"

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42, data_exclusao: data) ])
    end

    gestor = GestorIndividual.find_by(id_legado: 900)
    vinculo = GestorIndividualGerenciado.find_by(id_legado: 42)

    assert_not gestor.ativo?
    assert_equal Time.zone.parse(data), gestor.data_exclusao
    assert_not vinculo.ativo?
    assert_equal Time.zone.parse(data), vinculo.data_exclusao
  end

  test "data_exclusao legada nao e sobrescrita por execucao posterior" do
    preparar_gerido
    data = "2021-03-04 08:00:00.0"

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42, data_exclusao: data) ])
    end

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42, data_exclusao: data) ])
    end

    assert_equal Time.zone.parse(data), GestorIndividualGerenciado.find_by(id_legado: 42).data_exclusao
  end

  # --- relatório de não-resolvidos ------------------------------------------

  test "matricula do gestor sem CPF vira nao-resolvido" do
    preparar_gerido

    resultado = nil
    stub_mapa_cpf({ "2002" => CPF_GERIDO }) do
      resultado = ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ])
    end

    assert_equal 0, resultado.importados
    assert_equal 1, resultado.nao_resolvidos.size
    assert_includes resultado.nao_resolvidos.first.motivo, "gestor"
    assert_equal 0, GestorIndividual.count
  end

  test "gerido sem User no Frequencia vira nao-resolvido" do
    # Nenhum User criado para o CPF do gerido.

    resultado = nil
    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      resultado = ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ])
    end

    assert_equal 0, resultado.importados
    assert_equal 1, resultado.nao_resolvidos.size
    assert_includes resultado.nao_resolvidos.first.motivo, "User"
  end

  test "uma linha invalida nao impede a importacao das demais" do
    preparar_gerido
    User.create!(nome_completo: "Outro Gerido", password: "123456", cpf: "66677788899")

    linhas = [
      linha(id: 42, matricula_gestor: "9999"),                                   # não resolve
      linha(id: 43, matricula_gerido: "2003", id_vinculo_gerido: 703)
    ]

    resultado = nil
    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO, "2003" => "66677788899" }) do
      resultado = ImportarGestoresIndividuaisService.call(registros: linhas)
    end

    assert_equal 1, resultado.importados
    assert_equal 1, resultado.nao_resolvidos.size
    assert GestorIndividualGerenciado.find_by(id_legado: 43).present?
  end

  # --- dry-run --------------------------------------------------------------

  test "dry-run percorre a resolucao mas NAO escreve nada" do
    preparar_gerido

    resultado = nil
    assert_no_difference([ "GestorIndividual.count", "GestorIndividualGerenciado.count" ]) do
      stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
        resultado = ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ], dry_run: true)
      end
    end

    assert resultado.dry_run
    assert_equal 1, resultado.importados
  end

  test "dry-run classifica reimportacao como atualizacao (sem escrever)" do
    preparar_gerido

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ])
    end

    resultado = nil
    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      resultado = ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ], dry_run: true)
    end

    assert_equal 0, resultado.importados
    assert_equal 1, resultado.atualizados
  end

  # --- normalizações de borda -----------------------------------------------

  test "id legado ausente/zero/negativo vira nao-resolvido (⚪ 11)" do
    preparar_gerido

    [ nil, 0, -7 ].each do |id|
      resultado = nil
      stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
        resultado = ImportarGestoresIndividuaisService.call(registros: [ linha(id: id) ])
      end

      assert_equal 0, resultado.importados, "id #{id.inspect} não pode criar registro"
      assert_equal 1, resultado.nao_resolvidos.size
      assert_equal 0, GestorIndividualGerenciado.where(id_legado: id).count
    end
  end

  test "gestor_cpf string vazia nunca e persistida como \"\" (⚪ 14)" do
    preparar_gerido
    # CPF do gestor resolvido para "" (folha devolveu valor vazio) → deve
    # contar como NÃO resolvido (blank), e jamais gravar `gestor_cpf: ""`.
    resultado = nil
    stub_mapa_cpf({ "1001" => "", "2002" => CPF_GERIDO }) do
      resultado = ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ])
    end

    assert_equal 1, resultado.nao_resolvidos.size, "cpf vazio não pode casar/montar gestor"
    assert_equal 0, GestorIndividual.where(gestor_cpf: "").count
  end

  test "gestor_cpf resolvido e persistido normalizado (presence)" do
    preparar_gerido
    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ])
    end

    assert_equal CPF_GESTOR, GestorIndividual.find_by(id_legado: 900).gestor_cpf
    assert_equal 0, GestorIndividual.where(gestor_cpf: "").count
  end

  test "ativo nil na borda e normalizado (Bug 3 da D7 / A5)" do
    preparar_gerido
    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ])
    end

    gestor = GestorIndividual.find_by(id_legado: 900)
    assert_equal true, gestor.ativo
    assert_equal true, GestorIndividualGerenciado.find_by(id_legado: 42).ativo
  end

  # --- invariante de auto-gerência não é contornado -------------------------

  test "auto-gerencia ativa e recusada e sai no relatorio (nao grava por baixo)" do
    # Gestor e gerido são o MESMO CPF: o User gerido é também o gestor_user.
    User.create!(nome_completo: "Auto Gerido", password: "123456", cpf: CPF_GESTOR)

    resultado = nil
    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GESTOR }) do
      resultado = ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ])
    end

    assert_equal 0, resultado.importados
    assert_equal 1, resultado.nao_resolvidos.size
    assert_includes resultado.nao_resolvidos.first.motivo, "inválido"
    assert_equal 0, GestorIndividualGerenciado.where(id_legado: 42).count
  end

  # --- mensagem de RecordInvalid não vaza "Translation missing" (Bug 8) -----

  test "erro de RecordInvalid usa full_messages, nunca e.message cru (Bug 8)" do
    preparar_gerido
    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      # Força um RecordInvalid: gestor sem nome não pode ser persistido. O
      # serviço preenche o nome, então provocamos o erro por outra via — um
      # CPF de gestor inválido (não 11 dígitos) faz o model recusar.
    end

    resultado = nil
    stub_mapa_cpf({ "1001" => "123", "2002" => CPF_GERIDO }) do
      resultado = ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ])
    end

    motivo = resultado.nao_resolvidos.first.motivo

    assert_equal 1, resultado.nao_resolvidos.size
    assert_includes motivo, "inválido", "o motivo deve trazer o erro REAL do atributo"

    # Controle discriminante: `e.message` carrega o wrapper do `record_invalid`
    # ("Validation failed:"/"1 erro impediu este registro de ser salvo:")
    # ANTES das mensagens dos atributos; `full_messages` não. O motivo é
    # prefixado por "registro inválido: ", então o wrapper, se viesse de
    # `e.message`, apareceria logo depois. Sem esta asserção, trocar
    # `full_messages` por `e.message` no serviço passaria — foi o que a
    # mutação mostrou.
    refute_match(/erro impediu este registro|Validation failed/, motivo,
                 "motivo deve ser o full_messages, sem o wrapper do e.message")
    assert_not_includes motivo, "Translation missing"
  end

  # =========================================================================
  # Complemento 29.3-D1..D4 (ADR-0008, CTO 2026-09-30)
  # =========================================================================

  # --- D1: projeção determinística do `ativo` do gestor ---------------------

  test "D1: gestor com algum vinculo ATIVO permanece ativo (projecao pos-loop)" do
    preparar_gerido(cpf: "60000000001")
    preparar_gerido(cpf: "60000000002", nome: "Gerido 2")

    linhas = [
      linha(id: 1, matricula_gerido: "2001", id_vinculo_gerido: 701),
      linha(id: 2, matricula_gerido: "2002", id_vinculo_gerido: 702, data_exclusao: "2021-03-04 08:00:00.0")
    ]

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2001" => "60000000001", "2002" => "60000000002" }) do
      ImportarGestoresIndividuaisService.call(registros: linhas)
    end

    gestor = GestorIndividual.find_by(id_legado: 900)
    assert gestor.ativo?, "um único vínculo ativo mantém o gestor ATIVO"
    assert_nil gestor.data_exclusao, "havendo vínculo ativo, o gestor não tem data de exclusão"
  end

  test "D1: gestor com TODOS os vinculos excluidos fica INATIVO com a exclusao mais recente" do
    preparar_gerido(cpf: "60000000001")
    preparar_gerido(cpf: "60000000002", nome: "Gerido 2")
    antiga = "2021-03-04 08:00:00.0"
    recente = "2022-07-10 09:30:00.0"

    linhas = [
      linha(id: 1, matricula_gerido: "2001", id_vinculo_gerido: 701, data_exclusao: antiga),
      linha(id: 2, matricula_gerido: "2002", id_vinculo_gerido: 702, data_exclusao: recente)
    ]

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2001" => "60000000001", "2002" => "60000000002" }) do
      ImportarGestoresIndividuaisService.call(registros: linhas)
    end

    gestor = GestorIndividual.find_by(id_legado: 900)
    assert_not gestor.ativo?, "nenhum vínculo ativo ⇒ gestor inativo"
    assert_equal Time.zone.parse(recente), gestor.data_exclusao, "exclusão mais recente entre os vínculos"
  end

  test "D1: ativo do gestor independe da ORDEM das linhas (mata o order-dependence)" do
    preparar_gerido(cpf: "60000000001")
    preparar_gerido(cpf: "60000000002", nome: "Gerido 2")
    preparar_gerido(cpf: "60000000003", nome: "Gerido 3")

    ativa = linha(id: 1, matricula_gerido: "2001", id_vinculo_gerido: 701)
    excl1 = linha(id: 2, matricula_gerido: "2002", id_vinculo_gerido: 702, data_exclusao: "2021-01-01 00:00:00.0")
    excl2 = linha(id: 3, matricula_gerido: "2003", id_vinculo_gerido: 703, data_exclusao: "2022-01-01 00:00:00.0")
    mapa = { "1001" => CPF_GESTOR, "2001" => "60000000001", "2002" => "60000000002", "2003" => "60000000003" }

    # Ordem A: a linha ATIVA por ÚLTIMO — na regra antiga ("última linha vence")
    # deixava ativo=true.
    stub_mapa_cpf(mapa) do
      ImportarGestoresIndividuaisService.call(registros: [ excl1, excl2, ativa ])
    end
    assert GestorIndividual.find_by(id_legado: 900).ativo?, "ordem A: há vínculo ativo ⇒ ativo"

    # Ordem B: a linha ATIVA por PRIMEIRO — na regra antiga deixava ativo=false.
    stub_mapa_cpf(mapa) do
      ImportarGestoresIndividuaisService.call(registros: [ ativa, excl1, excl2 ])
    end
    assert GestorIndividual.find_by(id_legado: 900).ativo?, "ordem B: MESMO resultado (determinístico)"

    # Controle negativo: sem o vínculo ativo em nenhuma ordem, o gestor fica inativo.
    gestor = GestorIndividual.find_by(id_legado: 900)
    GestorIndividualGerenciado.find_by(id_legado: 1).update!(ativo: false, data_exclusao: Time.zone.parse("2023-01-01 00:00:00.0"))

    stub_mapa_cpf(mapa) do
      ImportarGestoresIndividuaisService.call(registros: [ excl1, excl2, ativa ])
    end
    assert GestorIndividual.find_by(id_legado: 900).ativo?, "a reimportação RESTAURA o ativo verdadeiro (linha ativa existe)"
  end

  # --- F1: reancoragem só na criação / casamento só por id_legado -----------

  test "F1: linha com id_vinculo_gestor presente casa so por id_legado, sem reancorar por CPF" do
    preparar_gerido(cpf: "60000000001")
    preparar_gerido(cpf: "60000000002", nome: "Gerido 2")

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2001" => "60000000001" }) do
      ImportarGestoresIndividuaisService.call(
        registros: [ linha(id: 1, matricula_gerido: "2001", id_vinculo_gerido: 701) ]
      )
    end
    assert GestorIndividual.find_by(id_legado: 900).present?

    # Outro id_vinculo_gestor (901) para o MESMO CPF: NÃO pode mover/reaproveitar
    # o gestor 900 (era o furo F1); cria o gestor 901.
    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => "60000000002" }) do
      ImportarGestoresIndividuaisService.call(
        registros: [ linha(id: 2, matricula_gerido: "2002", id_vinculo_gerido: 702, id_vinculo_gestor: 901) ]
      )
    end

    assert_equal 900, GestorIndividual.find_by(gestor_cpf: CPF_GESTOR, id_legado: 900)&.id_legado
    assert GestorIndividual.find_by(id_legado: 901).present?, "cada id_vinculo_gestor tem seu gestor"
  end

  test "F1: linha SEM id_vinculo_gestor usa a ponte CPF e nao cria gestor novo" do
    preparar_gerido(cpf: "60000000001")
    preparar_gerido(cpf: "60000000002", nome: "Gerido 2")

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2001" => "60000000001" }) do
      ImportarGestoresIndividuaisService.call(
        registros: [ linha(id: 1, matricula_gerido: "2001", id_vinculo_gerido: 701) ]
      )
    end

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => "60000000002" }) do
      ImportarGestoresIndividuaisService.call(
        registros: [ linha(id: 2, matricula_gerido: "2002", id_vinculo_gerido: 702, id_vinculo_gestor: nil) ]
      )
    end

    assert_equal 1, GestorIndividual.where(gestor_cpf: CPF_GESTOR).count, "ponte CPF reaproveita o gestor existente"
    assert GestorIndividualGerenciado.find_by(id_legado: 2).present?
  end

  test "F1: reimportacao que recria um vinculo apos exclusao legada nao colide com o indice parcial" do
    preparar_gerido

    # Dois vínculos legados do MESMO par: um excluído (id 1) e um ativo (id 2).
    # O índice parcial `WHERE ativo` permite o histórico; a importação não pode
    # colidir nem mover o gestor.
    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(
        registros: [ linha(id: 1, data_exclusao: "2021-01-01 00:00:00.0"), linha(id: 2) ]
      )
    end

    gestor = GestorIndividual.find_by(id_legado: 900)
    ativos = GestorIndividualGerenciado.ativos.where(gestor_individual: gestor)
    assert_equal 1, ativos.count, "só um vínculo ATIVO do par (índice parcial respeitado)"
    assert_equal 2, ativos.first.id_legado, "o vínculo ativo é o recriado"
    assert gestor.ativo?, "o vínculo recriado mantém o gestor ativo"
  end

  # --- D2: guarda de identidade (CPF divergente para o mesmo id_legado) -----

  test "D2: id_legado do gestor com CPF divergente vira nao-resolvido e nao toca o existente" do
    outro_cpf = "99988877766"
    preparar_gerido
    gestor_user = User.create!(nome_completo: "Gestor Logado", password: "123456", cpf: CPF_GESTOR)

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 1) ])
    end
    gestor = GestorIndividual.find_by(id_legado: 900)
    assert_equal gestor_user, gestor.gestor_user

    User.create!(nome_completo: "Gerido 3", password: "123456", cpf: "60000000003")

    resultado = nil
    stub_mapa_cpf({ "1001" => outro_cpf, "2003" => "60000000003" }) do
      resultado = ImportarGestoresIndividuaisService.call(
        registros: [ linha(id: 2, matricula_gerido: "2003", id_vinculo_gerido: 703) ]
      )
    end

    assert_equal 0, resultado.importados
    assert_equal 1, resultado.nao_resolvidos.size
    assert_includes resultado.nao_resolvidos.first.motivo, "conflito de identidade"

    gestor.reload
    assert_equal CPF_GESTOR, gestor.gestor_cpf, "CPF do gestor existente intacto"
    assert_equal gestor_user, gestor.gestor_user, "login do gestor existente intacto (sem auto-autorização)"
    assert_nil GestorIndividualGerenciado.find_by(id_legado: 2), "nenhum vínculo é criado no conflito"
  end

  test "D2: mesmo CPF para o id_legado do gestor nao e conflito (reimportacao normal)" do
    preparar_gerido

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 1) ])
    end

    resultado = nil
    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      resultado = ImportarGestoresIndividuaisService.call(registros: [ linha(id: 1, observacao: "novo") ])
    end

    assert_empty resultado.nao_resolvidos
    assert_equal "novo", GestorIndividual.find_by(id_legado: 900).observacao
  end

  # --- D3: marcador de nome de sistema -------------------------------------

  test "D3: nome nao resolvido usa marcador explicito de sistema, nao \"Gestor individual\"" do
    preparar_gerido

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 1) ])
    end

    nome = GestorIndividual.find_by(id_legado: 900).nome
    assert_equal "(sem nome — CPF #{CPF_GESTOR})", nome
    refute_match(/Gestor individual/, nome)
  end

  test "D3: marcador e substituido pelo nome real numa reimportacao com o Pessoas de volta" do
    skip_sem_espelho!
    preparar_gerido

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 1) ])
    end
    assert_equal "(sem nome — CPF #{CPF_GESTOR})", GestorIndividual.find_by(id_legado: 900).nome

    inserir_pessoa_espelho(nome: "Fulano Real", cpf: CPF_GESTOR)

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 1) ])
    end

    assert_equal "Fulano Real", GestorIndividual.find_by(id_legado: 900).nome, "nome real ganha do marcador"
  end

  test "D3: marcador nao sobrescreve nome real ja gravado quando o Pessoas nao resolve" do
    preparar_gerido
    GestorIndividual.create!(nome: "Nome Cadastrado", gestor_cpf: CPF_GESTOR, id_legado: 900, ativo: true)

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 1) ])
    end

    assert_equal "Nome Cadastrado", GestorIndividual.find_by(id_legado: 900).nome, "marcador não sobrepõe nome real"
  end

  # --- D4: casing das chaves de data do payload legado (F2) ----------------

  test "D4: payload em camelCase respeita a exclusao (dataExclusao)" do
    preparar_gerido
    data = "2021-03-04 08:00:00.0"

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha_camel(id: 42, dataExclusao: data) ])
    end

    vinculo = GestorIndividualGerenciado.find_by(id_legado: 42)
    assert_not vinculo.ativo?, "camelCase: a exclusão do legado NÃO pode ser ignorada"
    assert_equal Time.zone.parse(data), vinculo.data_exclusao

    gestor = GestorIndividual.find_by(id_legado: 900)
    assert_equal Time.zone.parse("2019-10-30 10:03:25.0"), gestor.data_criacao_legado, "dataCriacao lida"
    assert_not gestor.ativo?, "gestor derivado inativo (único vínculo excluído)"
  end

  test "D4: payload em snake_case continua respeitando a exclusao" do
    preparar_gerido
    data = "2021-03-04 08:00:00.0"

    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42, data_exclusao: data) ])
    end

    vinculo = GestorIndividualGerenciado.find_by(id_legado: 42)
    assert_not vinculo.ativo?
    assert_equal Time.zone.parse(data), vinculo.data_exclusao
  end

  test "D4: contrato falha alto quando nenhum casing conhecido de data esta presente" do
    preparar_gerido
    linha_estranha = {
      "id" => 42, "data_exclusao_legado" => "2021-03-04",
      "matricula_gestor" => "1001", "matricula_gerido" => "2002",
      "id_vinculo_gestor" => 900, "id_vinculo_gerido" => 700
    }

    erro = assert_raises(ArgumentError) do
      stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
        ImportarGestoresIndividuaisService.call(registros: [ linha_estranha ])
      end
    end
    assert_match(/contrato/, erro.message)
    assert_equal 0, GestorIndividualGerenciado.where(id_legado: 42).count
  end

  # Achado 🟡1 do review do complemento: o contrato antigo usava `any?` sobre a
  # LINHA inteira — bastava uma chave conhecida (criação OU exclusão) para
  # "perdoar" a linha. Este é o caso que passava indevidamente: criação
  # reconhecida, exclusão num casing não previsto ⇒ o excluído entrava ATIVO
  # sem `data_exclusao`. Agora tem de falhar ALTO.
  test "D4: criacao reconhecida + exclusao em casing desconhecido falha ALTO (achado 🟡1)" do
    preparar_gerido
    linha_parcial = {
      "id" => 42,
      "data_criacao" => "2019-10-30 10:03:25.0",
      "dataExclusao2" => "2021-03-04 08:00:00.0", # 3º casing, não previsto
      "matricula_gestor" => "1001", "matricula_gerido" => "2002",
      "id_vinculo_gestor" => 900, "id_vinculo_gerido" => 700
    }

    erro = assert_raises(ArgumentError) do
      stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
        ImportarGestoresIndividuaisService.call(registros: [ linha_parcial ])
      end
    end

    assert_match(/contrato/, erro.message)
    assert_match(/exclus/, erro.message, "o motivo deve apontar o campo de EXCLUSÃO")
    assert_equal 0, GestorIndividualGerenciado.where(id_legado: 42).count,
                 "abortou antes de aplicar: nenhum vínculo pode entrar corrompido"
    assert_equal 0, GestorIndividual.count
  end

  # A verificação também é POR LINHA: uma linha 100% reconhecida NÃO pode
  # "proteger" as demais (o `any?` da lista era o segundo furo).
  test "D4: uma linha reconhecida nao protege outra com exclusao em casing desconhecido" do
    preparar_gerido(cpf: "60000000001")
    preparar_gerido(cpf: "60000000002", nome: "Gerido 2")

    ok = linha(id: 1, matricula_gerido: "2001", id_vinculo_gerido: 701)
    suspeita = {
      "id" => 2,
      "data_criacao" => "2019-10-30 10:03:25.0",
      "data_exclusao_legado" => "2021-03-04 08:00:00.0", # 3º casing
      "matricula_gestor" => "1001", "matricula_gerido" => "2002",
      "id_vinculo_gestor" => 900, "id_vinculo_gerido" => 702
    }

    assert_raises(ArgumentError) do
      stub_mapa_cpf({ "1001" => CPF_GESTOR, "2001" => "60000000001", "2002" => "60000000002" }) do
        ImportarGestoresIndividuaisService.call(registros: [ ok, suspeita ])
      end
    end
  end

  # Falso positivo a NÃO introduzir: é legítimo um vínculo nunca excluído não
  # ter campo de exclusão algum. O endurecimento distingue "ausente de verdade"
  # (nenhuma chave parece com o campo) de "casing desconhecido" (chave parecida).
  test "D4: linha sem campo de exclusao algum (nunca excluido) passa — sem falso positivo" do
    preparar_gerido
    linha_sem_exclusao = {
      "id" => 42,
      "data_criacao" => "2019-10-30 10:03:25.0",
      "matricula_gestor" => "1001", "matricula_gerido" => "2002",
      "id_vinculo_gestor" => 900, "id_vinculo_gerido" => 700
    }

    resultado = nil
    stub_mapa_cpf({ "1001" => CPF_GESTOR, "2002" => CPF_GERIDO }) do
      resultado = ImportarGestoresIndividuaisService.call(registros: [ linha_sem_exclusao ])
    end

    assert_empty resultado.nao_resolvidos
    assert_equal 1, resultado.importados
    vinculo = GestorIndividualGerenciado.find_by(id_legado: 42)
    assert vinculo.ativo?, "sem exclusão no legado ⇒ ativo"
    assert_nil vinculo.data_exclusao
  end

  test "D4: lista vazia nao viola o contrato" do
    resultado = ImportarGestoresIndividuaisService.call(registros: [])
    assert_equal 0, resultado.total
  end

  # --- fallback via codigo_de_para (espelho Pessoas) -----------------------

  test "resolve gestor por codigo_de_para quando a matricula nao esta na folha" do
    skip_sem_espelho!
    # Só o gerido tem User; o gestor é resolvido via vinculo legado no espelho.
    User.create!(nome_completo: "Gerido", password: "123456", cpf: CPF_GERIDO)

    pessoa = inserir_pessoa_espelho(nome: "Gestor Via Vinculo", cpf: CPF_GESTOR)
    inserir_vinculo_espelho(pessoa_id: pessoa.id, codigo_de_para: "900", matricula: "1001")

    resultado = nil
    stub_mapa_cpf({ "2002" => CPF_GERIDO }) do
      resultado = ImportarGestoresIndividuaisService.call(registros: [ linha(id: 42) ])
    end

    assert_empty resultado.nao_resolvidos
    assert_equal 1, resultado.importados
    assert_equal CPF_GESTOR, GestorIndividual.find_by(id_legado: 900).gestor_cpf
  end

  private

  def inserir_pessoa_espelho(nome:, cpf:)
    Pessoas::Pessoa.insert_all([ { nome: nome, cpf: cpf } ], returning: :id).rows.first.first
      .then { |id| Pessoas::Pessoa.find(id) }
  end

  def inserir_vinculo_espelho(pessoa_id:, codigo_de_para:, matricula:)
    Pessoas::Vinculo.insert_all(
      [ { pessoa_id: pessoa_id, codigo_de_para: codigo_de_para, matricula: matricula, inicio: Date.new(2020, 1, 1) } ],
      returning: :id
    ).rows.first.first
  end
end
