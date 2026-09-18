ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
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
