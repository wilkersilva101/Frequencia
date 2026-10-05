require "test_helper"

# Tarefa 29.7 (Sprint 29) — testes da cascata de autorização na `Ability`,
# atrás da flag `FREQUENCIA_AUTORIZACAO_CASCATA` (Decisão D2/D3 do CTO).
#
# Cobre os critérios de aceite da 29.7 no nível do model:
#   - flag LIGADA: `can :read` dos 4 recursos de frequência por instância
#     segundo a visibilidade do alvo; `gestor` só gerencia frequência visível;
#   - flag DESLIGADA e modo SHADOW: comportamento IDÊNTICO ao atual (baseline);
#   - as DEMAIS telas/seções seguem com o baseline `can :read, :all`.
#
# A visibilidade é injetada pelo MESMO ponto de entrada de produção
# (`Pessoas::Vinculo.cpfs_frequentadores_visiveis`), stubado com o helper
# `com_metodo_de_classe_stubado` (nunca `remove_method` — ver lessons.md).
class AbilityCascataTest < ActiveSupport::TestCase
  setup do
    @usuario = User.create!(nome_completo: "Usuario Cascata", password: "123456", cpf: "11122233344")
    @visivel = User.create!(nome_completo: "Alvo Visivel", password: "123456", cpf: "55566677788")
    @oculto = User.create!(nome_completo: "Alvo Oculto", password: "123456", cpf: "99988877766")
    # O usuário só enxerga a si mesmo e @visivel.
    @cpfs_visiveis = [ @usuario.cpf, @visivel.cpf ]
  end

  # --------------------------------------------------------------- flag OFF

  test "flag desligada mantem o baseline: leitura de frequencia por classe e por instancia" do
    com_cpfs_visiveis do
      ability = Ability.new(@usuario)

      assert ability.can?(:read, TimeRecord), "baseline: :read por classe"
      assert ability.can?(:read, TimeRecord.new(user_id: @oculto.id)),
             "baseline: :read de instancia de frequentador NAO visivel (comportamento atual)"
      assert_not ability.can?(:manage, TimeRecord)
    end
  end

  test "modo shadow mantem o baseline (nao nega)" do
    com_flag("shadow") do
      com_cpfs_visiveis do
        ability = Ability.new(@usuario)
        assert ability.can?(:read, TimeRecord)
        assert ability.can?(:read, TimeRecord.new(user_id: @oculto.id)),
               "shadow NAO nega — só loga"
      end
    end
  end

  # ------------------------------------------------------------- flag ON

  test "flag ligada: leitura de frequencia por instancia usa pode_ver? (visivel sim, oculto nao)" do
    com_flag("on") do
      com_cpfs_visiveis do
        ability = Ability.new(@usuario)

        # Admissão por classe (load_and_authorize_resource): a restrição fina é
        # por instância/listagem, então a classe continua liberada.
        assert ability.can?(:read, TimeRecord)
        assert ability.can?(:read, CalculoDiario)
        assert ability.can?(:read, RegistroMensalFrequencia)
        assert ability.can?(:read, IntervencaoFrequencia)

        # Visível: próprio e @visivel.
        assert ability.can?(:read, TimeRecord.new(user_id: @usuario.id))
        assert ability.can?(:read, TimeRecord.new(user_id: @visivel.id))
        assert ability.can?(:read, CalculoDiario.new(user_id: @visivel.id))
        assert ability.can?(:read, RegistroMensalFrequencia.new(user_id: @visivel.id))
        assert ability.can?(:read, IntervencaoFrequencia.new(user_id: @visivel.id))

        # Oculto: @oculto nao entra em nenhum dos 4 recursos.
        assert_not ability.can?(:read, TimeRecord.new(user_id: @oculto.id))
        assert_not ability.can?(:read, CalculoDiario.new(user_id: @oculto.id))
        assert_not ability.can?(:read, RegistroMensalFrequencia.new(user_id: @oculto.id))
        assert_not ability.can?(:read, IntervencaoFrequencia.new(user_id: @oculto.id))
      end
    end
  end

  test "flag ligada: as demais secoes seguem com o baseline can :read, :all" do
    com_flag("on") do
      com_cpfs_visiveis do
        ability = Ability.new(@usuario)

        assert ability.can?(:read, :all)
        assert ability.can?(:read, User)
        assert ability.can?(:read, EstacaoPonto)
        assert ability.can?(:read, RelatorioFrequenciaFinal)
        # Sem escrita fora do escopo (como hoje).
        assert_not ability.can?(:manage, EstacaoPonto)
      end
    end
  end

  test "flag ligada: recurso sem dono (user_id nulo) e negado (fail-closed)" do
    com_flag("on") do
      com_cpfs_visiveis do
        ability = Ability.new(@usuario)

        # `user_id` nulo não pertence a ninguém visível — a guarda
        # `return false if user_id.blank?` fecha em fail-closed (não libera por
        # ausência de informação).
        assert_not ability.can?(:read, TimeRecord.new(user_id: nil))
        assert_not ability.can?(:read, CalculoDiario.new(user_id: nil))
        assert_not ability.can?(:read, IntervencaoFrequencia.new(user_id: nil))
        assert_not ability.can?(:read, RegistroMensalFrequencia.new(user_id: nil))
      end
    end
  end

  test "flag ligada: guest continua sem nenhuma permissao" do
    com_flag("on") do
      com_cpfs_visiveis do
        ability = Ability.new(User.new)
        assert_not ability.can?(:read, TimeRecord)
        assert_not ability.can?(:read, :all)
      end
    end
  end

  test "flag ligada: admin continua lendo frequencia de qualquer frequentador" do
    admin = User.create!(nome_completo: "Admin Cascata", password: "123456", admin: true)
    com_flag("on") do
      com_cpfs_visiveis do
        ability = Ability.new(admin)
        assert ability.can?(:manage, :all)
        assert ability.can?(:read, TimeRecord.new(user_id: @oculto.id)),
               "admin curto-circuita a cascata"
      end
    end
  end

  # ------------------------------------------------------------- gestor

  test "flag desligada: gestor gerencia TimeRecord/IntervencaoFrequencia sem escopo (atual)" do
    gestor = User.create!(nome_completo: "Gestor Sem Flag", password: "123456")
    gestor.add_role(:gestor)
    com_cpfs_visiveis do
      ability = Ability.new(gestor)
      assert ability.can?(:manage, TimeRecord)
      assert ability.can?(:update, TimeRecord.new(user_id: @oculto.id)),
             "sem flag o gestor gerencia qualquer registro (comportamento atual)"
    end
  end

  test "flag ligada: gestor so gerencia frequencia de frequentadores visiveis" do
    gestor = User.create!(nome_completo: "Gestor Com Flag", password: "123456")
    gestor.add_role(:gestor)

    # O gestor enxerga apenas a si mesmo (cpfs visiveis = só o dele).
    com_flag("on") do
      com_cpfs_visiveis([ gestor.cpf ]) do
        ability = Ability.new(gestor)

        assert ability.can?(:update, TimeRecord.new(user_id: gestor.id)), "próprio é visível"
        assert_not ability.can?(:update, TimeRecord.new(user_id: @oculto.id)),
                   "gestor NAO gerencia registro de frequentador oculto sob a flag"
        assert_not ability.can?(:destroy, IntervencaoFrequencia.new(user_id: @oculto.id))
        assert ability.can?(:update, IntervencaoFrequencia.new(user_id: gestor.id))
        assert ability.can?(:deferir, IntervencaoFrequencia.new(user_id: gestor.id))
      end
    end
  end

  private

  # Stub do ponto de entrada de visibilidade. Por padrão usa `@cpfs_visiveis`;
  # pode receber uma lista própria.
  def com_cpfs_visiveis(cpfs = @cpfs_visiveis, &bloco)
    com_metodo_de_classe_stubado(
      Pessoas::Vinculo, :cpfs_frequentadores_visiveis, ->(_usuario) { cpfs }
    ) { bloco.call }
  end

  # A flag é estado global do processo — restaura o valor anterior no `ensure`.
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
