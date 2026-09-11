# frozen_string_literal: true

# Requer a integração do exception_notification com o Sidekiq (captura de
# exceções que ocorrem dentro de jobs). Descomentado porque o projeto usa
# jobs (Solid Queue) e queremos registrar erros de jobs também.
require "exception_notification/sidekiq"

ExceptionTrack.configure do
  # Ambientes que armazenam o log de exceção no banco.
  # default: [:development, :production]
  # `:test` fica de fora por padrão para não poluir a suíte; a captura em
  # testes é feita de forma isolada no teste de integração correspondente.
  self.environments = %i[development production]
end

# Configura o notifier :db, que grava a exceção na tabela `exception_tracks`
# via `ExceptionTrack::Log`. O middleware `ExceptionNotification::Rack` é
# inserido pela Engine (`lib/exception_notification/rails.rb`) e captura
# exceções no ciclo de request.
ExceptionNotification.configure do |config|
  config.add_notifier :db, {}
end
