# Configuração do Sidekiq (background jobs).
#
# A api-ponto migrou de Solid Queue para Sidekiq (ver PRD-CONFIGURACOES-SISTEMA.md
# e config/schedule.yml). O agendamento recorrente é carregado pelo `sidekiq-cron`
# no boot do worker, a partir de config/schedule.yml (apenas em produção).
#
# Redis isolado: usa o DB 2 do redis local por padrão para não colidir com outros
# apps Rails locais (ex.: `pessoas` e `cpemult`) que compartilham o mesmo
# redis-server. Em produção, honra `REDIS_URL` (Redis dedicado do container
# api_ponto-redis, ver config/deploy.yml). Se `REDIS_URL` for definida, ela tem
# precedência — aqui só garantimos um DB dedicado em dev quando nada é setado.
require "sidekiq"
require "sidekiq/cron"

redis_config = { url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/2" } }

# `configure_client` roda no processo web (Puma), que enfileira os jobs via
# `perform_later`; `configure_server` roda no worker Sidekiq, que processa a
# fila e roda o `sidekiq-cron`. Ambos precisam apontar para o mesmo Redis.
Sidekiq.configure_client do |config|
  config.redis = redis_config
end

Sidekiq.configure_server do |config|
  config.redis = redis_config
  config.logger = Sidekiq::Logger.new($stdout) if Rails.env.development?
end
