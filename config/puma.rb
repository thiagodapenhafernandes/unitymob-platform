require 'dotenv/load'

max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

worker_timeout 3600 if ENV.fetch("RAILS_ENV", "development") == "development"

environment ENV.fetch("RAILS_ENV", "development")

if ENV.fetch("RAILS_ENV", "development") == "production"
  directory ENV.fetch("PUMA_DIRECTORY", Dir.pwd)

  worker_count = ENV.fetch("WEB_CONCURRENCY", 0).to_i

  if worker_count > 1
    workers worker_count
    preload_app!

    on_worker_boot do
      ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
    end
  end

  # Produção escuta SOMENTE atrás do nginx. `port` e `bind` ACUMULAM listeners
  # no Puma — chamar `port` aqui abriria também 0.0.0.0:3000 público,
  # bypassando SSL/buffering do nginx.
  bind "tcp://127.0.0.1:9292"

  # pidfile "tmp/pids/puma.pid"
  # state_path "tmp/pids/puma.state"
else
  # Dev/test: porta local de sempre (PORT ou 3000).
  port ENV.fetch("PORT", 3000)
end

plugin :tmp_restart
