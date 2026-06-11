# Plano: Novo Projeto Rails - Salute Imóveis V3

## Estrutura do Novo Projeto

### Passo 1: Criar Novo Projeto Rails

```bash
cd /Users/thiagofernandes/workspaces
rails new salute-imoveis-v3 \
  --database=postgresql \
  --skip-test \
  --css=bootstrap \
  --javascript=importmap \
  --skip-jbuilder
```

### Passo 2: Gems Essenciais

**Gemfile otimizado:**

```ruby
source "https://rubygems.org"
ruby "3.2.3"

# Core Rails
gem "rails", "~> 7.1.2"
gem "pg", "~> 1.5"
gem "puma", "~> 6.4"
gem "puma-daemon", require: false

# Assets & Frontend
gem "sprockets-rails"
gem "importmap-rails"
gem "stimulus-rails"
gem "turbo-rails"
gem "sassc-rails"
gem "terser"
gem "image_processing", "~> 1.12"
gem "bootstrap", "~> 5.3"

# Environment & Configuration
gem "dotenv-rails"
gem "meta-tags"

# Database & Background Jobs
gem "redis", "~> 5.0"
gem "solid_queue"
gem "mission_control-jobs"

# Pagination
gem "will_paginate", "~> 4.0"
gem "will_paginate-bootstrap-style"

# API & External Services
gem "rest-client"
gem "httparty"

# Performance & Caching
gem "rack-cors"
gem "rack-attack"
gem "redis-rack-cache"
gem "dalli" # Memcached client

# SEO & Images
gem "sitemap_generator"
gem "friendly_id"
gem "mini_magick"
gem "carrierwave", "~> 3.0"
gem "fog-aws"

# Authentication & Authorization (se necessário)
gem "bcrypt", "~> 3.1.7"

# Utilities
gem "brazilian-rails"
gem "device_detector"

group :development, :test do
  gem "debug"
  gem "pry"
  gem "pry-rails"
  gem "bullet" # N+1 queries detection
end

group :development do
  gem "web-console"
  gem "mina"
  gem "mina-puma", require: false
  gem "annotate" # Schema annotations
end

group :production do
  gem "lograge" # Better logging
  gem "exception_notification"
end
```

### Passo 3: Estrutura de Diretórios Otimizada

```
app/
├── models/
│   ├── concerns/
│   │   ├── habitation/
│   │   │   ├── price_formatting.rb
│   │   │   ├── search_scopes.rb
│   │   │   ├── cacheable_methods.rb
│   │   │   └── seo_helpers.rb
│   ├── habitation.rb
│
├── controllers/
│   ├── concerns/
│   │   ├── cacheable.rb
│   │   └── seo_meta.rb
│   ├── habitations_controller.rb
│   ├── pages_controller.rb
│   └── home_controller.rb
│
├── services/
│   ├── cache/
│   │   └── manager_service.rb
│   └── seo/
│       ├── meta_tags_service.rb
│       └── structured_data_service.rb
│
├── jobs/
│   └── cache_warm_job.rb
│
├── queries/
│   └── habitation_query.rb
│
└── helpers/
    ├── application_helper.rb
    ├── seo_helper.rb
    ├── image_optimization_helper.rb
    └── structured_data_helper.rb
```

### Passo 4: Configurações Essenciais

#### 4.1 Database Configuration

**config/database.yml:**
```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000
  prepared_statements: true

development:
  <<: *default
  database: salute_imoveis_development
  username: <%= ENV.fetch("DB_USERNAME", "postgres") %>
  password: <%= ENV.fetch("DB_PASSWORD", "") %>
  host: <%= ENV.fetch("DB_HOST", "localhost") %>

test:
  <<: *default
  database: salute_imoveis_test

production:
  <<: *default
  database: <%= ENV.fetch("DB_NAME") %>
  username: <%= ENV.fetch("DB_USERNAME") %>
  password: <%= ENV.fetch("DB_PASSWORD") %>
  host: <%= ENV.fetch("DB_HOST") %>
  port: <%= ENV.fetch("DB_PORT", 5432) %>
```

