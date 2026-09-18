class RegimeCategoria < ApplicationRecord
  # Corresponde ao legado `presenca_regime_categoriavinculo` (join table
  # muitos-pra-muitos entre Regime e categoria de vínculo — um regime pode
  # valer para várias categorias, ex.: Servidor Efetivo + Residente).

  belongs_to :regime

  validates :categoria, presence: true, inclusion: { in: Regime::CATEGORIAS_DISPONIVEIS }
end
