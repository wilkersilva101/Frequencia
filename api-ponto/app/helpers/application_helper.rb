# frozen_string_literal: true

module ApplicationHelper
  # --------------------------------------------------------------------------
  # menu_activated? / eval_with_rescue
  #
  # Portado fielmente da gem `zutils` 4.0.0 (`Zutils::Helpers`), mixin usado
  # pelo `ApplicationHelper` do projeto de referência `basic8`. Fonte:
  # vendor/bundle/ruby/3.4.0/gems/zutils-4.0.0/lib/zutils/helpers.rb
  #
  # Por que `eval()`: a string avaliada (`menu_item[:active_test]`) é definida
  # internamente pelo desenvolvedor ao montar o Hash `@static_menu` (Sprint 25,
  # menu dinâmico) — nunca vem de input de usuário, `params`, `request` ou
  # qualquer fonte externa. Não é, portanto, uma superfície de RCE explorável
  # por um atacante externo. Ainda assim é `eval()` de fato, então a escolha é
  # documentada aqui de forma explícita para não ficar escondida de quem ler
  # o código.
  #
  # Decisão consciente confirmada com o usuário em 2026-09-14: portar
  # fielmente com `eval()`, em vez de reimplementar com uma comparação segura
  # de `request.path`, para manter o comportamento idêntico ao `basic8`.
  # --------------------------------------------------------------------------

  # rubocop:disable Security/Eval
  def eval_with_rescue(code)
    eval(code) # rubocop:disable Lint/RescueException
  rescue Exception => e
    "error"
  end
  # rubocop:enable Security/Eval

  def menu_activated?(menu_item)
    check = ->(test) { eval_with_rescue(test) rescue false }

    check.call(menu_item.dig(:active_test)) ||
      menu_item.dig(:children).to_a.any? { |c| check.call(c[:active_test]) } ||
      menu_item.dig(:children).to_a.flat_map { |c| c.dig(:children).to_a }.any? { |c| check.call(c[:active_test]) }
  end
end