#### 4.2 Environment Variables

**.env.example:**
```env
# Rails
RAILS_ENV=development
RAILS_MAX_THREADS=5
SECRET_KEY_BASE=your_secret_key_here

# Database
DB_NAME=salute_imoveis_production
DB_USERNAME=saluteimoveis
DB_PASSWORD=your_password_here
DB_HOST=localhost
DB_PORT=5432

# Redis
REDIS_URL=redis://localhost:6379/0
REDIS_CACHE_URL=redis://localhost:6379/1

# Vista Soft API
VISTA_KEY=ea83a702a7669520304be011258289fd
VISTA_HOST=http://saluteim20174-rest.vistahost.com.br

# CDN & Assets (Cloudflare/S3)
CDN_URL=
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=us-east-1
AWS_BUCKET=

# Application
APP_DOMAIN=saluteimoveis.com
APP_HOST=https://saluteimoveis.com

# Performance
CACHE_EXPIRATION=3600
PAGE_CACHE_ENABLED=true

# Monitoring (opcional)
SENTRY_DSN=
NEW_RELIC_LICENSE_KEY=
```

#### 4.3 Redis Configuration

**config/initializers/redis.rb:**
```ruby
REDIS_CONFIG = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
  driver: :hiredis,
  reconnect_attempts: 3
}

$redis = ConnectionPool::Wrapper.new(size: 5, timeout: 3) do
  Redis.new(REDIS_CONFIG)
end
```

**config/initializers/cache.rb:**
```ruby
Rails.application.configure do
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("REDIS_CACHE_URL", "redis://localhost:6379/1"),
    expires_in: 1.hour,
    namespace: "salute_cache",
    reconnect_attempts: 3,
    error_handler: -> (method:, returning:, exception:) {
      Rails.logger.error("Redis cache error: #{exception.class} - #{exception.message}")
    }
  }
end
```

#### 4.4 Puma Configuration

**config/puma.rb:**
```ruby
require 'dotenv/load'
require 'puma/daemon'

max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

worker_timeout 3600 if ENV.fetch("RAILS_ENV", "development") == "development"

port ENV.fetch("PORT", 3000)

environment ENV.fetch("RAILS_ENV", "development")

if ENV.fetch("RAILS_ENV") == "production"
  workers ENV.fetch("WEB_CONCURRENCY", 3)
  preload_app!
  
  bind "tcp://127.0.0.1:9292"
  daemonize true
  
  pidfile "tmp/pids/puma.pid"
  state_path "tmp/pids/puma.state"
  
  on_worker_boot do
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
  end
end

plugin :tmp_restart
```

#### 4.5 Deploy Configuration (Mina)

**config/deploy.rb:**
```ruby
require 'mina/bundler'
require 'mina/rails'
require 'mina/git'
require 'mina/rvm'
require 'mina/puma'

set :application_name, 'salute-v3'
set :domain, 'saluteimoveis.com'
set :deploy_to, '/home/saluteimoveis.com/deploy-v3'
set :repository, 'git@bitbucket.org:thiago_pfernandes/salute-imoveis-v3.git'
set :branch, 'main'
set :user, 'saluteimoveis.com'
set :rails_env, 'production'
set :keep_releases, 5

set :shared_files, fetch(:shared_files, []).push(
  'config/database.yml',
  'config/master.key',
  '.env'
)

set :shared_dirs, fetch(:shared_dirs, []).push(
  'log',
  'tmp/pids',
  'tmp/cache',
  'tmp/sockets',
  'public/uploads',
  'public/system',
  'storage',
  'vendor/bundle'
)

task :remote_environment do
  invoke :'rvm:use', 'ruby-3.2.3@salute-v3'
end

task :setup do
  command %[mkdir -p "#{fetch(:shared_path)}/log"]
  command %[mkdir -p "#{fetch(:shared_path)}/config"]
  command %[mkdir -p "#{fetch(:shared_path)}/tmp/pids"]
  command %[mkdir -p "#{fetch(:shared_path)}/tmp/cache"]
  command %[mkdir -p "#{fetch(:shared_path)}/tmp/sockets"]
  command %[touch "#{fetch(:shared_path)}/config/database.yml"]
  command %[touch "#{fetch(:shared_path)}/.env"]
  
  comment "Configurar database.yml e .env manualmente"
end

desc "Deploy"
task :deploy do
  deploy do
    invoke :'git:clone'
    invoke :'deploy:link_shared_paths'
    invoke :'bundle:install'
    invoke :'rails:db_migrate'
    invoke :'rails:assets_precompile'
    invoke :'deploy:cleanup'
    
    on :launch do
      invoke :'puma:phased_restart'
    end
  end
end
```

