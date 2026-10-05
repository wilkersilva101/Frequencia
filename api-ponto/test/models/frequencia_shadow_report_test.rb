require "test_helper"

# Tarefa 29.8 (Sprint 29) — RELATÓRIO DO MODO SHADOW (critério 2 da 29.8).
#
# Mede, de forma DETERMINÍSTICA e reproduzível, a CONTAGEM DE NEGAÇÕES POR
# MOTIVO que o modo shadow emite sobre um conjunto FIXO de cenários reais.
#
# ── MÉTODO REPRODUZÍVEL (é isto que a entrega tem de declarar) ──────────────
# Os cenários são construídos pelo SCHEMA REAL do espelho (ADR-0006:
# `PessoasEspelhoHelper` + `insert_all`), o ator é um usuário NÃO-global fixo
# (sem role/admin — os passos 1–5 da cascata ficam todos exercitáveis) e a
# medição roda o CAMINHO REAL do controller
# (`Admin::FrequenciaController#index`, sob `com_flag("shadow")`) com um logger
# coletor. Reproduza com:
#
#   RAILS_ENV=test bin/rails test test/models/frequencia_shadow_report_test.rb
#
# O teste ASSERE os números (não só imprime): a contagem é INVARIANTE do
# processo — CPFs variam por pid, mas o número de alvos e os motivos não.
#
# ── O QUE "MOTIVO" É AQUI ───────────────────────────────────────────────────
# O shadow loga, por alvo OCULTO, o `motivo` do PORO `AutorizacaoFrequencia`
# (o primeiro match da cascata, ou `:negado`). Como o shadow só observa o que a
# cascata ocultaria, o motivo esperado de TODO evento é `:negado`; um motivo
# diferente de `:negado` entre os ocultos seria uma DIVERGÊNCIA
# scope-SQL × PORO (o scope esconder o que o PORO liberaria) — o teste a
# conta e a espera ZERO.
#
# A causa RAIZ da negação (por que `:negado`) é observável nos eventos `warn`
# do próprio PORO (`autorizacao_frequencia.unidade_inelegivel` /
# `pessoa_ausente`); a medição os conta à parte, para que o relatório não seja
# uma linha só.
#
# ── LIMITE DECLARADO ────────────────────────────────────────────────────────
# O modo shadow é acionado no CONTROLLER (`observar_cascata_frequencia`); não
# há uma tarefa de varredura do universo. Os cenários abaixo são uma AMOSTRA
# CONTROLADA, não a contagem de produção — para produção, os mesmos eventos
# (`EVENTO_SHADOW`/`EVENTO_NEGACAO`) saem no log e podem ser agregados por
# `motivo` com um parser de log. Este teste fixa a SEMÂNTICA e prova o formato.
module Admin
  class FrequenciaShadowReportTest < ActionDispatch::IntegrationTest
    include PessoasEspelhoHelper

    setup do
      skip_sem_espelho!
    end

    test "relatorio do shadow: contagem de negacoes por motivo sobre cenarios fixos" do
      # ------------------------------------------------------------------
      # Cenários (ator NÃO-global, sem role): 1 alvo VISÍVEL + 4 OCULTOS.
      # ------------------------------------------------------------------
      # Ator: pessoa no espelho, gestor (atual) da unidade U → passo 5.
      ator_pessoa = criar_pessoa(cpf: proximo_cpf_teste, nome: "Ator Shadow")
      unidade_u = criar_unidade(descricao: "Unidade Shadow U", active: true, gestor_id: ator_pessoa.id)
      ator = criar_usuario(nome: "Ator Shadow", cpf: ator_pessoa.cpf)

      # VISÍVEL: lotado em U (gestor = ator) → liberado pelo passo 5.
      visivel = alvo_lotado(nome: "Visivel Shadow", unidade: unidade_u)

      # OCULTO 1: sem relação nenhuma com o ator → :negado (passo 6).
      oculto_sem_relacao = alvo_lotado(nome: "Oculto Sem Relacao", unidade: unidade_sem_gestor)

      # OCULTO 2: terceirizado, e o ator NÃO tem a role → :negado.
      oculto_terceirizado = alvo_terceirizado(nome: "Oculto Terceirizado", unidade: unidade_sem_gestor)

      # OCULTO 3: gestor individual do ator, mas vínculo INATIVO → :negado.
      oculto_gi_inativo = alvo_lotado(nome: "Oculto GI Inativo", unidade: unidade_sem_gestor)
      gestor_individual(gerido: oculto_gi_inativo, gestor_user: ator, ativo: false)

      # OCULTO 4: lotado em unidade INATIVA (D6) cujo gestor é o ator → :negado
      # (e o PORO emite `unidade_inelegivel`).
      unidade_inativa = criar_unidade(descricao: "Unidade Shadow Inativa", active: false, gestor_id: ator_pessoa.id)
      oculto_unidade_inativa = alvo_lotado(nome: "Oculto Unidade Inativa", unidade: unidade_inativa)

      ocultos_esperados = [
        oculto_sem_relacao, oculto_terceirizado, oculto_gi_inativo, oculto_unidade_inativa
      ]

      # ------------------------------------------------------------------
      # Medição: roda o index real sob o modo shadow e coleta os eventos.
      # ------------------------------------------------------------------
      logger = RecordingLogger.new
      login_como(ator)
      com_flag("shadow") do
        with_logger(logger) do
          get frequencia_path
        end
      end
      assert_response :success

      shadow = logger.entradas.select { |e| e[:evento] == "frequencia_autorizacao_cascata.shadow" }

      # Contagem POR MOTIVO (a métrica pedida pelo critério).
      por_motivo = shadow.group_by { |e| e[:motivo] }.transform_values(&:size)

      # Asserções (números invariantes do processo):
      assert_equal 4, shadow.size, "shadow deve observar exatamente os 4 alvos ocultos"
      assert_equal({ negado: 4 }, por_motivo, "todo alvo oculto deve ter motivo :negado")

      # Nenhuma DIVERGÊNCIA scope × PORO: nenhum oculto com motivo != :negado.
      divergencias = shadow.reject { |e| e[:motivo] == :negado }
      assert_empty divergencias, "divergencia scope x PORO: o scope ocultou o que o PORO liberaria"

      # O alvo VISÍVEL não é observado pelo shadow (não é negado).
      ids_shadow = shadow.map { |e| e[:alvo_id] }.to_set
      refute_includes ids_shadow, visivel.id, "alvo visível não deve aparecer como negação do shadow"
      ocultos_esperados.each do |oculto|
        assert_includes ids_shadow, oculto.id, "alvo oculto #{oculto.nome_completo} deve ser negado pelo shadow"
      end

      # Causa raiz diagnostica do PORO (warn): a unidade INATIVA (D6) do
      # `oculto_unidade_inativa` é reportada com `unidade_inelegivel`.
      causas = logger.entradas.select { |e| e[:evento] == "autorizacao_frequencia.unidade_inelegivel" }
      assert_operator causas.size, :>=, 1, "a negacao por D6 deve ser diagnosticada (unidade_inelegivel)"

      # Dilema: imprimir o relatório no stdout do teste para que ele seja
      # colhido na medição (o assert acima é a garantia; isto é a evidência).
      puts "[SHADOW REPORT] eventos=#{shadow.size} por_motivo=#{por_motivo.inspect} " \
           "divergencias=#{divergencias.size} causas_unidade_inelegivel=#{causas.size}"
    end

    private

    # --- assertions -----------------------------------------------------------

    # --- login ----------------------------------------------------------------

    def login_como(user)
      hash = BCrypt::Password.create("123456")
      fake = Struct.new(:encrypted_password).new(hash)
      com_metodo_de_classe_stubado(Pessoas::User, :buscar_por_cpf, ->(_cpf) { fake }) do
        post login_path, params: { username: user.username, password: "123456" }
      end
    end

    # --- usuários / espelho ---------------------------------------------------

    def criar_usuario(nome: "Usuario Shadow", cpf: nil)
      User.create!(nome_completo: nome, password: "123456", cpf: cpf)
    end

    def criar_pessoa(cpf: proximo_cpf_teste, nome: "Pessoa Shadow")
      inserir(Pessoas::Pessoa, nome: nome, cpf: cpf)
    end

    def alvo_lotado(nome:, unidade:)
      cpf = proximo_cpf_teste
      pessoa = criar_pessoa(cpf: cpf, nome: nome)
      inserir_vinculo(pessoa: pessoa, unidade: unidade)
      user = criar_usuario(nome: nome, cpf: cpf)
      TimeRecord.create!(user: user, raw_data: "s", punched_at: Time.zone.now, authentication_mode: "biometric")
      user
    end

    def alvo_terceirizado(nome:, unidade:)
      cpf = proximo_cpf_teste
      pessoa = criar_pessoa(cpf: cpf, nome: nome)
      config = inserir(Pessoas::ConfiguracaoCadastro, tipo_vinculo_id: criar_tipo_vinculo("Terceirizado").id)
      inserir_vinculo(pessoa: pessoa, unidade: unidade, configuracao_cadastro_id: config.id)
      user = criar_usuario(nome: nome, cpf: cpf)
      TimeRecord.create!(user: user, raw_data: "t", punched_at: Time.zone.now, authentication_mode: "biometric")
      user
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

    def unidade_sem_gestor
      @unidade_sem_gestor ||= criar_unidade(descricao: "Unidade Shadow Sem Gestor", active: true)
    end

    def proximo_cpf_teste
      PessoasEspelhoHelper.proximo_cpf
    end

    def gestor_individual(gerido:, gestor_user:, ativo: true)
      gestor = GestorIndividual.create!(nome: "Gestor Shadow", gestor_user: gestor_user)
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

      def warn(payload = nil)
        @entradas << payload if payload.is_a?(Hash)
      end

      def debug(*); end
      def error(*); end
      def fatal(*); end
      def level(*); end

      attr_reader :entradas
    end
  end
end
