# Upsert do espelho local (FrequentadorCache) a partir de um `Pessoas::Pessoa`
# lido diretamente do banco do Pessoas (task 8.13 — substitui o payload de
# `SticapiClient::Pessoas.get_by_cpf`). Extraído de ImportarDadosPessoaJob
# para ser reaproveitado também por ImportarServidoresUnidadeJob (Sprint
# 10B).
#
# Histórico (Sprint 10, task 10.3 / Sprint 10B, task 10B.10, formato
# confirmado via HTTP Sticapi): `lotacao_principal.unidade.descricao` dava
# o nome do órgão/unidade, e `vinculos_ativos` vinha ora como Hash único
# (pessoa com 1 vínculo ativo), ora como Array (vários vínculos) —
# inconsistência de serialização da própria API, normalizada com
# `Array.wrap`. Essa inconsistência não existe mais aqui: `Pessoas::Pessoa
# #vinculos_ativos` é sempre uma relação ActiveRecord, e `Pessoas::Vinculo
# #lotacao_principal`/`#tipo_vinculo` leem as colunas reais
# (`lotacoes.principal`, `vinculos.configuracao_cadastro_id` →
# `tipos_vinculo.nome`) — ver app/models/pessoas/*.rb.
class AtualizarFrequentadorCacheService
  def self.call(cpf:, pessoa:)
    vinculo_ativo = pessoa.vinculos_ativos.first

    FrequentadorCache.find_or_initialize_by(cpf: cpf).tap do |cache|
      cache.update!(
        pessoa_id_pessoas: pessoa.id,
        nome: pessoa.nome,
        orgao: vinculo_ativo&.lotacao_principal&.unidade&.descricao,
        vinculo: vinculo_ativo&.tipo_vinculo&.nome,
        sincronizado_em: Time.current
      )
    end
  end
end
