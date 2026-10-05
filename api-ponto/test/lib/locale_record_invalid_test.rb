require "test_helper"

# Bug 8 do Bug Finder (Sprint 29) — decisão do CTO 2026-09-29 (ADR-0007): o
# locale pt-BR precisa definir `record_invalid` para que `e.message` de um
# `ActiveRecord::RecordInvalid` traga os erros dos atributos em vez de
# "Translation missing". É a mensagem que o operador da 29.3 verá quando o
# upsert da importação falhar.
class LocaleRecordInvalidTest < ActiveSupport::TestCase
  test "record_invalid resolve no escopo activerecord usado pelo RecordInvalid" do
    valor = I18n.t("activerecord.errors.messages.record_invalid",
                   errors: "Nome não pode ficar em branco",
                   default: nil)

    assert_not_nil valor,
                   "o locale precisa definir activerecord.errors.messages.record_invalid"
    assert_includes valor, "Nome não pode ficar em branco",
                    "a mensagem deve interpolar %{errors}"
  end

  test "errors.messages.record_invalid também está definido (fallback do Rails)" do
    valor = I18n.t("errors.messages.record_invalid",
                   errors: "X", default: nil)

    assert_not_nil valor, "o fallback errors.messages.record_invalid deve existir"
  end

  test "e.message de RecordInvalid traz o erro do atributo, não Translation missing" do
    gestor = GestorIndividual.new(nome: nil)
    erro = assert_raises(ActiveRecord::RecordInvalid) { gestor.save! }

    assert_not_includes erro.message, "Translation missing",
                        "message crua ainda cai no fallback de tradução"
    assert_includes erro.message, "não pode ficar em branco",
                    "a mensagem deve conter o erro real do atributo"
  end

  test "errors.full_messages continua sendo a fonte preferida (reforço do CTO)" do
    gestor = GestorIndividual.new(nome: nil)
    assert_not gestor.valid?
    assert_includes gestor.errors.full_messages.join, "não pode ficar em branco"
  end
end
