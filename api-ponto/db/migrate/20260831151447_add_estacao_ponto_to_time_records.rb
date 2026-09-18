class AddEstacaoPontoToTimeRecords < ActiveRecord::Migration[8.0]
  # Sprint 13 (task 13.1): a grid de admin/frequencia precisa exibir de qual
  # estação veio cada batida, mas SincronizarRegistrosPontoController já
  # validava a EstacaoPonto e descartava o vínculo. Nullable porque: (a)
  # registros já existentes não têm essa informação retroativamente, e (b)
  # o sentinela `CODIGO_SISTEMA_OPERACIONAL_NAO_SUPORTADO` (ver
  # EstacaoPonto#codigo_ativacao_valido?) é válido para autenticar mas não
  # corresponde a uma linha real de EstacaoPonto.
  def change
    # `to_table: :estacoes_ponto` explícito: o model EstacaoPonto usa
    # `self.table_name = "estacoes_ponto"` (irregular, não pluralização
    # padrão de "estacao_ponto"), então o `foreign_key: true` sozinho
    # tentaria referenciar uma tabela "estacao_pontos" inexistente.
    add_reference :time_records, :estacao_ponto, null: true, foreign_key: { to_table: :estacoes_ponto }
  end
end
