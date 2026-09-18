class AddExcluidoEVisivelToRegimes < ActiveRecord::Migration[8.0]
  def change
    # Espelha `presenca_regime.excluido`/`.visivel` do legado — controla
    # o mesmo filtro real que `RegimeDao.paginateList` aplica na tela
    # `/presenca/Regime-explore` (só mostra excluido=false, visivel=true,
    # e que não seja `anterior_id` de outro regime não-excluído).
    add_column :regimes, :excluido, :boolean, default: false, null: false
    add_column :regimes, :visivel, :boolean, default: true, null: false
  end
end
