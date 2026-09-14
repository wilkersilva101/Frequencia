require "test_helper"

class Intranet::SyncDigitaisServiceTest < ActiveSupport::TestCase
  # Injeta os dados da Intranet sem acesso ao MySQL real, capturando o `new`
  # original e substituindo-o por um que anexa um stub de `ler_digitais_intranet`
  # à instância. O bloco é avaliado a cada chamada, permitindo mutar `dados`
  # entre execuções (simula alterações na Intranet). O `new` original é
  # restaurado no ensure.
  def stub_dados_intranet(dados)
    original_new = Intranet::SyncDigitaisService.method(:new)
    Intranet::SyncDigitaisService.define_singleton_method(:new) do |**kwargs|
      instance = original_new.call(**kwargs)
      instance.define_singleton_method(:ler_digitais_intranet) { dados.map(&:dup) }
      instance
    end
    yield
  ensure
    Intranet::SyncDigitaisService.singleton_class.send(:define_method, :new, original_new)
  end

  def criar_user(cpf: nil, username: nil, digitais: nil)
    User.create!(
      nome_completo: "Usuario #{cpf || username}",
      password: "123456",
      cpf: cpf,
      username: username,
      digitais_hash: digitais
    )
  end

  test "atualiza a digital de um user pelo CPF" do
    user = criar_user(cpf: "11122233344", username: "mat.001")
    stubs = [ { frequentador_id: 1, digitais_hash: "FIR_ABC", matricula: "mat.001", cpf: "11122233344" } ]

    stub_dados_intranet(stubs) do
      resumo = Intranet::SyncDigitaisService.call
      assert_equal 1, resumo[:atualizados]
      assert_equal 0, resumo[:sem_alteracao]
    end

    assert_equal "FIR_ABC", user.reload.digitais_hash
  end

  test "faz fallback para username quando o CPF nao encontra user" do
    user = criar_user(cpf: nil, username: "mat.001")
    stubs = [ { frequentador_id: 1, digitais_hash: "FIR_XYZ", matricula: "mat.001", cpf: nil } ]

    stub_dados_intranet(stubs) do
      resumo = Intranet::SyncDigitaisService.call
      assert_equal 1, resumo[:atualizados]
    end

    assert_equal "FIR_XYZ", user.reload.digitais_hash
  end

  test "conta como sem_alteracao quando a digital ja e igual" do
    user = criar_user(cpf: "11122233344", digitais: "FIR_IGUAL")
    stubs = [ { frequentador_id: 1, digitais_hash: "FIR_IGUAL", matricula: "mat.001", cpf: "11122233344" } ]

    stub_dados_intranet(stubs) do
      resumo = Intranet::SyncDigitaisService.call
      assert_equal 0, resumo[:atualizados]
      assert_equal 1, resumo[:sem_alteracao]
    end

    assert_equal "FIR_IGUAL", user.reload.digitais_hash
  end

  test "ignora (e nao cria user) quando nao ha correspondente" do
    stubs = [ { frequentador_id: 1, digitais_hash: "FIR_SEM_USER", matricula: "mat.999", cpf: "99988877766" } ]

    stub_dados_intranet(stubs) do
      resumo = Intranet::SyncDigitaisService.call
      assert_equal 1, resumo[:ignorados]
      assert_equal 0, resumo[:atualizados]
    end

    assert_nil User.find_by(cpf: "99988877766")
  end

  test "ignora registro com digital vazia (nao apaga a existente)" do
    user = criar_user(cpf: "11122233344", digitais: "FIR_MANTIDA")
    stubs = [ { frequentador_id: 1, digitais_hash: "", matricula: "mat.001", cpf: "11122233344" } ]

    stub_dados_intranet(stubs) do
      resumo = Intranet::SyncDigitaisService.call
      assert_equal 1, resumo[:ignorados]
    end

    assert_equal "FIR_MANTIDA", user.reload.digitais_hash
  end

  test "respeita o modo dry_run (nao grava nada)" do
    user = criar_user(cpf: "11122233344")
    stubs = [ { frequentador_id: 1, digitais_hash: "FIR_DRY", matricula: "mat.001", cpf: "11122233344" } ]

    stub_dados_intranet(stubs) do
      resumo = Intranet::SyncDigitaisService.call(dry_run: true)
      assert_equal 1, resumo[:atualizados]
    end

    assert_nil user.reload.digitais_hash
  end

  test "processa somente os CPFs passados em only_cpfs" do
    user_alvo = criar_user(cpf: "11122233344")
    user_outro = criar_user(cpf: "55544433322")
    stubs = [
      { frequentador_id: 1, digitais_hash: "FIR_ALVO", matricula: "mat.001", cpf: "11122233344" },
      { frequentador_id: 2, digitais_hash: "FIR_OUTRO", matricula: "mat.002", cpf: "55544433322" }
    ]

    stub_dados_intranet(stubs) do
      resumo = Intranet::SyncDigitaisService.call(only_cpfs: ["11122233344"])
      assert_equal 1, resumo[:atualizados]
    end

    assert_equal "FIR_ALVO", user_alvo.reload.digitais_hash
    assert_nil user_outro.reload.digitais_hash
  end

  test "nao quebra quando nao consegue conectar na Intranet" do
    # Simula falha de conexão (mysql2 / rede) → "ler_digitais_intranet" retorna [].
    original_new = Intranet::SyncDigitaisService.method(:new)
    Intranet::SyncDigitaisService.define_singleton_method(:new) do |**kwargs|
      instance = original_new.call(**kwargs)
      instance.define_singleton_method(:ler_digitais_intranet) { [] }
      instance
    end

    resumo = Intranet::SyncDigitaisService.call
    assert_equal 0, resumo[:processados]
    assert_equal 0, resumo[:erros]
  ensure
    Intranet::SyncDigitaisService.singleton_class.send(:define_method, :new, original_new)
  end
end
