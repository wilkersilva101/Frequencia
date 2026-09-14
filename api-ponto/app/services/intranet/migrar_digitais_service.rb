# Wrapper de compatibilidade para a migração inicial (backfill) de digitais
# da Intranet para a api-ponto.
#
# A lógica completa (atualizar + sem-alteração + ignorado) vive em
# `Intranet::SyncDigitaisService`. Esta classe apenas delega, mantendo a
# assinatura e o mesmo arquivo de log (`log/digitais_migracao.log`) para
# não quebrar chamadas existentes ou seeds de migração inicial.
#
# Uso:
#   Intranet::MigrarDigitaisService.call                       # migra/sincroniza todos
#   Intranet::MigrarDigitaisService.call(dry_run: true)        # só simula/relatório
#   Intranet::MigrarDigitaisService.call(only_cpfs: ['1','2']) # sincroniza somente CPFs
class Intranet::MigrarDigitaisService
  def self.call(dry_run: false, only_cpfs: nil)
    Intranet::SyncDigitaisService.call(dry_run: dry_run, only_cpfs: only_cpfs)
  end
end
