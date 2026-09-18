require "test_helper"

module Presenca
  class AdicioneEstacaoControllerTest < ActionDispatch::IntegrationTest
    # Sprint 1 (Task 1.4): EP-06 (heartbeat) passou a gravar/consultar
    # `EstacaoPonto` real em vez de responder "OK" fixo (ver
    # docs/07-estacao-ponto/02-endpoints-consumidos.md).

    test "GET show returns true and updates ultimo_contato for a known station" do
      estacao = estacoes_ponto(:one)
      contato_anterior = estacao.ultimo_contato

      get "/presenca/AdicioneEstacao", params: {
        codAtivacao: estacao.cod_ativacao,
        versao: "1.2",
        estadoEstacao: "FUNCIONANDO"
      }

      assert_response :ok
      assert_equal "true", @response.body
      estacao.reload
      assert_not_equal contato_anterior, estacao.ultimo_contato
      assert_equal "1.2", estacao.versao
    end

    test "GET show returns false for an unknown activation code" do
      get "/presenca/AdicioneEstacao", params: {
        codAtivacao: "codigo-inexistente",
        versao: "1.2",
        estadoEstacao: "FUNCIONANDO"
      }

      assert_response :ok
      assert_equal "false", @response.body
    end

    test "GET show returns false when codAtivacao is missing" do
      get "/presenca/AdicioneEstacao"

      assert_response :ok
      assert_equal "false", @response.body
    end

    test "GET show returns false for the unsupported-OS sentinel (not a real station)" do
      get "/presenca/AdicioneEstacao", params: { codAtivacao: "SistemaOperacionalNaoSuportado" }

      assert_response :ok
      assert_equal "false", @response.body
    end

    test "GET show does not update versao when versao param is absent" do
      estacao = estacoes_ponto(:one)
      versao_anterior = estacao.versao

      get "/presenca/AdicioneEstacao", params: { codAtivacao: estacao.cod_ativacao }

      assert_response :ok
      assert_equal "true", @response.body
      estacao.reload
      assert_equal versao_anterior, estacao.versao
    end
  end
end
