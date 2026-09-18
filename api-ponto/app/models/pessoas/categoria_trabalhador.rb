# Tabela `categorias_trabalhador` — fonte real do filtro de Categoria em
# `admin/frequentadores` (task 10.11). Antes disso, o filtro ficava
# `disabled: true` porque `FrequentadorCache` nunca guardou essa informação
# (o campo `categoria_trabalhador_ativa` da Sticapi nunca foi mapeado) —
# agora que a leitura é direta no Postgres do Pessoas, a categoria vem via
# `Vinculo -> ConfiguracaoCadastro -> TipoVinculo -> CategoriaTrabalhador`.
module Pessoas
  class CategoriaTrabalhador < PessoasRecord
    self.table_name = "categorias_trabalhador"

    has_many :tipos_vinculo, class_name: "Pessoas::TipoVinculo", inverse_of: :categoria_trabalhador

    # A tabela `categorias_trabalhador` inteira é a taxonomia genérica do
    # eSocial (45 categorias — a maioria irrelevante aqui, ex: "Trabalhador
    # rural", "Cooperado"). Pro filtro da tela, só as que aparecem de fato
    # entre vínculos ativos reais (5 hoje, confirmado 2026-09-02). Junção
    # por nome de tabela (não por associação Rails) porque os models enxutos
    # deste namespace não replicam todas as associações intermediárias do
    # pessoas2 (ex: `TipoVinculo has_many :configuracoes_cadastro` não
    # existe aqui, só o `belongs_to` inverso em `ConfiguracaoCadastro`).
    scope :em_uso, -> {
      where(
        id: Pessoas::TipoVinculo
          .joins("INNER JOIN configuracoes_cadastro ON configuracoes_cadastro.tipo_vinculo_id = tipos_vinculo.id")
          .joins("INNER JOIN vinculos ON vinculos.configuracao_cadastro_id = configuracoes_cadastro.id")
          .joins("INNER JOIN vinculos_estados ON vinculos_estados.id = vinculos.vinculo_estado_id")
          .where(vinculos_estados: { nome: "em_exercicio" })
          .where("vinculos.fim IS NULL OR vinculos.fim >= ?", Date.current)
          .select(:categoria_trabalhador_id)
      ).order(:descricao)
    }
  end
end
