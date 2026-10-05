ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
# Helpers do espelho Pessoas (ADR-0006). Incluídos só nas classes que usam o
# schema real, para não acoplar a suíte inteira ao banco espelho.
require_relative "support/pessoas_espelho_helper"
# Stub de método de classe capturar/restaurar (não destrutivo) — ver o próprio
# arquivo e a lição em docs/governance/lessons.md. Incluído na base para que
# QUALQUER teste stube métodos de classe sem vazar para os arquivos seguintes.
require_relative "support/class_method_stub_helper"

module ActiveSupport
  class TestCase
    # Stub de método de classe capturar/restaurar (não destrutivo).
    include ClassMethodStubHelper

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # A tabela `estacoes_ponto` não segue a inferência padrão de nome de
    # classe a partir do nome da fixture (`estacoes_ponto` → `EstacoesPonto`),
    # já que o model real é `EstacaoPonto` (ver `self.table_name` no model).
    set_fixture_class estacoes_ponto: EstacaoPonto

    # Add more helper methods to be used by all tests here...
  end
end
