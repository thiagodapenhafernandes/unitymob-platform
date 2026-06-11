# frozen_string_literal: true

require 'mina/rails'
require 'mina/git'
# require 'mina/rbenv'  # for rbenv support. (https://rbenv.org)
require 'mina/rvm'    # for rvm support. (https://rvm.io)

# Basic settings:
#   domain       - The hostname to SSH to.
#   deploy_to    - Path to deploy into.
#   repository   - Git repo to clone from. (needed by mina/git)
#   branch       - Branch name to deploy. (needed by mina/git)

set :application_name, 'unitymob_crm'
set :domain, '143.110.138.67'
set :deploy_to, '/home/unitymob/deploy'
set :repository, 'https://github.com/thiagodapenhafernandes/unitymob-crm.git'
set :branch, 'master'

set :user, 'unitymob'          # Username in the server to SSH to.
# set :port, '30000'           # SSH port number.
set :forward_agent, true     # SSH forward_agent.

# Shared dirs and files will be symlinked into the app-folder by the 'deploy:link_shared_paths' step.
# Some plugins already add folders to shared_dirs like `mina/rails` add `public/assets`, `vendor/bundle` and many more
# run `mina -d` to see all folders and files already included in `shared_dirs` and `shared_files`
set :shared_dirs, fetch(:shared_dirs, []).push('public/uploads', 'storage', 'public/assets', 'tmp/pids', 'tmp/sockets', 'log')
set :shared_files, fetch(:shared_files, []).push('config/database.yml', 'config/master.key', '.env')

# This task is the environment that is loaded for all remote run commands, such as
# `mina deploy` or `mina rake`.
# Configuração explícita do RVM
set :rvm_use_path, '/usr/local/rvm/scripts/rvm'

task :remote_environment do
  # Carrega o RVM manualmente para garantir
  command %{
    if [ -s "/usr/local/rvm/scripts/rvm" ]; then
      source "/usr/local/rvm/scripts/rvm"
    elif [ -s "$HOME/.rvm/scripts/rvm" ]; then
      source "$HOME/.rvm/scripts/rvm"
    elif [ -s "/etc/profile.d/rvm.sh" ]; then
      source "/etc/profile.d/rvm.sh"
    fi
    
    # Load Homebrew
    if [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
    
    # Load .env if it exists in shared path
    if [ -f "#{fetch(:deploy_to)}/shared/.env" ]; then
      set -a
      source "#{fetch(:deploy_to)}/shared/.env"
      set +a
    fi
    # Silence RVM path mismatch warnings
    export rvm_silence_path_mismatch_check_flag=1
  }

  invoke :'rvm:use', 'ruby-3.2.3@default'
end

# Override default bundle:install to fix deprecated --deployment flag
namespace :bundle do
  desc "Install gem dependencies using Bundler."
  task :install do
    command %{
      echo "-----> Installing gem dependencies using Bundler"
      bundle config set --local deployment 'true'
      bundle config set --local path 'vendor/bundle'
      bundle config set --local without 'development test'
      bundle install --quiet
    }
  end
end

# Put any custom commands you need to run at setup
# All paths in `shared_dirs` and `shared_paths` will be created on their own.
task :setup do
  # command %{rbenv install 2.5.3 --skip-existing}
  command %{rvm install ruby-3.2.3}
  command %{gem install bundler}
end

desc 'Deploys the current version to the server.'
task :deploy do
  # uncomment this line to make sure you pushed your local branch to the remote origin
  # invoke :'git:ensure_pushed'
  deploy do
    # Put things that will set up an empty directory into a fully set-up
    # instance of your project.
    invoke :'git:clone'
    invoke :'deploy:link_shared_paths'
    invoke :'bundle:install'
    invoke :'rails:db_migrate'
    invoke :'rails:assets_precompile'
    invoke :'deploy:cleanup'

    on :launch do
      invoke :restart
    end
  end
end

desc "Reinicia o Puma e o Solid Queue"
task :restart => :remote_environment do
  comment 'Restarting Puma...'
  command %(sudo systemctl restart puma_unitymob_crm_production)
  comment 'Restarting Solid Queue...'
  command %(sudo systemctl restart solid_queue_unitymob_crm_production)
  command %(cd #{fetch(:current_path)} && bundle exec rails runner "Rails.cache.clear")
end


desc "Mostra os logs da aplicação (Puma) em tempo real"
task :logs do
  command "journalctl -u puma_unitymob_crm_production -f -n 100"
end


# For help in making your deploy script, see the Mina documentation:
#
#  - https://github.com/mina-deploy/mina/tree/master/docs
