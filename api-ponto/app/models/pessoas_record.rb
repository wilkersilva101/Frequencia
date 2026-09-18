# Base para models que leem diretamente do banco do Pessoas (Postgres),
# substituindo as chamadas via Sticapi (gem `sticapi_client`/HTTP).
#
# Conexão configurada em `config/database.yml` (`pessoas:`), autenticada com
# o usuário `app.frequencia`, que só tem GRANT de SELECT no banco do Pessoas
# (sem INSERT/UPDATE/DELETE — confirmado no Postgres, não só documentado
# aqui). `readonly!` reforça essa restrição também do lado do Rails: qualquer
# tentativa de `save`/`update`/`destroy` num model que herde daqui levanta
# `ActiveRecord::ReadOnlyRecord` antes mesmo de chegar no banco.
class PessoasRecord < ApplicationRecord
  self.abstract_class = true

  connects_to database: { writing: :pessoas, reading: :pessoas }

  def readonly?
    true
  end
end