### Passo 5: Modelo Habitation Otimizado

**app/models/habitation.rb** (versão enxuta com concerns):

```ruby
class Habitation < ApplicationRecord
  # Concerns organizados
  include Habitation::PriceFormatting
  include Habitation::SearchScopes
  include Habitation::CacheableMethods
  include Habitation::SeoHelpers
  
  # Associations
  has_many :units, 
    class_name: 'Habitation',
    primary_key: 'codigo',
    foreign_key: 'codigo_empreendimento'
  
  # Validations
  validates :codigo, presence: true, uniqueness: true
  validates :categoria, presence: true
  validates :status, presence: true
  
  # FriendlyId for SEO URLs
  extend FriendlyId
  friendly_id :slug_candidates, use: [:slugged, :finders]
  
  def slug_candidates
    [
      [:categoria, :cidade, :bairro, :codigo],
      [:categoria, :cidade, :codigo]
    ]
  end
  
  # Callbacks
  after_update :clear_cache
  
  private
  
  def clear_cache
    Rails.cache.delete(["habitation", id])
  end
end
```

**app/models/concerns/habitation/price_formatting.rb:**
```ruby
module Habitation::PriceFormatting
  extend ActiveSupport::Concern
  
  MONEY_FIELDS = %w[
    valor_venda
    valor_locacao
    valor_condominio
    valor_iptu
  ].freeze
  
  included do
    before_save :format_money_fields
  end
  
  def valor_venda_money
    Money.new(valor_venda_cents || 0, "BRL")
  end
  
  # ... outros métodos de formatação
  
  private
  
  def format_money_fields
    MONEY_FIELDS.each do |field|
      cents_field = "#{field}_cents"
      next unless respond_to?(cents_field)
      
      value = send(field)
      next if value.blank?
      
      send("#{cents_field}=", (value.to_f * 100).to_i)
    end
  end
end
```

### Passo 6: Vista Soft Integration

Importacao feita via Thor, seguindo o fluxo legado do v2:

```bash
RAILS_ENV=production bundle exec thor builder_fields --force
RAILS_ENV=production bundle exec rake 'vista:progress[UUID]'
```

### Passo 7: Performance Optimizations

**config/initializers/rack_attack.rb:**
```ruby
class Rack::Attack
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip
  end
  
  throttle('api/ip', limit: 100, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/api/')
  end
end
```

**config/initializers/compression.rb:**
```ruby
Rails.application.config.middleware.insert_before(
  ActionDispatch::Static,
  Rack::Deflater
)
```

### Passo 8: SEO Helpers

**app/helpers/seo_helper.rb:**
```ruby
module SeoHelper
  def page_meta_tags
    set_meta_tags(
      site: 'Salute Imóveis',
      title: @page_title,
      description: @page_description,
      keywords: @page_keywords,
      og: {
        title: @page_title,
        description: @page_description,
        type: 'website',
        url: request.original_url,
        image: @page_image || asset_url('logo.png')
      },
      twitter: {
        card: 'summary_large_image',
        title: @page_title,
        description: @page_description,
        image: @page_image
      }
    )
  end
end
```

