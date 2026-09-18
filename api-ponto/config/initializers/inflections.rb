# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, "\\1en"
#   inflect.singular /^(ox)en/i, "\\1"
#   inflect.irregular "person", "people"
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym "RESTful"
# end

# NOTE: "estacoes" é plural irregular em português (estação/estações) — o
# inflector padrão (locale :en) singulariza para "estaco", quebrando o path
# helper `estacao_path` usado pelas rotas de `admin/estacoes` (Task 1.3).
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.irregular "estacao", "estacoes"

  # Mesmo problema para "frequentador"/"frequentadores": o inflector padrão
  # singulariza para "frequentadore", quebrando o path helper de member route
  # `reimportar_dados_pessoa_frequentador_path` (Sprint 8, Task 8.7).
  inflect.irregular "frequentador", "frequentadores"

  # "categoria" termina em "-ia", e o Rails trata palavras assim como plural
  # latino já existente (mesmo padrão de "bacteria"/"bacterium") — por
  # padrão ele se recusa a pluralizar de novo (`pluralize("categoria") ==
  # "categoria"`), o que quebrava o nome de tabela do model
  # `RegimeCategoria` (Sprint 11, estrutura real do Regime — 2026-08-31).
  inflect.irregular "categoria", "categorias"

  # "caches" (de "cache") singulariza errado por padrão: o Rails trata
  # palavras terminadas em "-ches" como plural de "-ch" (ex.: "churches" →
  # "church"), então `singularize("frequentador_caches")` virava
  # "frequentador_cach" (sem o "e" final) — quebrava a inferência de classe
  # de `has_many :afastamento_caches`/`:frequentador_caches` (Sprint 12,
  # `AfastamentoCache`/`FrequentadorCache`, 2026-08-31).
  inflect.irregular "cache", "caches"

  # "versao" segue o mesmo padrão de "estacao": o inflector padrão (locale
  # :en) singulariza "versoes" para "verso" (perde o "a" nasal do
  # português), quebrando o path helper `versao_path`/inferência de classe
  # de `Versao` a partir da tabela `versoes` (Sprint 14, Task 14.4).
  inflect.irregular "versao", "versoes"

  # Mesmo problema de "categoria" (acima) — "frequencia" também termina em
  # "-ia" e o Rails se recusa a pluralizar de novo, quebrando a inferência
  # de tabela (`registro_mensal_frequencias`) do model
  # `RegistroMensalFrequencia` (Sprint 17, task 17.1, 2026-09-03).
  inflect.irregular "frequencia", "frequencias"
end
