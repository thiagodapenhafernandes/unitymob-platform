require 'mina/deploy'
require 'mina/git'
require 'mina/rvm'

set :domain, ENV.fetch('CENTRAL_HOST')
set :user, 'unitymob'
set :deploy_to, '/home/unitymob/central'
set :repository, 'git@github.com:thiagodapenhafernandes/unitymob-platform.git'
set :branch, ENV.fetch('CENTRAL_BRANCH', 'master')
set :forward_agent, true
set :keep_releases, 5
set :shared_dirs, %w[central/log central/storage central/public/assets central/tmp/pids central/tmp/sockets central/vendor/bundle]
set :shared_files, %w[central/.env]
set :rvm_use_path, '/usr/local/rvm/scripts/rvm'

task :remote_environment do
  invoke :'rvm:use', 'ruby-3.2.3@default'
end

desc 'Publica somente a central no servidor próprio'
task deploy: :remote_environment do
  deploy do
    invoke :'git:clone'
    invoke :'deploy:link_shared_paths'
    command 'cd central'
    command 'bundle config set --local deployment true'
    command 'bundle config set --local path vendor/bundle'
    command 'bundle config set --local without "development test"'
    command 'bundle install --quiet'
    command 'RAILS_ENV=production bundle exec rails db:migrate zeitwerk:check assets:precompile'
    command 'cd ..'
    invoke :'deploy:cleanup'
    on :launch do
      command 'sudo systemctl restart unitymob-central-web unitymob-central-jobs'
      command 'curl --fail --retry 10 --retry-connrefused --retry-delay 2 https://admin.unitymob.com.br/up'
    end
  end
end