### Passo 9: Database Migrations

**db/migrate/XXXXXX_create_habitations.rb:**
```ruby
class CreateHabitations < ActiveRecord::Migration[7.1]
  def change
    create_table :habitations do |t|
      # Identificação
      t.string :codigo, null: false, index: { unique: true }
      t.string :slug, index: { unique: true }
      
      # Básico
      t.string :categoria
      t.string :status
      t.string :situacao
      
      # Endereço
      t.string :tipo_endereco
      t.string :endereco
      t.string :numero
      t.string :bairro
      t.string :cidade
      t.string :uf
      t.string :cep
      t.decimal :latitude, precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7
      
      # Características
      t.integer :dormitorios_qtd
      t.integer :suites_qtd
      t.integer :banheiros_qtd
      t.integer :vagas_qtd
      t.decimal :area_privativa_m2
      t.decimal :area_total_m2
      
      # Preços (em centavos)
      t.bigint :valor_venda_cents
      t.bigint :valor_locacao_cents
      t.bigint :valor_condominio_cents
      t.bigint :valor_iptu_cents
      
      # JSONB Fields
      t.jsonb :caracteristicas, default: {}
      t.jsonb :infra_estrutura, default: {}
      t.jsonb :destaque_localizacao, default: {}
      t.jsonb :pictures, default: []
      
      # SEO
      t.text :descricao_web
      t.string :titulo_anuncio
      
      # Flags
      t.boolean :exibir_no_site_flag, default: false
      t.boolean :destaque_web_flag, default: false
      
      t.timestamps
      t.datetime :data_atualizacao_crm
    end
    
    # Índices para performance
    add_index :habitations, [:status, :categoria]
    add_index :habitations, [:cidade, :bairro]
    add_index :habitations, :valor_venda_cents
    add_index :habitations, :caracteristicas, using: :gin
    add_index :habitations, :infra_estrutura, using: :gin
    add_index :habitations, :exibir_no_site_flag
  end
end
```

### Passo 10: Routes Otimizadas

**config/routes.rb:**
```ruby
Rails.application.routes.draw do
  root 'home#index'
  
  # Habitations
  resources :habitations, only: [:index, :show]
  
  # SEO-friendly routes
  get '/venda/*path', to: 'habitations#index', as: :venda
  get '/aluguel/*path', to: 'habitations#index', as: :aluguel
  get '/imovel/:id', to: 'habitations#show', as: :property
  
  # API endpoints
  namespace :api do
    get 'search', to: 'search#index'
    get 'autocomplete', to: 'search#autocomplete'
  end
  
  # Sitemap
  get '/sitemap.xml', to: 'sitemap#index', defaults: { format: 'xml' }
  
  # Health check
  get '/health', to: 'health#index'
  
  # Mission Control for Jobs
  mount MissionControl::Jobs::Engine => "/jobs"
end
```

## Próximos Passos

1. **Criar o projeto**: `rails new` com configurações
2. **Configurar gems**: Instalar e configurar todas as gems
3. **Setup database**: Criar migrations e seed data
4. **Implementar models**: Habitation com concerns
5. **Vista integration**: Services e jobs
6. **Frontend**: Views otimizadas com lazy loading
7. **Deploy**: Configurar Mina e fazer primeiro deploy
8. **Testing**: Performance e SEO validation

## Comandos de Setup

```bash
# 1. Criar projeto
rails new salute-imoveis-v3 --database=postgresql --skip-test

# 2. Entrar no diretório
cd salute-imoveis-v3

# 3. Configurar .env
cp .env.example .env

# 4. Instalar gems
bundle install

# 5. Setup database
rails db:create db:migrate

# 6. Iniciar servidor
rails server

# 7. Deploy
mina setup
mina deploy
```
