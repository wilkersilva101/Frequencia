require "test_helper"

module Admin
  class FrequentadoresControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    setup do
      @admin = User.create!(nome_completo: "Admin Teste", password: "123456", admin: true)
      post login_path, params: { username: @admin.username, password: "123456" }
    end

    # SPRINT-PLAN task 10.10: a tela passou a listar `Pessoas::Vinculo.ativos`
    # (todo vínculo ativo do pessoas2), não mais só os `User` locais. O banco
    # `pessoas_test` existe mas não tem schema carregado (task 8.13) — não dá
    # pra criar `Pessoas::Vinculo`/`Pessoas::Pessoa` reais em teste. Seguindo
    # o mesmo padrão já usado nos outros arquivos desde a 8.13, isolamos o
    # ponto de entrada (`Pessoas::Vinculo.frequentadores_ativos` e
    # `.unidades_por_vinculo`, ver app/models/pessoas/vinculo.rb) e stubamos
    # com `define_singleton_method` + `Struct`/`Kaminari.paginate_array`.

    PessoaDouble = Struct.new(:nome, :cpf, keyword_init: true)
    TipoVinculoDouble = Struct.new(:nome, keyword_init: true)
    UnidadeDouble = Struct.new(:descricao, keyword_init: true)
    VinculoDouble = Struct.new(:id, :pessoa, :tipo_vinculo, keyword_init: true)
    CategoriaTrabalhadorDouble = Struct.new(:id, :descricao, keyword_init: true)

    def stub_vinculos(vinculos, unidades_por_vinculo_id: {}, categorias_trabalhador: [])
      paginado = Kaminari.paginate_array(vinculos).page(1)

      Pessoas::Vinculo.define_singleton_method(:frequentadores_ativos) { |**_kwargs| paginado }
      Pessoas::Vinculo.define_singleton_method(:unidades_por_vinculo) { |*_args| unidades_por_vinculo_id }
      Pessoas::CategoriaTrabalhador.define_singleton_method(:em_uso) { categorias_trabalhador }

      yield
    ensure
      Pessoas::Vinculo.singleton_class.remove_method(:frequentadores_ativos)
      Pessoas::Vinculo.singleton_class.remove_method(:unidades_por_vinculo)
      Pessoas::CategoriaTrabalhador.singleton_class.remove_method(:em_uso)
    end

    test "deve enfileirar o job de reimportacao quando o frequentador tem cpf" do
      frequentador = User.create!(nome_completo: "Frequentador Com Cpf", password: "123456", cpf: "11122233344")

      assert_enqueued_with(job: ImportarDadosPessoaJob, args: [ frequentador.id ]) do
        post reimportar_dados_pessoa_frequentador_path(frequentador)
      end

      assert_redirected_to frequentadores_path
    end

    test "o botao de reimportacao atualiza o FrequentadorCache quando o job enfileirado roda" do
      frequentador = User.create!(nome_completo: "Frequentador Com Cpf", password: "123456", cpf: "11122233344")

      # Sem dados reais no banco `pessoas` de teste (sem schema carregado) —
      # stubamos `Pessoas::Pessoa.find_by` (task 8.13, substitui
      # `SticapiClient::Pessoas.get_by_cpf`).
      vinculo_ativo = Struct.new(:lotacao_principal, :tipo_vinculo, keyword_init: true).new(
        lotacao_principal: Struct.new(:unidade, keyword_init: true).new(unidade: Struct.new(:descricao, keyword_init: true).new(descricao: "Vara Cível")),
        tipo_vinculo: Struct.new(:nome, keyword_init: true).new(nome: "Efetivo")
      )
      pessoa = Struct.new(:id, :nome, :username, :vinculos_ativos, keyword_init: true).new(
        id: 42, nome: "Nome Atualizado Pessoas", username: nil, vinculos_ativos: [ vinculo_ativo ]
      )

      Pessoas::Pessoa.define_singleton_method(:find_by) { |*_args| pessoa }

      begin
        perform_enqueued_jobs do
          post reimportar_dados_pessoa_frequentador_path(frequentador)
        end
      ensure
        Pessoas::Pessoa.singleton_class.remove_method(:find_by)
      end

      cache = FrequentadorCache.find_by(cpf: "11122233344")
      assert cache.present?
      assert_equal "Nome Atualizado Pessoas", cache.nome
      assert_equal "Vara Cível", cache.orgao
      assert_equal "Efetivo", cache.vinculo
    end

    test "nao enfileira o job quando o frequentador nao tem cpf" do
      frequentador = User.create!(nome_completo: "Frequentador Sem Cpf", password: "123456")

      assert_no_enqueued_jobs(only: ImportarDadosPessoaJob) do
        post reimportar_dados_pessoa_frequentador_path(frequentador)
      end

      assert_redirected_to frequentadores_path
    end

    test "index exibe orgao e vinculo (tipo) vindos do pessoas2" do
      User.create!(nome_completo: "Com Cache", password: "123456", cpf: "11122233344")
      vinculo = VinculoDouble.new(
        id: 1,
        pessoa: PessoaDouble.new(nome: "Com Cache", cpf: "11122233344"),
        tipo_vinculo: TipoVinculoDouble.new(nome: "Efetivo")
      )

      stub_vinculos([ vinculo ], unidades_por_vinculo_id: { 1 => UnidadeDouble.new(descricao: "Vara Cível") }) do
        get frequentadores_path
      end

      assert_response :success
      assert_select "td", text: "Vara Cível"
      assert_select "td", text: "Efetivo"
    end

    test "index exibe as categorias reais no select de Categoria" do
      stub_vinculos([], categorias_trabalhador: [
        CategoriaTrabalhadorDouble.new(id: 34, descricao: "Estagiário"),
        CategoriaTrabalhadorDouble.new(id: 10, descricao: "Servidor Efetivo")
      ]) do
        get frequentadores_path
      end

      assert_response :success
      assert_select "select#categoria option", text: "Estagiário"
      assert_select "select#categoria option", text: "Servidor Efetivo"
    end

    test "index repassa o filtro de categoria para Pessoas::Vinculo.frequentadores_ativos" do
      categoria_recebida = nil
      paginado = Kaminari.paginate_array([]).page(1)

      Pessoas::Vinculo.define_singleton_method(:frequentadores_ativos) do |**kwargs|
        categoria_recebida = kwargs[:categoria_trabalhador_id]
        paginado
      end
      Pessoas::Vinculo.define_singleton_method(:unidades_por_vinculo) { |*_args| {} }
      Pessoas::CategoriaTrabalhador.define_singleton_method(:em_uso) { [] }

      begin
        get frequentadores_path, params: { categoria: "34" }
      ensure
        Pessoas::Vinculo.singleton_class.remove_method(:frequentadores_ativos)
        Pessoas::Vinculo.singleton_class.remove_method(:unidades_por_vinculo)
        Pessoas::CategoriaTrabalhador.singleton_class.remove_method(:em_uso)
      end

      assert_equal "34", categoria_recebida
    end

    test "index exibe o vinculo mesmo quando nao existe User local (nunca cadastrado no Frequencia)" do
      vinculo = VinculoDouble.new(
        id: 2,
        pessoa: PessoaDouble.new(nome: "Sem Cadastro Local", cpf: "99988877766"),
        tipo_vinculo: TipoVinculoDouble.new(nome: "Efetivo")
      )

      stub_vinculos([ vinculo ]) do
        get frequentadores_path
      end

      assert_response :success
      assert_select "td", text: "Sem Cadastro Local"
      assert_select "span.badge", text: "Sem cadastro local"
    end

    test "index exibe travessao quando o vinculo nao tem lotacao/tipo de vinculo resolvidos" do
      vinculo = VinculoDouble.new(
        id: 3,
        pessoa: PessoaDouble.new(nome: "Sem Lotacao", cpf: "11122233344"),
        tipo_vinculo: nil
      )

      stub_vinculos([ vinculo ]) do
        get frequentadores_path
      end

      assert_response :success
      assert_select "td.text-muted", text: "—", minimum: 1
    end

    test "index nao faz N+1 ao carregar User local por cpf" do
      cpfs = [ "11122223301", "11122223302", "11122223303" ]
      cpfs.each { |cpf| User.create!(nome_completo: "Frequentador #{cpf}", password: "123456", cpf: cpf) }

      vinculos = cpfs.each_with_index.map do |cpf, i|
        VinculoDouble.new(id: i + 1, pessoa: PessoaDouble.new(nome: "Frequentador #{cpf}", cpf: cpf), tipo_vinculo: nil)
      end

      # 2 queries esperadas na tabela `users`, nenhuma delas por linha: (1)
      # `User.where(status: 0)` calculada 1x no controller pra ocultar
      # inativos por padrão (filtro cross-database, não depende do tamanho
      # da página) e (2) `User.where(cpf: cpfs_da_pagina)` pra pré-carregar
      # os Users locais da página inteira de uma vez.
      queries_users_por_cpf_in = 0
      contador = ->(*, payload) { queries_users_por_cpf_in += 1 if payload[:sql].include?('"users"."cpf" IN') }

      stub_vinculos(vinculos) do
        ActiveSupport::Notifications.subscribed(contador, "sql.active_record") do
          get frequentadores_path
        end
      end

      assert_response :success
      assert_equal 1, queries_users_por_cpf_in, "esperado 1 query (IN) para carregar os Users locais da página, não uma por linha"
    end

    test "deve redirecionar para login se nao autenticado" do
      delete logout_path
      frequentador = User.create!(nome_completo: "Frequentador", password: "123456", cpf: "11122233344")

      post reimportar_dados_pessoa_frequentador_path(frequentador)

      assert_redirected_to login_path
    end

    test "botao importar_unidade enfileira ImportarServidoresUnidadeJob para a unidade piloto" do
      assert_enqueued_with(job: ImportarServidoresUnidadeJob, args: [ Admin::FrequentadoresController::UNIDADE_PILOTO_ID ]) do
        post importar_unidade_frequentadores_path
      end

      assert_redirected_to frequentadores_path
    end

    test "importar_unidade cria multiplos frequentadores em um unico clique quando o job roda" do
      # Sem dados reais no banco `pessoas` de teste (sem schema carregado) —
      # stubamos os 3 pontos de entrada usados por ImportarServidoresUnidadeJob
      # (task 8.13, substitui SticapiClient::Pessoas.unidade/get_by_cpf e
      # SticapiClient::Gestorh.competencia).
      unidade = Struct.new(:servidores, keyword_init: true).new(
        servidores: [
          Pessoas::Unidade::ServidorLotado.new(matricula: "1001", nome: "Servidor Um"),
          Pessoas::Unidade::ServidorLotado.new(matricula: "1002", nome: "Servidor Dois")
        ]
      )
      pessoa_double = Struct.new(:id, :nome, :username, :vinculos_ativos, keyword_init: true)
      pessoas_por_cpf = {
        "11122233344" => pessoa_double.new(id: 1, nome: "Servidor Um", username: nil, vinculos_ativos: []),
        "55566677788" => pessoa_double.new(id: 2, nome: "Servidor Dois", username: nil, vinculos_ativos: [])
      }

      Pessoas::Unidade.define_singleton_method(:find_by) { |*_args| unidade }
      Pessoas::GestorhContrachequeMirror.define_singleton_method(:pares_matricula_cpf_para) do |*_args, **_kwargs|
        [ [ "1001", "11122233344" ], [ "1002", "55566677788" ] ]
      end
      Pessoas::Pessoa.define_singleton_method(:find_by) { |cpf:| pessoas_por_cpf[cpf] }

      begin
        perform_enqueued_jobs do
          post importar_unidade_frequentadores_path
        end
      ensure
        Pessoas::Unidade.singleton_class.remove_method(:find_by)
        Pessoas::GestorhContrachequeMirror.singleton_class.remove_method(:pares_matricula_cpf_para)
        Pessoas::Pessoa.singleton_class.remove_method(:find_by)
      end

      assert User.exists?(cpf: "11122233344")
      assert User.exists?(cpf: "55566677788")
    end

    test "importar_unidade exige autenticacao" do
      delete logout_path

      post importar_unidade_frequentadores_path

      assert_redirected_to login_path
    end

    # Task 23.10 (auditoria) — `reimportar_dados_pessoa` e `importar_unidade`
    # usam `authorize! :manage, User` (task 23.7), mas só havia teste do
    # caminho de autenticação, não do caminho de acesso negado por falta de
    # permissão. Só admin tem `:manage` em `User` (ver app/models/ability.rb).
    test "usuario nao-admin nao deve reimportar dados do pessoa" do
      frequentador = User.create!(nome_completo: "Frequentador Com Cpf", password: "123456", cpf: "11122233344")
      login_como_nao_admin

      assert_no_enqueued_jobs(only: ImportarDadosPessoaJob) do
        post reimportar_dados_pessoa_frequentador_path(frequentador)
      end

      assert_redirected_to dashboard_path
    end

    test "usuario nao-admin nao deve importar unidade" do
      login_como_nao_admin

      assert_no_enqueued_jobs(only: ImportarServidoresUnidadeJob) do
        post importar_unidade_frequentadores_path
      end

      assert_redirected_to dashboard_path
    end

    test "gestor tambem nao deve importar unidade (fora do escopo de manage do gestor)" do
      delete logout_path
      gestor = User.create!(nome_completo: "Gestor Teste", password: "123456")
      gestor.add_role(:gestor)
      post login_path, params: { username: gestor.username, password: "123456" }

      assert_no_enqueued_jobs(only: ImportarServidoresUnidadeJob) do
        post importar_unidade_frequentadores_path
      end

      assert_redirected_to dashboard_path
    end

    private

    def login_como_nao_admin
      delete logout_path
      usuario_comum = User.create!(nome_completo: "Usuario Comum", password: "123456", admin: false)
      post login_path, params: { username: usuario_comum.username, password: "123456" }
    end
  end
end
