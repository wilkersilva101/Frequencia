require "test_helper"

class ResolverCpfPorMatriculaServiceTest < ActiveSupport::TestCase
  # Não usamos dados reais no banco `pessoas` de teste (sem schema
  # carregado, ver nota em test/jobs/importar_dados_pessoa_job_test.rb) —
  # stubamos o ponto de entrada único que o serviço usa,
  # `Pessoas::GestorhContrachequeMirror.pares_matricula_cpf_para`.
  # `pares_matricula_cpf_para` é `def self.` real de produção: captura/restaura o
  # UnboundMethod (remove_method o apagaria para os arquivos seguintes do
  # processo — ver docs/governance/lessons.md).
  def stub_pares(resposta)
    com_metodo_de_classe_stubado(
      Pessoas::GestorhContrachequeMirror, :pares_matricula_cpf_para,
      ->(*_args, **_kwargs) { resposta }
    ) { yield }
  end

  test "resolve as matriculas encontradas na competencia" do
    pares = [ [ "1001", "11122233344" ], [ "1002", "55566677788" ] ]

    resultado = nil
    stub_pares(pares) do
      resultado = ResolverCpfPorMatriculaService.call(%w[1001 1002], mes: 7, ano: 2026)
    end

    assert_equal({ "1001" => "11122233344", "1002" => "55566677788" }, resultado)
  end

  test "matricula nao encontrada na competencia nao aparece no resultado" do
    pares = [ [ "1001", "11122233344" ] ]

    resultado = nil
    stub_pares(pares) do
      resultado = ResolverCpfPorMatriculaService.call(%w[1001 9999], mes: 7, ano: 2026)
    end

    assert_equal({ "1001" => "11122233344" }, resultado)
    assert_not resultado.key?("9999")
  end

  test "retorna hash vazio quando a competencia esta vazia" do
    resultado = nil
    stub_pares([]) do
      resultado = ResolverCpfPorMatriculaService.call(%w[1001], mes: 7, ano: 2026)
    end

    assert_equal({}, resultado)
  end

  test "normaliza matriculas para string na busca (integer vs string)" do
    pares = [ [ "1001", "11122233344" ] ]

    resultado = nil
    stub_pares(pares) do
      resultado = ResolverCpfPorMatriculaService.call([ 1001 ], mes: 7, ano: 2026)
    end

    assert_equal({ "1001" => "11122233344" }, resultado)
  end

  test "ignora registros da competencia sem matricula ou cpf" do
    pares = [
      [ "1001", "11122233344" ],
      [ nil, "99988877766" ],
      [ "1002", nil ]
    ]

    resultado = nil
    stub_pares(pares) do
      resultado = ResolverCpfPorMatriculaService.call(%w[1001 1002], mes: 7, ano: 2026)
    end

    assert_equal({ "1001" => "11122233344" }, resultado)
  end

  test "chama pares_matricula_cpf_para apenas uma vez por instancia mesmo com multiplas chamadas" do
    chamadas = 0
    pares = [ [ "1001", "11122233344" ] ]

    com_metodo_de_classe_stubado(Pessoas::GestorhContrachequeMirror, :pares_matricula_cpf_para, ->(*_args, **_kwargs) do
      chamadas += 1
      pares
    end) do
      service = ResolverCpfPorMatriculaService.new(mes: 7, ano: 2026)
      service.call(%w[1001])
      service.call(%w[1001])
    end

    assert_equal 1, chamadas
  end

  # --- mais_recente (10B.3) ---

  test "mais_recente prioriza o mes atual quando a matricula aparece nos dois" do
    travel_to Time.zone.local(2026, 7, 15) do
      com_metodo_de_classe_stubado(Pessoas::GestorhContrachequeMirror, :pares_matricula_cpf_para, ->(mes:, ano:) do
        if mes == 7 && ano == 2026
          [ [ "1001", "AAA_MES_ATUAL" ] ]
        elsif mes == 6 && ano == 2026
          [ [ "1001", "BBB_MES_ANTERIOR" ] ]
        else
          []
        end
      end) do
        resultado = ResolverCpfPorMatriculaService.mais_recente(%w[1001])
        assert_equal({ "1001" => "AAA_MES_ATUAL" }, resultado)
      end
    end
  end

  test "mais_recente usa o mes anterior quando a matricula so aparece nele" do
    travel_to Time.zone.local(2026, 7, 15) do
      com_metodo_de_classe_stubado(Pessoas::GestorhContrachequeMirror, :pares_matricula_cpf_para, ->(mes:, ano:) do
        if mes == 6 && ano == 2026
          [ [ "2002", "SO_MES_ANTERIOR" ] ]
        else
          []
        end
      end) do
        resultado = ResolverCpfPorMatriculaService.mais_recente(%w[2002])
        assert_equal({ "2002" => "SO_MES_ANTERIOR" }, resultado)
      end
    end
  end

  test "mais_recente atravessa a virada de ano corretamente (janeiro cai para dezembro do ano anterior)" do
    travel_to Time.zone.local(2026, 1, 10) do
      chamadas_mes_ano = []

      com_metodo_de_classe_stubado(Pessoas::GestorhContrachequeMirror, :pares_matricula_cpf_para, ->(mes:, ano:) do
        chamadas_mes_ano << [ mes, ano ]
        []
      end) do
        ResolverCpfPorMatriculaService.mais_recente(%w[1001])
        assert_includes chamadas_mes_ano, [ 12, 2025 ]
        assert_includes chamadas_mes_ano, [ 1, 2026 ]
      end
    end
  end
end
