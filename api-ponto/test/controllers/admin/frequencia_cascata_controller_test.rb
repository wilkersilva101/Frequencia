require "test_helper"

# Tarefa 29.7 (Sprint 29) — integração da cascata nos controllers de
# frequência, atrás da flag `FREQUENCIA_AUTORIZACAO_CASCATA` (Decisão D2/D3).
#
# O que se prova aqui (critérios da 29.7):
#   - `admin/frequencia` e `admin/frequentadores` só mostram frequentadores
#     visíveis com a flag LIGADA;
#   - com a flag DESLIGADA o conteúdo é idêntico ao atual;
#   - no modo SHADOW nada é filtrado, mas a negação é LOGADA.
#
# A visibilidade é injetada pelo MESMO ponto de entrada de produção
# (`Pessoas::Vinculo.cpfs_frequentadores_visiveis`), stubado com
# `com_metodo_de_classe_stubado` (nunca `remove_method`).
module Admin
  class FrequenciaCascataControllerTest < ActionDispatch::IntegrationTest
    setup do
      # Sem cpf: com cpf, o login passa pela validação contra o Pessoas
      # (`Pessoas::User.buscar_por_cpf`) e exigiria stub — mesmo padrão dos
      # demais testes admin (authorization_matrix).
      @gestor = User.create!(nome_completo: "Gestor Cascata", password: "123456")
      @gestor.add_role(:gestor)
      @visivel = User.create!(nome_completo: "Frequentador Visivel", password: "123456", cpf: "20020020020")
      @oculto = User.create!(nome_completo: "Frequentador Oculto", password: "123456", cpf: "30030030030")

      @visivel_record = TimeRecord.create!(
        user: @visivel, raw_data: "v", punched_at: Time.zone.now, authentication_mode: "biometric"
      )
      @oculto_record = TimeRecord.create!(
        user: @oculto, raw_data: "o", punched_at: Time.zone.now, authentication_mode: "biometric"
      )

      post login_path, params: { username: @gestor.username, password: "123456" }
    end

    # ----------------------------------------------------------- frequencia

    test "frequencia: flag desligada mostra visivel e oculto (comportamento atual)" do
      com_cpfs_visiveis([ @visivel.cpf ]) do
        get frequencia_path
        assert_response :success
        assert_select "td", text: "Frequentador Visivel"
        assert_select "td", text: "Frequentador Oculto"
      end
    end

    test "frequencia: flag ligada restringe aos frequentadores visiveis" do
      com_flag("on") do
        com_cpfs_visiveis([ @visivel.cpf ]) do
          get frequencia_path
          assert_response :success
          assert_select "td", text: "Frequentador Visivel"
          assert_select "td", text: "Frequentador Oculto", count: 0
        end
      end
    end

    test "frequencia: modo shadow NAO filtra mas LOGA a negacao" do
      logger = RecordingLogger.new
      com_flag("shadow") do
        with_logger(logger) do
          com_cpfs_visiveis([ @visivel.cpf ]) do
            get frequencia_path
          end
        end
      end

      assert_response :success
      # Sem filtragem: o oculto continua aparecendo.
      assert_select "td", text: "Frequentador Oculto"
      # Mas a decisão que a cascata TOMARIA foi logada.
      entrada = logger.entradas.find { |e| e[:evento] == "frequencia_autorizacao_cascata.shadow" }
      assert entrada, "shadow deveria logar a negação"
      assert_equal @oculto.id, entrada[:alvo_id]
      assert_equal :negaria, entrada[:decisao]
    end

    test "frequencia: modo on LOGA a negacao EFETIVA do frequentador oculto (debito S4)" do
      logger = RecordingLogger.new
      com_flag("on") do
        with_logger(logger) do
          com_cpfs_visiveis([ @visivel.cpf ]) do
            get frequencia_path
          end
        end
      end

      assert_response :success
      assert_select "td", text: "Frequentador Oculto", count: 0
      # Débito S4: no modo `:on` (o único que nega de verdade), a negação deixa
      # rastro — mesmo payload do shadow, evento próprio.
      entrada = logger.entradas.find { |e| e[:evento] == "frequencia_autorizacao_cascata.negacao" }
      assert entrada, "modo on deveria logar a negação efetiva"
      assert_equal @oculto.id, entrada[:alvo_id]
      assert_equal :negaria, entrada[:decisao]
    end

    # -------------------------------------------------------- frequentadores

    test "frequentadores: flag ligada restringe a listagem aos cpfs visiveis" do
      vinculos = [ vinculo_double(@visivel), vinculo_double(@oculto) ]

      com_flag("on") do
        com_cpfs_visiveis([ @visivel.cpf ]) do
          stub_frequentadores(vinculos) do
            get frequentadores_path
            assert_response :success
            assert_select "td", text: "Frequentador Visivel"
            assert_select "td", text: "Frequentador Oculto", count: 0
          end
        end
      end
    end

    test "frequentadores: modo on LOGA a negacao EFETIVA na listagem (debito S4)" do
      vinculos = [ vinculo_double(@visivel), vinculo_double(@oculto) ]

      logger = RecordingLogger.new
      com_flag("on") do
        with_logger(logger) do
          com_cpfs_visiveis([ @visivel.cpf ]) do
            stub_frequentadores(vinculos) do
              get frequentadores_path
            end
          end
        end
      end

      assert_response :success
      # O log cobre TODOS os `User` locais fora do conjunto visível (não só os
      # do double de vínculo — a listagem do Pessoas não mapeia 1:1 para `User`
      # sem uma query extra); o que importa é que o oculto está entre os
      # negados efetivos.
      entrada = logger.entradas.find do |e|
        e[:evento] == "frequencia_autorizacao_cascata.negacao" && e[:alvo_id] == @oculto.id
      end
      assert entrada, "modo on deveria logar a negação efetiva do frequentador oculto"
    end

    test "frequentadores: flag ligada NAO mostra oculto nem quando o filtro local aponta para ele" do
      # O filtro local (`incluir_cpfs`) aponta para o OCULTO (via o filtro
      # "Digital": só o oculto tem digital cadastrada), que NÃO é visível. O
      # correto é a INTERSEÇÃO do filtro local com os visíveis: nada aparece.
      # Se a cascata fosse aplicada como SUBSTITUIÇÃO (só `visiveis`, ignorando
      # o filtro local), a listagem mostraria TUDO — e o oculto vazaria. Este
      # teste exige a interseção.
      @oculto.update!(digitais_hash: "hash-oculto")
      vinculos = [ vinculo_double(@visivel), vinculo_double(@oculto) ]

      com_flag("on") do
        com_cpfs_visiveis([ @visivel.cpf ]) do
          stub_frequentadores(vinculos) do
            get frequentadores_path, params: { digital: "1" }
            assert_response :success
            assert_select "td", text: "Frequentador Oculto", count: 0
            assert_select "td", text: "Frequentador Visivel", count: 0
          end
        end
      end
    end

    test "frequentadores: flag desligada mantem a listagem completa (comportamento atual)" do
      vinculos = [ vinculo_double(@visivel), vinculo_double(@oculto) ]

      com_cpfs_visiveis([ @visivel.cpf ]) do
        stub_frequentadores(vinculos) do
          get frequentadores_path
          assert_response :success
          assert_select "td", text: "Frequentador Visivel"
          assert_select "td", text: "Frequentador Oculto"
        end
      end
    end

    # ----------------------------------------------------------- time_records

    test "time_records: sob a flag, a busca do admin continua resolvendo qualquer frequentador (visao global, passo 2)" do
      admin = User.create!(nome_completo: "Admin Cascata", password: "123456", admin: true)
      delete logout_path
      post login_path, params: { username: admin.username, password: "123456" }

      # O ramo de busca por usuário de `time_records` só é alcançado por ADMIN,
      # que é o passo 2 da cascata (`role_geral?`) — vê todos. Sob a flag, a
      # visão global é PRESERVADA: o card "Registro Mensal" (que consulta
      # `TimeRecord.where(user_id: @user.id)` direto) continua renderizando,
      # mesmo para um alvo que não estaria no conjunto próprio/gerido/hierarquia
      # do admin.
      #
      # ⚠️ Controle de ISOLAMENTO DA FLAG (débito S1 da 29.7): o heading
      # "Registro Mensal" apareceria COM OU SEM a flag — ele não depende de
      # `:on`. Para que o teste não passe por um motivo alheio à flag, o MESMO
      # cenário é rodado nos dois estados da flag, e o que se assere é a
      # IGUALDADE de comportamento (o admin vê o oculto nas duas). A prova de
      # que o cenário discrimina (um não-admin NÃO veria) está no `refute_ve`
      # do teste `frequencia_por_orgao` e na matriz de aceite.
      #
      # ⚠️ CPFs em LOCAIS: o `corpo` do stub é instalado via
      # `define_singleton_method`, que REBINDA o `self` do lambda para a classe;
      # uma variável de INSTÂNCIA resolveria no receiver e viria `nil`. Local é
      # capturado pelo closure independentemente do `self`.
      cpf_oculto = @oculto.cpf
      stub_busca = [ [ Pessoas::Vinculo, :cpfs_por_nome, ->(_nome) { [ cpf_oculto ] } ] ]

      com_flag(nil) do
        com_metodos_de_classe_stubados(stub_busca) do
          get time_records_path, params: { usuario: "oculto" }
          assert_response :success
          assert_select "h5", { text: /Registro Mensal/ }, "admin ve o oculto COM a flag desligada"
        end
      end

      com_flag("on") do
        com_metodos_de_classe_stubados(stub_busca) do
          get time_records_path, params: { usuario: "oculto" }
          assert_response :success
          assert_select "h5", { text: /Registro Mensal/ },
                        "admin (passo 2) mantem visao global sob a flag"
        end
      end
    end

    test "time_records: controle — a flag NAO e um no-op; muda o comportamento de um usuario NAO-global" do
      # Débito S1 da 29.7 (controle de DISCRIMINAÇÃO): o teste do admin acima
      # assere que o comportamento é o MESMO com e sem flag — o que só tem valor
      # de prova se a flag de fato produziria uma diferença em algum caso. Este
      # controle prova a diferença: um usuário NÃO-global (sem role/admin) com um
      # registro próprio aparece na listagem SEM a flag e some SOB a flag (o
      # `restringir_frequencia` o fecha — é o S3 para conta sem CPF). Sem este
      # controle, o teste do admin passaria mesmo se a flag fosse um no-op.
      #
      # ⚠️ O discriminador é o CONTEÚDO da tabela ("Nenhum registro encontrado" /
      # o nome do usuário), não o heading "Registro Mensal": o card renderiza
      # sempre que há um `@user` resolvido (usuário básico), mesmo com zero
      # registros — o heading NÃO isola a flag (foi o sintoma do S1).
      nao_global = User.create!(nome_completo: "Nao Global Disriminacao", password: "123456")
      TimeRecord.create!(user: nao_global, raw_data: "ng", punched_at: Time.zone.now, authentication_mode: "biometric")
      delete logout_path
      post login_path, params: { username: nao_global.username, password: "123456" }

      # O usuário básico cai no modo "um usuário só" (tabela Dia/Trabalhado/
      # Registro/Informações, sem a coluna "Usuário") — o discriminador é a
      # presença de linhas de registro vs. a mensagem de vazio.
      com_flag(nil) do
        get time_records_path
        assert_response :success
        assert_select "td", { text: "Nenhum registro encontrado", count: 0 },
                      "sem a flag, o usuario ve o proprio registro (tabela com linhas)"
      end

      com_flag("on") do
        get time_records_path
        assert_response :success
        assert_select "td", { text: "Nenhum registro encontrado" },
                      "sob a flag, o usuario NAO-global nao ve mais o proprio registro (a flag discrimina)"
      end
    end

    # --------------------------------------------------- frequencia_por_orgao

    test "frequencia_por_orgao: flag ligada NAO conta presencas de frequentador oculto" do
      # Usa o @gestor do setup (sem cpf, sem role global): é um usuário NÃO
      # passo-2, o único caso em que a cascata de fato restringe. Admin/role
      # geral veem tudo (passo 2) e não seriam filtrados — testá-los aqui não
      # exercitaria a condição.
      oculto = User.create!(nome_completo: "Oculto Orgao", password: "123456", cpf: "40040040040")
      TimeRecord.create!(user: oculto, raw_data: "o", punched_at: Time.zone.local(2026, 7, 10, 8, 0), authentication_mode: "biometric")
      cpf_oculto = oculto.cpf

      # CONTROLE: sem a flag, o oculto entra na contagem (1 presença).
      stub_orgao_por_cpf([ cpf_oculto ], []) do
        get frequencia_por_orgao_path
      end
      assert_response :success
      assert_select "td", text: "Vara Cível"
      assert_select "td", text: "1"

      # SOB TESTE: com a flag, o oculto não é visível → 0 presenças.
      com_flag("on") do
        stub_orgao_por_cpf([ cpf_oculto ], []) do
          get frequencia_por_orgao_path
        end
      end
      assert_response :success
      assert_select "td", text: "Vara Cível"
      assert_select "td", text: "0"
      assert_select "td", text: "1", count: 0
    end

    # ------------------------- S4: auditoria do :on em time_records / orgao

    test "time_records: modo on LOGA a negacao EFETIVA (simetria com o shadow)" do
      oculto = User.create!(nome_completo: "Oculto TR S4", password: "123456", cpf: "40040040050")
      TimeRecord.create!(user: oculto, raw_data: "t", punched_at: Time.zone.now, authentication_mode: "biometric")
      cpf_oculto = oculto.cpf

      # POSITIVO: `:on` emite o evento de negação (payload do shadow).
      logger_on = RecordingLogger.new
      com_flag("on") do
        with_logger(logger_on) do
          com_cpfs_visiveis([ @visivel.cpf ]) { get time_records_path }
        end
      end
      assert_response :success
      negacao = logger_on.entradas.find do |e|
        e[:evento] == "frequencia_autorizacao_cascata.negacao" && e[:alvo_id] == oculto.id
      end
      assert negacao, "time_records DEVE logar a negação no modo on (estava mudo)"
      assert_equal :negaria, negacao[:decisao]
      assert_equal "User", negacao[:alvo_tipo]

      # CONTROLE NEGATIVO: no shadow NÃO emite o evento de `:on` — emite o DELE.
      logger_shadow = RecordingLogger.new
      com_flag("shadow") do
        with_logger(logger_shadow) do
          com_cpfs_visiveis([ @visivel.cpf ]) { get time_records_path }
        end
      end
      refute logger_shadow.entradas.any? { |e| e[:evento] == "frequencia_autorizacao_cascata.negacao" },
             "shadow NAO deve emitir o evento de negação do on"
      assert logger_shadow.entradas.any? { |e| e[:evento] == "frequencia_autorizacao_cascata.shadow" },
             "shadow deve emitir o evento dele"

      # CONTROLE NEGATIVO: com a flag off, nada é logado.
      logger_off = RecordingLogger.new
      com_flag(nil) do
        with_logger(logger_off) do
          com_cpfs_visiveis([ @visivel.cpf ]) { get time_records_path }
        end
      end
      assert_empty logger_off.entradas, "flag off nao deve logar auditoria"
    end

    test "time_records: SIMETRIA shadow x on — mesmos alvos, eventos distintos, contagens coerentes" do
      ocultos = %w[40040040060 40040040061 40040040062].map do |cpf|
        User.create!(nome_completo: "Oculto TR #{cpf}", password: "123456", cpf: cpf).tap do |u|
          TimeRecord.create!(user: u, raw_data: "t", punched_at: Time.zone.now, authentication_mode: "biometric")
        end
      end
      cpfs_ocultos = ocultos.map(&:id).to_set

      logger_shadow = RecordingLogger.new
      com_flag("shadow") do
        with_logger(logger_shadow) do
          com_cpfs_visiveis([]) { get time_records_path }
        end
      end
      logger_on = RecordingLogger.new
      com_flag("on") do
        with_logger(logger_on) do
          com_cpfs_visiveis([]) { get time_records_path }
        end
      end

      shadow = logger_shadow.entradas.select { |e| e[:evento] == "frequencia_autorizacao_cascata.shadow" }
      negacao = logger_on.entradas.select { |e| e[:evento] == "frequencia_autorizacao_cascata.negacao" }

      assert_operator shadow.size, :>=, 3
      assert_equal shadow.size, negacao.size, "shadow e on devem observar a MESMA quantidade de alvos"
      assert_equal shadow.map { |e| e[:alvo_id] }.to_set, negacao.map { |e| e[:alvo_id] }.to_set,
                   "shadow e on devem cobrir os MESMOS alvos"
      cpfs_ocultos.each { |id| assert_includes shadow.map { |e| e[:alvo_id] }, id }
    end

    test "frequencia_por_orgao: modo on LOGA a negacao EFETIVA e shadow loga o proprio evento" do
      oculto = User.create!(nome_completo: "Oculto Orgao S4", password: "123456", cpf: "40040040070")
      TimeRecord.create!(user: oculto, raw_data: "o", punched_at: Time.zone.local(2026, 7, 10, 8, 0), authentication_mode: "biometric")
      cpf_oculto = oculto.cpf

      # POSITIVO (:on): emite negação do alvo oculto.
      logger_on = RecordingLogger.new
      com_flag("on") do
        with_logger(logger_on) do
          stub_orgao_por_cpf([ cpf_oculto ], []) { get frequencia_por_orgao_path }
        end
      end
      assert_response :success
      negacao = logger_on.entradas.find do |e|
        e[:evento] == "frequencia_autorizacao_cascata.negacao" && e[:alvo_id] == oculto.id
      end
      assert negacao, "frequencia_por_orgao DEVE logar a negação no modo on (estava mudo)"

      # CONTROLE NEGATIVO (shadow): emite o evento DELE, não o de negação.
      logger_shadow = RecordingLogger.new
      com_flag("shadow") do
        with_logger(logger_shadow) do
          stub_orgao_por_cpf([ cpf_oculto ], []) { get frequencia_por_orgao_path }
        end
      end
      refute logger_shadow.entradas.any? { |e| e[:evento] == "frequencia_autorizacao_cascata.negacao" }
      assert logger_shadow.entradas.any? { |e| e[:evento] == "frequencia_autorizacao_cascata.shadow" && e[:alvo_id] == oculto.id },
             "frequencia_por_orgao deve logar shadow no modo shadow"

      # CONTROLE NEGATIVO (off): nada.
      logger_off = RecordingLogger.new
      com_flag(nil) do
        with_logger(logger_off) do
          stub_orgao_por_cpf([ cpf_oculto ], []) { get frequencia_por_orgao_path }
        end
      end
      assert_empty logger_off.entradas, "flag off nao deve logar auditoria"
    end

    private

    PessoaDouble = Struct.new(:nome, :cpf, keyword_init: true)
    VinculoDouble = Struct.new(:id, :pessoa, :tipo_vinculo, keyword_init: true)

    def vinculo_double(user)
      VinculoDouble.new(
        id: user.id,
        pessoa: PessoaDouble.new(nome: user.nome_completo, cpf: user.cpf),
        tipo_vinculo: nil
      )
    end

    # Fonte da tela admin/frequentadores (ponto de entrada stubável). O stub
    # HONRA `incluir_cpfs` — senão o teste passaria independentemente do filtro
    # da cascata (teste degenerado; lição de 2026-10-02).
    def stub_frequentadores(vinculos)
      com_metodos_de_classe_stubados([
        [ Pessoas::Vinculo, :frequentadores_ativos, lambda { |incluir_cpfs: nil, **|
            filtrados = incluir_cpfs.nil? ? vinculos : vinculos.select { |v| incluir_cpfs.include?(v.pessoa.cpf) }
            Kaminari.paginate_array(filtrados).page(1)
          } ],
        [ Pessoas::Vinculo, :unidades_por_vinculo, ->(*_args) { {} } ],
        [ Pessoas::CategoriaTrabalhador, :em_uso, -> { [] } ]
      ]) { yield }
    end

    def stub_orgao_por_cpf(cpfs_orgao, cpfs_visiveis, &bloco)
      com_metodos_de_classe_stubados([
        [ Pessoas::Vinculo, :orgaos_em_uso, -> { [ "Vara Cível" ] } ],
        [ Pessoas::Vinculo, :cpfs_por_orgao, ->(_o) { cpfs_orgao } ],
        [ Pessoas::Vinculo, :cpfs_frequentadores_visiveis, ->(_u) { cpfs_visiveis } ]
      ]) { bloco.call }
    end

    def com_cpfs_visiveis(cpfs, &bloco)
      com_metodo_de_classe_stubado(
        Pessoas::Vinculo, :cpfs_frequentadores_visiveis, ->(_usuario) { cpfs }
      ) { bloco.call }
    end

    def com_flag(valor)
      anterior = ENV[FrequenciaAutorizacaoCascata::VARIAVEL]
      if valor.nil?
        ENV.delete(FrequenciaAutorizacaoCascata::VARIAVEL)
      else
        ENV[FrequenciaAutorizacaoCascata::VARIAVEL] = valor
      end
      yield
    ensure
      if anterior.nil?
        ENV.delete(FrequenciaAutorizacaoCascata::VARIAVEL)
      else
        ENV[FrequenciaAutorizacaoCascata::VARIAVEL] = anterior
      end
    end

    def with_logger(logger)
      anterior = Rails.logger
      Rails.logger = logger
      yield
    ensure
      Rails.logger = anterior
    end

    class RecordingLogger
      def initialize
        @entradas = []
      end

      def info(payload = nil)
        @entradas << payload if payload.is_a?(Hash)
      end

      def warn(*); end
      def debug(*); end
      def error(*); end
      def fatal(*); end
      def level(*); end

      attr_reader :entradas
    end
  end
end
