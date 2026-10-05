# frozen_string_literal: true

# Helper para trocar um MÉTODO DE CLASSE num teste SEM corromper o processo.
#
# ATENÇÃO (lição da Sprint 29 — ver `docs/governance/lessons.md`): no Rails os
# `scope` SÃO métodos de singleton definidos por
# `singleton_class.define_method(name)` (`activerecord/lib/active_record/scoping/named.rb`).
# Logo o padrão "define_singleton_method + remove_method para limpar" NÃO remove
# um stub: remove o PRÓPRIO método de produção. Como a suíte compartilha a VM
# (mesmo com `parallelize`, cada worker roda vários arquivos em sequência), o
# método fica morto para TODO arquivo rodado depois — falsificando os testes dos
# outros (contaminação order-dependent). O mesmo vale para `def self.` de models
# e services.
#
# Correção: capturar o `UnboundMethod` REAL antes de trocar e REINSTALÁ-LO no
# `ensure` — que roda inclusive quando o teste falha/levanta (o teardown do
# Minitest não é a única garantia; `ensure` cobre o bloco inteiro).
#
# Por que não `Pessoas::Vinculo.stub(...)`? O `Object#stub` do Minitest não
# existe neste bundle (Minitest 6.0.6 sem `minitest/mock` — medido). Este helper
# é o substituto manual do padrão capturar/restaurar.
#
# IMPORTANTE: use apenas para métodos OWN (definidos na própria classe: scopes e
# `def self.`). Para métodos HERDADOS do ORM (ex.: `find_by` do ActiveRecord), o
# padrão `define_singleton_method` + `remove_method` JÁ é seguro, porque o
# `remove_method` cai de volta no ancestral — não use este helper nesses casos
# (não há `UnboundMethod` próprio a capturar).
module ClassMethodStubHelper
  # Troca `owner.metodo` pelo `corpo` enquanto o bloco roda, restaurando o
  # método real ao final — inclusive sob falha/erro.
  #
  #   com_metodo_de_classe_stubado(Pessoas::Vinculo, :frequentadores_ativos,
  #                                ->(**_kwargs) { paginado }) do
  #     get frequentadores_path
  #   end
  #
  # `corpo` pode ser um `Proc`/`lambda` (recomendado, preserva a assinatura) ou
  # um `Method`. A restauração roda no `ensure`.
  def com_metodo_de_classe_stubado(owner, metodo, corpo, &bloco)
    com_metodos_de_classe_stubados([ [ owner, metodo, corpo ] ], &bloco)
  end

  # Variante para VÁRIOS métodos de uma vez (evita aninhamento profundo quando
  # o setup precisa trocar 2-3 pontos de entrada). Recebe uma lista de
  # `[owner, metodo, corpo]`. Restaura TODOS no `ensure`.
  #
  #   com_metodos_de_classe_stubados([
  #     [ Pessoas::Vinculo, :frequentadores_ativos, ->(**_k) { paginado } ],
  #     [ Pessoas::CategoriaTrabalhador, :em_uso, -> { categorias } ]
  #   ]) do
  #     get frequentadores_path
  #   end
  def com_metodos_de_classe_stubados(stubs)
    originais = stubs.map do |owner, metodo, _corpo|
      unless owner.respond_to?(metodo)
        raise ArgumentError, "#{owner} não responde a `#{metodo}` (não há método real a capturar)"
      end

      [ owner, metodo, owner.singleton_class.instance_method(metodo) ]
    end

    stubs.each { |owner, metodo, corpo| owner.define_singleton_method(metodo, corpo) }
    yield
  ensure
    originais.each { |owner, metodo, original| owner.singleton_class.send(:define_method, metodo, original) }
  end
end
