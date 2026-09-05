threads_count = ENV.fetch('RAILS_MAX_THREADS', 5).to_i
threads threads_count, threads_count
bind 'tcp://127.0.0.1:4020'
environment ENV.fetch('RAILS_ENV', 'production')
pidfile 'tmp/pids/puma.pid'
