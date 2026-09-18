class SeedEstacaoPontoLegado < ActiveRecord::Migration[8.0]
  # Migração de dados (não de schema): antes da Sprint 1 (Task 1.4), a
  # validação de `codAtivacao` nos controllers `presenca/*` usava uma
  # whitelist hardcoded que sempre aceitava "poc-ativacao-001". Agora a
  # validação depende de existir um registro real em `estacoes_ponto`
  # (ver `EstacaoPonto.codigo_ativacao_valido?`). Sem este dado, qualquer
  # EstaçãoPonto física já configurada em produção com esse código passa a
  # falhar autenticação silenciosamente. Roda como migração (não como seed)
  # para garantir execução automática no `db:migrate` do deploy.
  def up
    EstacaoPonto.find_or_create_by!(cod_ativacao: "poc-ativacao-001") do |estacao|
      estacao.descricao = "Estação PoC (migração automática)"
    end
  end

  def down
    EstacaoPonto.find_by(cod_ativacao: "poc-ativacao-001")&.destroy
  end
end
