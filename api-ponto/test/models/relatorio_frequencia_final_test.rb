require "test_helper"

class RelatorioFrequenciaFinalTest < ActiveSupport::TestCase
  test "valido com ano, mes e data_geracao" do
    relatorio = RelatorioFrequenciaFinal.new(ano: 2026, mes: 9, data_geracao: Time.current)
    assert relatorio.valid?
  end

  test "invalido sem mes" do
    relatorio = RelatorioFrequenciaFinal.new(ano: 2026, data_geracao: Time.current)
    assert_not relatorio.valid?
  end

  test "mes deve estar entre 1 e 12" do
    relatorio = RelatorioFrequenciaFinal.new(ano: 2026, mes: 13, data_geracao: Time.current)
    assert_not relatorio.valid?
  end

  test "indice unico em ano e mes impede duplicata" do
    RelatorioFrequenciaFinal.create!(ano: 2026, mes: 9, data_geracao: Time.current)
    duplicado = RelatorioFrequenciaFinal.new(ano: 2026, mes: 9, data_geracao: Time.current)

    assert_not duplicado.valid?
    assert_raises(ActiveRecord::RecordInvalid) { duplicado.save! }
  end
end
