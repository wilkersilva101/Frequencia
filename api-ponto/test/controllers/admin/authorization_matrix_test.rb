require "test_helper"

# Task 23.7 (Sprint 23) — CanCanCan nos controllers admin.
#
# Suíte de autorização do Frequencia (migração Frequencia/api-ponto).
#
# As tasks 23.1-23.6 entregaram autenticação por sessão (Admin::SessionsController),
# `current_user` baseado em session (gem API-only) e Rolify/Devise no model User;
# os 15 controllers admin receberam a integração CanCanCan (`authorize!` ou
# `load_and_authorize_resource`) na própria task 23.7 (commit da Sprint 23).
#
# O que está coberto aqui é o GAP REAL que ficou para esta tarefa: a matriz de
# autorização por perfil no nível de CONTROLLER (Rails way: teste de integração
# exercita a esteira completa — router → before_action → CanCan → action) e a
# verificação de que o `current_ability` do controller deriva do usuário
# autenticado na sessão (contexto API-only, sem Warden).
#
# Perfis testados (fonte de verdade: ability.rb, task 23.5 — NÃO alterado aqui):
#   guest (não autenticado)        → nada (require_login)
#   autenticado sem role           → baseline de leitura 23.7 (`can :read, :all`)
#   operador                       → leitura + escrita negada
#   gestor                         → leitura (gestão do próprio escopo) + escrita
#                                    administrativa negada (RN05/RN06: gestor não
#                                    edita User/Role/EstacaoPonto; manage só em
#                                    TimeRecord/IntervencaoFrequencia)
#   admin via Rolify (coluna false)→ manage total (`user.admin? || has_role?(:admin)`)
#
# Regras do commit 2d99706 mantidas: mesmo padrão de stubs do
# `Pessoas::Vinculo` (banco pessoas_test sem schema — task 8.13) e usuários
# criados inline (username gerado pelo callback do User), sem tocar fixtures.
module Admin
  class AuthorizationMatrixTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    # ----------------------------------------------------------------------
    # Helpers (mesmo padrão dos demais arquivos de teste admin)
    # ----------------------------------------------------------------------

    def criar_gestor
      User.create!(nome_completo: "Gestor Matriz Teste", password: "123456").tap do |user|
        user.add_role(:gestor)
      end
    end

    def criar_operador
      User.create!(nome_completo: "Operador Matriz Teste", password: "123456").tap do |user|
        user.add_role(:operador)
      end
    end

    # Admin via Rolify ONLY — a coluna `admin` permanece false, exercitando a
    # condição `user.has_role?(:admin)` da Ability (não a coluna legada).
    def criar_admin_por_role
      User.create!(nome_completo: "Admin Rolify Teste", password: "123456").tap do |user|
        user.add_role(:admin)
      end
    end

    def criar_usuario_sem_role
      User.create!(nome_completo: "Usuario Sem Role Teste", password: "123456")
    end

    def login_como(user)
      post login_path, params: { username: user.username, password: "123456" }
      assert_response :redirect
      follow_redirect!
    end

    def trocar_usuario(user)
      delete logout_path
      post login_path, params: { username: user.username, password: "123456" }
      follow_redirect!
    end

    def registrar_estacao!(descricao: "Estacao Matriz Teste", cod_ativacao: "mx-teste-0001")
      EstacaoPonto.create!(descricao: descricao, cod_ativacao: cod_ativacao)
    end

    def registrar_regime!(nome: "Regime Matriz Teste")
      Regime.create!(nome: nome, modalidade: "HORAS")
    end

    def registrar_versao!(numero: "1.0.0")
      Versao.create!(numero: numero)
    end

    # Stub do ponto de entrada da listagem de usuários (Pessoas::Vinculo —
    # banco pessoas_test sem schema, task 8.13). Assinatura com **kwargs para
    # aceitar os argumentos nomeados que o Admin::UsersController#index passa.
    def stub_frequentadores_ativos
      paginado = Kaminari.paginate_array([]).page(1)
      # `def self.frequentadores_ativos` é método real de produção — remove_method
      # o apagaria para os arquivos seguintes do mesmo processo (ver lição em
      # docs/governance/lessons.md). Captura/restaura o UnboundMethod real.
      com_metodo_de_classe_stubado(Pessoas::Vinculo, :frequentadores_ativos, ->(**_kwargs) { paginado }) { yield }
    end

    # ----------------------------------------------------------------------
    # Matriz por perfil
    # ----------------------------------------------------------------------

    test "guest (nao autenticado) e redirecionado para o login em leitura e escrita" do
      # leitura
      get dashboard_path
      assert_redirected_to login_path
      assert_nil @controller.send(:current_user), "guest nao tem current_user (sessao vazia)"
      get estacoes_path
      assert_redirected_to login_path
      get regimes_path
      assert_redirected_to login_path
      get versoes_path
      assert_redirected_to login_path
      get parcial_path
      assert_redirected_to login_path
      get relatorio_terceirizados_path
      assert_redirected_to login_path

      # escrita — nenhum registro pode ser criado por guest
      get new_estacao_path
      assert_redirected_to login_path
      assert_no_difference("EstacaoPonto.count") do
        post estacoes_path, params: { estacao: { descricao: "Estacao Guest", cod_ativacao: "mx-guest-0001" } }
      end
      assert_redirected_to login_path
      assert_no_difference("Regime.count") do
        post regimes_path, params: { regime: { nome: "Regime Guest" } }
      end
      assert_redirected_to login_path
      assert_no_difference("Versao.count") do
        post versoes_path, params: { versao: { numero: "9.9.9" } }
      end
      assert_redirected_to login_path
    end

    test "admin via role Rolify (coluna admin false) gerencia CRUD e acoes de manutencao" do
      admin = criar_admin_por_role
      refute admin.admin?, "pre-condicao: admin do teste deve ser via role, nao pela coluna legada"
      login_como(admin)

      # create EstacaoPonto (CRUD puro convertido para load_and_authorize_resource)
      assert_difference("EstacaoPonto.count", 1) do
        post estacoes_path, params: { estacao: { descricao: "Estacao do Admin Role", cod_ativacao: "mx-role-0001" } }
      end
      assert_redirected_to estacoes_path

      # update Regime (mesmo fluxo — loader carrega e autoriza)
      regime = registrar_regime!
      patch regime_path(regime), params: { regime: { nome: "Regime Renomeado Pelo Admin" } }
      assert_redirected_to regimes_path
      assert_equal "Regime Renomeado Pelo Admin", regime.reload.nome

      # create Versao
      assert_difference("Versao.count", 1) do
        post versoes_path, params: { versao: { numero: "2.0.0" } }
      end
      assert_redirected_to versoes_path

      # manutencao: sincronizar afastamentos enfileira o job (admin tem :manage)
      assert_enqueued_with(job: SincronizarAfastamentosJob, args: []) do
        post sincronizar_agora_direitos_deveres_path
      end
      assert_redirected_to direitos_deveres_path
    end

    test "gestor le telas de consulta mas nao gerencia recursos administrativos (RN05/RN06)" do
      gestor = criar_gestor
      login_como(gestor)

      # leitura liberada (baseline de leitura 23.7: todo autenticado lê)
      get dashboard_path
      assert_response :success
      get estacoes_path
      assert_response :success
      get regimes_path
      assert_response :success
      get versoes_path
      assert_response :success
      get frequencia_path
      assert_response :success
      get time_records_path
      assert_response :success
      get gestores_individuais_path
      assert_response :success
      get parcial_path
      assert_response :success
      get relatorio_terceirizados_path
      assert_response :success

      # users index exige stub do Pessoas (sem schema de teste — task 8.13)
      stub_frequentadores_ativos do
        get users_path
        assert_response :success
      end

      # escrita administrativa negada → CanCan::AccessDenied → dashboard
      get new_estacao_path
      assert_redirected_to dashboard_path

      assert_no_difference("EstacaoPonto.count") do
        post estacoes_path, params: { estacao: { descricao: "Estacao do Gestor", cod_ativacao: "mx-gestor-0001" } }
      end
      assert_redirected_to dashboard_path
      # Task 23.10 — contrato do rescue_from CanCan::AccessDenied (23.7):
      # o redirect para dashboard vem acompanhado do flash alert com a
      # mensagem da exceção. Presença (não texto exato) porque a mensagem
      # default do CanCan é em inglês e não é contrato de I18n da Sprint 23.
      assert flash[:alert].present?, "AccessDenied deve preencher flash alert (rescue_from CanCan::AccessDenied)"

      regime = registrar_regime!
      patch regime_path(regime), params: { regime: { nome: "Hack via gestor" } }
      assert_redirected_to dashboard_path
      assert_equal "Regime Matriz Teste", regime.reload.nome

      assert_no_difference("Versao.count") do
        post versoes_path, params: { versao: { numero: "9.9.9" } }
      end
      assert_redirected_to dashboard_path

      # gestor nao edita User (RN06) nem dispara manutencao (only admin)
      alvo = criar_usuario_sem_role
      patch user_path(alvo), params: { user: { nome_completo: "Hack via gestor" } }
      assert_redirected_to dashboard_path
      assert_not_equal "Hack via gestor", alvo.reload.nome_completo

      assert_no_enqueued_jobs(only: SincronizarAfastamentosJob) do
        post sincronizar_agora_direitos_deveres_path
      end
      assert_redirected_to dashboard_path
    end

    test "operador le telas de consulta mas nao edita nem gerencia recursos" do
      operador = criar_operador
      login_como(operador)

      get dashboard_path
      assert_response :success
      get estacoes_path
      assert_response :success
      get versoes_path
      assert_response :success
      get parcial_path
      assert_response :success
      get relatorio_terceirizados_path
      assert_response :success

      # nao edita recurso existente (dev example: operador não edita)
      estacao = registrar_estacao!
      patch estacao_path(estacao), params: { estacao: { descricao: "Hack via operador" } }
      assert_redirected_to dashboard_path
      assert_equal "Estacao Matriz Teste", estacao.reload.descricao

      # nao abre formulario de criacao
      get new_versao_path
      assert_redirected_to dashboard_path

      # nao gerencia
      assert_no_enqueued_jobs(only: SincronizarAfastamentosJob) do
        post sincronizar_agora_direitos_deveres_path
      end
      assert_redirected_to dashboard_path
    end

    test "autenticado sem role mantem a baseline de leitura 23.7 mas nao escreve" do
      usuario = criar_usuario_sem_role
      login_como(usuario)

      get dashboard_path
      assert_response :success
      get estacoes_path
      assert_response :success
      get regimes_path
      assert_response :success
      get versoes_path
      assert_response :success
      get parcial_path
      assert_response :success
      get relatorio_terceirizados_path
      assert_response :success

      assert_no_difference("EstacaoPonto.count") do
        post estacoes_path, params: { estacao: { descricao: "Estacao Sem Role", cod_ativacao: "mx-sem-role-0001" } }
      end
      assert_redirected_to dashboard_path

      regime = registrar_regime!
      patch regime_path(regime), params: { regime: { nome: "Hack via sem-role" } }
      assert_redirected_to dashboard_path
      assert_equal "Regime Matriz Teste", regime.reload.nome
    end

    # ----------------------------------------------------------------------
    # current_ability (contexto API-only — Ability é derivada do current_user
    # de sessão, e não de Warden)
    # ----------------------------------------------------------------------

    test "current_ability deriva do current_user autenticado na sessao" do
      admin = criar_admin_por_role
      login_como(admin)
      get dashboard_path

      ability_admin = @controller.current_ability
      assert_instance_of Ability, ability_admin
      assert ability_admin.can?(:manage, :all)
      assert ability_admin.can?(:manage, EstacaoPonto)
      assert ability_admin.can?(:read, :all)

      # troca de usuário na mesma sessão → ability recalculada por request
      gestor = criar_gestor
      trocar_usuario(gestor)
      get estacoes_path

      ability_gestor = @controller.current_ability
      assert ability_gestor.can?(:read, EstacaoPonto)
      assert ability_gestor.can?(:read, :all)
      refute ability_gestor.can?(:manage, User)
      refute ability_gestor.can?(:update, EstacaoPonto.new)
      refute ability_gestor.can?(:destroy, Regime.new)
    end
  end
end
