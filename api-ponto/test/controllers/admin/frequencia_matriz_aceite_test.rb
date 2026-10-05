require "test_helper"

# Tarefa 29.8 (Sprint 29) — MATRIZ DE ACEITE da cascata de autorização de
# frequência (PRD §3; critério da 29.8). É o teste de INTEGRAÇÃO que o PO usa
# para decidir ligar a flag em produção: exercita a esteira completa
# (router → before_action → `Ability`/CanCan → controller → `FrequentadoresVisiveis`
# → PORO `AutorizacaoFrequencia` → view) com a flag `:on`, sobre o SCHEMA REAL
# do espelho (ADR-0006) — a visibilidade NÃO é stubada: é calculada pela própria
# cascata de produção, a partir de vínculos/lotações/gestores reais.
#
# Cenários da matriz (um teste por linha do critério da 29.8):
#   1. próprio / 2. role geral / 3. terceirizado COM role / 4. terceirizado SEM
#   role / 5. gestor individual ATIVO / 6. gestor individual INATIVO /
#   7. hierarquia nível AVÔ (atual) / 8. hierarquia nível PAI (substituto) /
#   9. hierarquia EXCEPCIONAL / 10. hierarquia em unidade INELEGÍVEL (D6) /
#   11. sem vínculo / 12. sem CPF (débito S3 da 29.7).
#
# ⚠️ Contrato de "→ 403" (interpretação explícita, 29.8): neste app o `index`
# de frequência é liberado pelo baseline `can :read, :all` (Sprint 23) — a
# NEGAÇÃO da cascata é a FILTRAGEM da listagem, não um HTTP 403. Logo os
# cenários 11/12 provam a negação por (a) a listagem vir vazia para os alvos e
# (b) `Ability#can?(:read, instância de outro)` ser `false`. O substantivo do
# critério (usuário sem vínculo é NEGADO) é o que se prova; a forma HTTP é a
# deste app.
#
# Pré-requisito: `RAILS_ENV=test bin/rails test:pessoas_schema:load` (ADR-0006).
module Admin
  class FrequenciaMatrizAceiteTest < ActionDispatch::IntegrationTest
    include PessoasEspelhoHelper

    setup do
      skip_sem_espelho!
    end

    # ------------------------------------------------------------- 1. próprio

    test "matriz 1: proprio ve os proprios registros sob a flag" do
      eu = actor_lotado(nome: "Proprio Matrix", unidade: unidade_simples)
      outro = ator_com_registro(nome: "Outro Matrix", unidade: unidade_simples)

      login_como(eu)
      com_flag("on") { get frequencia_path }

      assert_response :success
      assert_ve(nome_de(eu))
      refute_ve(nome_de(outro))
    end

    # ----------------------------------------------------------- 2. role geral

    test "matriz 2a: role geral (admin) ve todos sob a flag" do
      admin = criar_usuario(nome: "Admin Matrix", admin: true)
      alvo = ator_com_registro(nome: "Alvo Admin Matrix", unidade: unidade_simples)

      login_como(admin)
      com_flag("on") { get frequencia_path }

      assert_response :success
      assert_ve(nome_de(alvo))
    end

    test "matriz 2b: role geral (visualiza_frequentadores) ve todos sob a flag" do
      gestor = criar_usuario(nome: "Role Geral Matrix", roles: [ :visualiza_frequentadores ])
      alvo = ator_com_registro(nome: "Alvo Role Geral Matrix", unidade: unidade_simples)

      login_como(gestor)
      com_flag("on") { get frequencia_path }

      assert_response :success
      assert_ve(nome_de(alvo))
    end

    # ------------------------------------------------------- 3/4. terceirizado

    test "matriz 3: terceirizado COM role ve o alvo terceirizado sob a flag" do
      gestor = criar_usuario(nome: "Ve Terc Matrix", roles: [ :visualiza_terceirizados ])
      alvo = ator_terceirizado_com_registro(nome: "Terceirizado Matrix", unidade: unidade_simples)

      login_como(gestor)
      com_flag("on") { get frequencia_path }

      assert_response :success
      assert_ve(nome_de(alvo))
    end

    test "matriz 4: terceirizado SEM role NAO ve o alvo terceirizado sob a flag" do
      gestor = criar_usuario(nome: "Sem Role Terc Matrix") # sem role alguma
      alvo = ator_terceirizado_com_registro(nome: "Terceirizado Oculto Matrix", unidade: unidade_simples)

      login_como(gestor)
      # CONTROLE (não-degeneração): SEM a flag, o alvo aparece — logo a única
      # razão da ausência sob a flag é a cascata, não um erro de setup.
      com_flag(nil) do
        get frequencia_path
        assert_response :success
        assert_ve(nome_de(alvo))
      end
      com_flag("on") do
        get frequencia_path
        assert_response :success
        refute_ve(nome_de(alvo))
      end
    end

    # --------------------------------------------------- 5/6. gestor individual

    test "matriz 5: gestor individual ATIVO ve o gerido sob a flag" do
      gestor = criar_usuario(nome: "Gestor Ind Matrix")
      gerido = ator_com_registro(nome: "Gerido Ativo Matrix", unidade: unidade_simples)
      gestor_individual(gerido: gerido, gestor_user: gestor, ativo: true)

      login_como(gestor)
      com_flag("on") { get frequencia_path }

      assert_response :success
      assert_ve(nome_de(gerido))
    end

    test "matriz 6: gestor individual INATIVO NAO ve o gerido sob a flag" do
      gestor = criar_usuario(nome: "Gestor Ind Inativo Matrix")
      gerido = ator_com_registro(nome: "Gerido Inativo Matrix", unidade: unidade_simples)
      gestor_individual(gerido: gerido, gestor_user: gestor, ativo: false)

      login_como(gestor)
      # CONTROLE: sem a flag, o gerido aparece (setup é válido); a ausência sob
      # a flag é atribuível à cascata.
      com_flag(nil) do
        get frequencia_path
        assert_response :success
        assert_ve(nome_de(gerido))
      end
      com_flag("on") do
        get frequencia_path
        assert_response :success
        refute_ve(nome_de(gerido))
      end
    end

    # --------------------------------------------------------- 7/8/9/10. hierarquia

    test "matriz 7: gestor ATUAL no nivel AVO ve o alvo lotado no neto" do
      gestor, arvore = gestor_para_hierarquia(papel: :gestor_id, nivel: :avo)
      alvo = ator_com_registro(nome: "Alvo Avo Matrix", unidade: arvore[:folha])

      login_como(gestor)
      com_flag("on") { get frequencia_path }

      assert_response :success
      assert_ve(nome_de(alvo))
    end

    test "matriz 8: gestor SUBSTITUTO no nivel PAI ve o alvo lotado no filho" do
      gestor, arvore = gestor_para_hierarquia(papel: :gestor_substituto_id, nivel: :pai)
      alvo = ator_com_registro(nome: "Alvo Pai Matrix", unidade: arvore[:folha])

      login_como(gestor)
      com_flag("on") { get frequencia_path }

      assert_response :success
      assert_ve(nome_de(alvo))
    end

    test "matriz 9: gestor EXCEPCIONAL no nivel AVO ve o alvo" do
      gestor, arvore = gestor_para_hierarquia(papel: :gestor_excepcional_id, nivel: :avo)
      alvo = ator_com_registro(nome: "Alvo Excepcional Matrix", unidade: arvore[:folha])

      login_como(gestor)
      com_flag("on") { get frequencia_path }

      assert_response :success
      assert_ve(nome_de(alvo))
    end

    test "matriz 10: gestor de unidade INELEGIVEL (D6) NAO ve o alvo" do
      gestor, arvore = gestor_para_hierarquia(papel: :gestor_id, nivel: :avo, raiz_ativa: false)
      alvo = ator_com_registro(nome: "Alvo Inelegivel Matrix", unidade: arvore[:folha])

      login_como(gestor)
      # CONTROLE: sem a flag, o alvo aparece (o setup de hierarquia é válido —
      # se `gestor_para_hierarquia` não montasse o gestor, este `assert_ve`
      # falharia e denunciaria o teste degenerado).
      com_flag(nil) do
        get frequencia_path
        assert_response :success
        assert_ve(nome_de(alvo))
      end
      com_flag("on") do
        get frequencia_path
        assert_response :success
        refute_ve(nome_de(alvo))
      end
    end

    # --------------------------------------------------------- 11. sem vínculo

    test "matriz 11: usuario SEM vinculo (sem relacao) nao ve registro algum sob a flag" do
      # Tem CPF e registro próprio, mas NENHUM vínculo/role/gestão/hierarquia —
      # o passo 6 da cascata (`:negado`) vale para todo alvo, inclusive o
      # próprio (que só seria liberado se o próprio tivesse vínculo ativo).
      sem_vinculo = criar_usuario(nome: "Sem Vinculo Matrix", cpf: proximo_cpf_teste)
      proprio_registro = TimeRecord.create!(
        user: sem_vinculo, raw_data: "sv", punched_at: Time.zone.now, authentication_mode: "biometric"
      )
      outro = ator_com_registro(nome: "Outro Sem Vinculo Matrix", unidade: unidade_simples)

      login_como(sem_vinculo)
      # CONTROLE: sem a flag, ambos aparecem (o setup é válido).
      com_flag(nil) do
        get frequencia_path
        assert_response :success
        assert_ve(nome_de(outro))
        assert_ve(nome_de(sem_vinculo))
      end
      com_flag("on") do
        get frequencia_path
        assert_response :success
        refute_ve(nome_de(outro))
        refute_ve(nome_de(sem_vinculo))
        # Prova adicional (per-instance): a Ability nega a leitura de QUALQUER
        # instância que não seja visível — inclusive a própria, aqui.
        ability = Ability.new(sem_vinculo)
        refute ability.can?(:read, proprio_registro)
      end
    end

    # -------------------------------------------------------------- 12. sem CPF (S3)

    test "matriz 12 (S3): usuario nao-admin SEM CPF ve zero registros sob a flag (perde os proprios)" do
      # Débito S3 da 29.7: `FrequentadoresVisiveis` fecha em "1 = 0" quando não
      # há insumo (sem CPF) → `frequentadores_visiveis_user_ids` vazio → o
      # `where(user_id: [])` apaga até os PRÓPRIOS registros. Fail-closed (não
      # vaza), mas é regressão funcional para conta local sem CPF.
      sem_cpf = criar_usuario(nome: "Sem Cpf Matrix")
      proprio = TimeRecord.create!(
        user: sem_cpf, raw_data: "sc", punched_at: Time.zone.now, authentication_mode: "biometric"
      )

      login_como(sem_cpf)
      # CONTROLE: sem a flag, o próprio registro aparece — a supressão sob a
      # flag é o efeito do S3, não um setup vazio.
      com_flag(nil) do
        get frequencia_path
        assert_response :success
        assert_ve(nome_de(sem_cpf))
      end
      com_flag("on") do
        get frequencia_path
        assert_response :success
        refute_ve(nome_de(sem_cpf))
        ability = Ability.new(sem_cpf)
        refute ability.can?(:read, proprio), "fail-closed: sem CPF, nem o próprio é liberado"
      end
    end

    # --------------------------------------------------------------------------
    # Infra da matriz
    # --------------------------------------------------------------------------

    private

    # --- assertions -----------------------------------------------------------

    def assert_ve(nome)
      assert_select "td", text: nome
    end

    def refute_ve(nome)
      assert_select "td", text: nome, count: 0
    end

    def nome_de(user)
      user.nome_completo
    end

    # --- login ----------------------------------------------------------------

    # Loga como o usuário. Users COM cpf autenticam contra o Pessoas2
    # (`Pessoas::User.buscar_por_cpf`), então o ponto de entrada é stubado para
    # devolver o hash de "123456" a QUALQUER cpf — os atores da matriz logam
    # com a mesma senha. Stub não-destrutivo (capturar/restaurar).
    def login_como(user)
      hash = BCrypt::Password.create("123456")
      fake = Struct.new(:encrypted_password).new(hash)
      com_metodo_de_classe_stubado(Pessoas::User, :buscar_por_cpf, ->(_cpf) { fake }) do
        post login_path, params: { username: user.username, password: "123456" }
      end
    end

    # --- usuários -------------------------------------------------------------

    def criar_usuario(nome: "Usuario Matrix", cpf: nil, admin: false, roles: [])
      user = User.create!(
        nome_completo: nome, password: "123456", cpf: cpf, admin: admin
      )
      roles.each { |role| user.add_role(role) }
      user
    end

    def criar_pessoa(cpf: proximo_cpf_teste, nome: "Pessoa Matrix")
      inserir(Pessoas::Pessoa, nome: nome, cpf: cpf)
    end

    def inserir_vinculo(pessoa:, unidade:, configuracao_cadastro_id: nil)
      vinculo = inserir(
        Pessoas::Vinculo,
        pessoa_id: pessoa.id,
        vinculo_estado_id: criar_vinculo_estado(nome: "em_exercicio").id,
        matricula: "M#{pessoa.id}",
        inicio: Date.new(2020, 1, 1),
        configuracao_cadastro_id: configuracao_cadastro_id
      )
      inserir(
        Pessoas::Lotacao,
        vinculo_id: vinculo.id, unidade_id: unidade.id, principal: true,
        inicio: Date.new(2020, 1, 1), fim: nil
      )
      vinculo
    end

    # Pessoa lotada + User local com o mesmo CPF (o ator logado).
    def usuario_lotado(nome:, unidade:)
      cpf = proximo_cpf_teste
      pessoa = criar_pessoa(cpf: cpf, nome: nome)
      inserir_vinculo(pessoa: pessoa, unidade: unidade)
      criar_usuario(nome: nome, cpf: cpf)
    end

    # Ator logado com registro próprio (para provar "ve os próprios").
    def actor_lotado(nome:, unidade:)
      user = usuario_lotado(nome: nome, unidade: unidade)
      TimeRecord.create!(user: user, raw_data: "eu", punched_at: Time.zone.now, authentication_mode: "biometric")
      user
    end

    # Alvo (frequentador) com registro, para o ator tentar vê-lo.
    def ator_com_registro(nome:, unidade:)
      user = usuario_lotado(nome: nome, unidade: unidade)
      TimeRecord.create!(user: user, raw_data: "alvo", punched_at: Time.zone.now, authentication_mode: "biometric")
      user
    end

    def ator_terceirizado_com_registro(nome:, unidade:)
      cpf = proximo_cpf_teste
      pessoa = criar_pessoa(cpf: cpf, nome: nome)
      config = inserir(Pessoas::ConfiguracaoCadastro, tipo_vinculo_id: criar_tipo_vinculo("Terceirizado").id)
      inserir_vinculo(pessoa: pessoa, unidade: unidade, configuracao_cadastro_id: config.id)
      user = criar_usuario(nome: nome, cpf: cpf)
      TimeRecord.create!(user: user, raw_data: "terc", punched_at: Time.zone.now, authentication_mode: "biometric")
      user
    end

    # --- hierarquia -----------------------------------------------------------

    # Monta a árvore raiz→intermediária→folha com o gestor (atual/substituto/
    # excepcional) no nível pedido, e devolve [gestor_user, arvore]. O gestor
    # existe como PESSOA no espelho (é por ela que `Unidade#gestor?` casa),
    # ligada ao `User` logado pelo CPF. `raiz_ativa: false` exercita a D6.
    def gestor_para_hierarquia(papel:, nivel:, raiz_ativa: true)
      gestor_pessoa = criar_pessoa(cpf: proximo_cpf_teste, nome: "Gestor Hier Matrix")
      sufixo = SecureRandom.hex(3)

      raiz_attrs = { descricao: "Raiz Matrix #{sufixo}", active: raiz_ativa }
      raiz_attrs[papel] = gestor_pessoa.id if nivel == :avo
      raiz = criar_unidade(**raiz_attrs)

      inter_attrs = { descricao: "Intermediaria Matrix #{sufixo}", parent: raiz, active: true }
      inter_attrs[papel] = gestor_pessoa.id if nivel == :pai
      intermediaria = criar_unidade(**inter_attrs)

      folha = criar_unidade(descricao: "Folha Matrix #{sufixo}", parent: intermediaria, active: true)

      gestor = criar_usuario(nome: "Gestor Hier User #{sufixo}", cpf: gestor_pessoa.cpf)
      [ gestor, { raiz: raiz, intermediaria: intermediaria, folha: folha } ]
    end

    # --- espelho (inserts via insert_all — readonly bloqueia instâncias) -------

    def inserir(model, **atributos)
      id = model.insert_all([ atributos ], returning: :id).rows.first.first
      model.find(id)
    end

    def criar_tipo_vinculo(nome)
      Pessoas::TipoVinculo.find_by(nome: nome) || inserir(Pessoas::TipoVinculo, nome: nome)
    end

    def criar_vinculo_estado(nome:)
      Pessoas::VinculoEstado.find_by(nome: nome) || inserir(Pessoas::VinculoEstado, nome: nome)
    end

    def unidade_simples
      @unidade_simples ||= criar_unidade(descricao: "Unidade Simples Matrix", active: true)
    end

    def proximo_cpf_teste
      PessoasEspelhoHelper.proximo_cpf
    end

    def gestor_individual(gerido:, gestor_user:, ativo: true)
      gestor = GestorIndividual.create!(nome: "Gestor Teste Matrix", gestor_user: gestor_user)
      vinculo = GestorIndividualGerenciado.create!(gestor_individual: gestor, user: gerido)
      vinculo.desativar! unless ativo
      vinculo
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
  end
end
