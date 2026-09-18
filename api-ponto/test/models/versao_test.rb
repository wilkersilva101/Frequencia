require "test_helper"

class VersaoTest < ActiveSupport::TestCase
  test "valid with numero" do
    versao = Versao.new(numero: "1.0.0")
    assert versao.valid?
  end

  test "invalid without numero" do
    versao = Versao.new(novidades: "Correções diversas")
    assert_not versao.valid?
    assert_includes versao.errors[:numero], "não pode ficar em branco"
  end

  test "aceita novidades e link opcionais" do
    versao = Versao.create!(numero: "1.2.0", novidades: "Correção de bug de login", link: "https://example.com/download")
    assert_equal "Correção de bug de login", versao.novidades
    assert_equal "https://example.com/download", versao.link
  end

  test "usa a tabela versoes" do
    assert_equal "versoes", Versao.table_name
  end
end
