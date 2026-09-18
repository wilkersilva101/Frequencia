# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "menu_activated? retorna truthy quando active_test do próprio item avalia para true" do
    menu_item = { active_test: "1 == 1" }

    assert menu_activated?(menu_item)
  end

  test "menu_activated? retorna false quando active_test do próprio item avalia para false" do
    menu_item = { active_test: "1 == 2" }

    assert_equal false, menu_activated?(menu_item)
  end

  # Comportamento fielmente portado de `Zutils::Helpers` (ver comentário de
  # topo em application_helper.rb): `eval_with_rescue` captura qualquer
  # exceção (ex: código com sintaxe inválida) e retorna a string "error" —
  # que em Ruby é um valor truthy. Isso significa que um `active_test` com
  # código inválido faz `menu_activated?` retornar truthy (a string "error"),
  # não `false`. É uma peculiaridade do código original do basic8, preservada
  # de propósito aqui por ser uma porta fiel, não uma reimplementação.
  test "menu_activated? com active_test inválido cai no rescue e retorna a string 'error' (truthy)" do
    menu_item = { active_test: "isso não é ruby válido &&&" }

    result = menu_activated?(menu_item)

    assert_equal "error", result
  end

  test "menu_activated? retorna true quando item pai não ativa mas um filho ativa" do
    menu_item = {
      active_test: "1 == 2",
      children: [
        { active_test: "1 == 2" },
        { active_test: "1 == 1" }
      ]
    }

    assert menu_activated?(menu_item)
  end

  test "menu_activated? retorna true quando um neto (filho de filho) ativa" do
    menu_item = {
      active_test: "1 == 2",
      children: [
        {
          active_test: "1 == 2",
          children: [
            { active_test: "1 == 2" },
            { active_test: "1 == 1" }
          ]
        }
      ]
    }

    assert menu_activated?(menu_item)
  end

  # Comportamento fielmente portado (mesma peculiaridade do teste acima):
  # quando não há `active_test` em nenhum nível, `menu_item.dig(:active_test)`
  # retorna `nil`, e `eval(nil)` levanta `TypeError` — capturado por
  # `eval_with_rescue`, que retorna a string "error" (truthy). Verificado
  # empiricamente antes de escrever este teste (não é suposição): o helper
  # portado NÃO retorna `false`/`nil` para um item totalmente sem
  # `active_test` — retorna "error", assim como no `basic8`/`zutils`.
  test "menu_activated? sem active_test em nenhum nível também cai no rescue e retorna 'error' (truthy)" do
    menu_item = {
      children: [
        { children: [ {} ] }
      ]
    }

    assert_equal "error", menu_activated?(menu_item)
  end
end
