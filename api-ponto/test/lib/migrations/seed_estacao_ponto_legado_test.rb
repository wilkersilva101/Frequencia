require "test_helper"

# Cobre o Blocker B2 (code review Sprint 1): sem este dado, uma EstaçãoPonto
# física já configurada em produção com `cod_ativacao: "poc-ativacao-001"`
# passaria a falhar autenticação nos controllers `presenca/*` (regressão da
# antiga whitelist hardcoded). Testa que a migração de dados é idempotente.
class SeedEstacaoPontoLegadoTest < ActiveSupport::TestCase
  MIGRATION_PATH = Rails.root.join("db/migrate/20260826151000_seed_estacao_ponto_legado.rb")

  setup do
    load MIGRATION_PATH
    EstacaoPonto.where(cod_ativacao: "poc-ativacao-001").delete_all
  end

  test "cria a estacao legada quando ela nao existe" do
    assert_difference("EstacaoPonto.count", 1) do
      SeedEstacaoPontoLegado.new.up
    end

    estacao = EstacaoPonto.find_by(cod_ativacao: "poc-ativacao-001")
    assert estacao.present?
    assert_equal "Estação PoC (migração automática)", estacao.descricao
  end

  test "e idempotente ao rodar mais de uma vez" do
    SeedEstacaoPontoLegado.new.up

    assert_no_difference("EstacaoPonto.count") do
      SeedEstacaoPontoLegado.new.up
    end

    assert_equal 1, EstacaoPonto.where(cod_ativacao: "poc-ativacao-001").count
  end

  test "codigo de ativacao legado passa a ser valido apos a migracao" do
    SeedEstacaoPontoLegado.new.up

    assert EstacaoPonto.codigo_ativacao_valido?("poc-ativacao-001")
  end
end
