class BarDuplicidadeDoVinculoGestorIndividual < ActiveRecord::Migration[8.0]
  # Bug 3 (🟡) do Bug Finder da 29.2 — decisão do dev em 2026-09-29.
  #
  # O UNIQUE de `id_legado` admite múltiplos NULL, então vínculos LOCAIS (sem
  # `id_legado`) podiam duplicar o mesmo par gestor→gerido livremente. Como
  # `GestorIndividual#gerenciados` não filtra por `ativos`, a duplicata
  # inflaria a contagem "Gerenciados" da tela e faria a cascata da 29.4/29.6
  # listar o mesmo gerido mais de uma vez.
  #
  # Índice UNIQUE **parcial** (`where: "ativo"`): no máximo UM vínculo ATIVO por
  # par, preservando o histórico — desativar e re-vincular o mesmo par continua
  # possível, e as linhas inativas antigas permanecem para auditoria (o que não
  # aconteceria com um UNIQUE simples do par, que bloquearia o re-vínculo para
  # sempre). É o primeiro índice parcial do projeto — não havia nenhum até aqui.
  #
  # Há também um índice para a corrida na CRIAÇÃO do vínculo: dois inserts
  # concorrentes do mesmo par ativo colidem no banco, não só na validação Ruby.
  def change
    add_index :gestor_individual_gerenciados,
              [ :gestor_individual_id, :user_id ],
              unique: true,
              where: "ativo",
              name: "index_gestor_individual_gerenciados_on_par_ativo"
  end
end
