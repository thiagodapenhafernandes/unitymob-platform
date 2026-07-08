# frozen_string_literal: true

set :stages, %w[saluteimoveis]
set :stages_dir, "config/deploy"

require "mina/multistage"
require "mina/rails"
require "mina/git"
require "mina/rvm"

set :repository, "git@github.com:thiagodapenhafernandes/unitymob-platform.git"
set :branch, "master"
set :rails_env, "production"
set :keep_releases, 5
set :forward_agent, true

set :shared_dirs, fetch(:shared_dirs, []) | [
  "public/uploads",
  "storage",
  "public/assets",
  "tmp/pids",
  "tmp/sockets",
  "log"
]
set :shared_files, fetch(:shared_files, []) | [
  "config/database.yml",
  "config/master.key",
  ".env"
]

set :rvm_use_path, "/usr/local/rvm/scripts/rvm"
set :ruby_version, "ruby-3.2.3"
set :ruby_gemset, "default"

task :remote_environment do
  command %{
    if [ -s "/usr/local/rvm/scripts/rvm" ]; then
      source "/usr/local/rvm/scripts/rvm"
    elif [ -s "$HOME/.rvm/scripts/rvm" ]; then
      source "$HOME/.rvm/scripts/rvm"
    elif [ -s "/etc/profile.d/rvm.sh" ]; then
      source "/etc/profile.d/rvm.sh"
    fi

    if [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi

    if [ -f "#{fetch(:deploy_to)}/shared/.env" ]; then
      set -a
      source "#{fetch(:deploy_to)}/shared/.env"
      set +a
    fi

    export rvm_silence_path_mismatch_check_flag=1
  }

  invoke :"rvm:use", "#{fetch(:ruby_version)}@#{fetch(:ruby_gemset)}"
end

namespace :bundle do
  Rake::Task["bundle:install"].clear if Rake::Task.task_defined?("bundle:install")

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

namespace :deploy do
  desc "Verifica se o manifest de assets aponta apenas para arquivos existentes."
  task :verify_assets do
    command %{
      echo "-----> Verifying compiled assets"
      ruby -rjson -e '
        manifest = Dir["public/assets/.sprockets-manifest-*.json"].max_by { |path| File.mtime(path) }
        abort("asset manifest ausente em public/assets") unless manifest

        data = JSON.parse(File.read(manifest))
        missing = data.fetch("assets", {}).values
          .select { |path| path.match?(/\\.(css|js)\\z/) }
          .reject { |path| File.exist?(File.join("public/assets", path)) }

        if missing.any?
          warn "Assets ausentes no manifest " + manifest + ":"
          missing.each { |path| warn "  - " + path }
          abort "deploy abortado: manifest aponta para assets inexistentes"
        end
      '
    }
  end

  desc "Recompila assets no release atual para corrigir manifest/assets desalinhados."
  task rebuild_current_assets: :remote_environment do
    command %{
      echo "-----> Rebuilding current release assets"
      cd "#{fetch(:deploy_to)}/current"
      bundle exec rails tmp:cache:clear
      rm -f public/assets/.sprockets-manifest-*.json
      RAILS_ENV=#{fetch(:rails_env)} bundle exec rails assets:precompile
      ruby -rjson -e '
        manifest = Dir["public/assets/.sprockets-manifest-*.json"].max_by { |path| File.mtime(path) }
        abort("asset manifest ausente em public/assets") unless manifest

        data = JSON.parse(File.read(manifest))
        missing = data.fetch("assets", {}).values
          .select { |path| path.match?(/\\.(css|js)\\z/) }
          .reject { |path| File.exist?(File.join("public/assets", path)) }

        abort("assets ausentes: " + missing.join(", ")) if missing.any?
      '
      sudo systemctl restart #{fetch(:puma_service)}
    }
  end
end

task :setup do
  command %{rvm install #{fetch(:ruby_version)}}
  command %{gem install bundler}
end

desc "Deploys the current version to the selected stage."
task :deploy do
  if (all_index = ARGV.index("all")) && (deploy_index = ARGV.index("deploy")) && deploy_index > all_index
    next
  end

  deploy do
    invoke :"git:clone"
    invoke :"deploy:link_shared_paths"
    invoke :"bundle:install"
    command %{echo "-----> Migrating database (PG_STATEMENT_TIMEOUT=10min)"}
    command %{RAILS_ENV=#{fetch(:rails_env)} PG_STATEMENT_TIMEOUT=10min bundle exec rails db:migrate}
    command %{echo "-----> Clearing Rails tmp cache before assets precompile"}
    command %{bundle exec rails tmp:cache:clear}
    invoke :"rails:assets_precompile"
    invoke :"deploy:verify_assets"
    invoke :"deploy:cleanup"

    on :launch do
      invoke :restart
    end
  end
end

if (all_index = ARGV.index("all"))
  ARGV.drop(all_index + 1).each do |task_name|
    Rake::Task[task_name].clear if Rake::Task.task_defined?(task_name)
  end
end

desc "Deploys every configured stage in isolated Mina processes."
task :all do
  command = ARGV.drop_while { |arg| arg != "all" }.drop(1)
  command = ["deploy"] if command.empty?
  simulate = Rake.application.options.dryrun || ARGV.include?("-s") || ARGV.include?("--simulate")
  fetch(:stages).each do |stage|
    stage_command = "bundle exec mina #{stage} #{command.join(' ')}"
    if simulate
      puts stage_command
    else
      sh stage_command
    end
  end
  exit(true)
end

desc "Reinicia o Puma e o Solid Queue"
task restart: :remote_environment do
  comment "Restarting Puma..."
  command %(sudo systemctl restart #{fetch(:puma_service)})
  comment "Restarting Solid Queue..."
  command %(sudo systemctl restart #{fetch(:solid_queue_service)})
end

desc "Mostra os logs da aplicação (Puma) em tempo real"
task :logs do
  command "journalctl -u #{fetch(:puma_service)} -f -n 100"
end
