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
gem "terser"
gem "image_processing", "~> 1.12"
gem "tailwindcss-rails", "~> 2.0"

# Environment & Configuration
gem "dotenv-rails"
gem "meta-tags"
gem "rails-i18n"

# Database & Background Jobs
gem "redis", "~> 5.0"
gem "solid_queue"
gem "mission_control-jobs"

# Pagination
gem "will_paginate", "~> 4.0"

# PDF (propostas comerciais)
gem "prawn"
gem "prawn-table"

# API & External Services
gem "rest-client"
gem "httparty"
gem "google-apis-calendar_v3", "~> 0.55"
gem "koala", "~> 3.0"
gem "omniauth-facebook"
gem "omniauth-rails_csrf_protection"

# Performance & Caching
gem "rack-cors"
gem "rack-attack"
gem "maxmind-db", "~> 1.2"
gem "web-push", "~> 3.0"
gem "dalli"

# SEO & Images
gem "sitemap_generator"
gem "friendly_id"
gem "mini_magick"
gem "carrierwave", "~> 3.0"
gem "fog-aws"
gem "aws-sdk-s3", require: false

# Authentication
gem "bcrypt", "~> 3.1.7"

# Utilities
# gem "brazilian-rails"
gem "device_detector"

# Required
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ]
  gem "pry"
  gem "pry-rails"
  gem "bullet"
  gem "rspec-rails", "~> 7.0"
  gem "factory_bot_rails"
  gem "shoulda-matchers", "~> 6.0"
  gem "faker"
end

group :development do
  gem "web-console"
  gem "mina"
  gem "mina-multistage", require: false
  gem "annotate"
end

group :production do
  gem "lograge"
end

gem "devise", "~> 4.9"

# 2FA TOTP (Google Authenticator): rotp gera/valida códigos, rqrcode desenha o QR
gem "rotp", "~> 6.3"
gem "rqrcode", "~> 2.2"

gem "dartsass-rails", "~> 0.5.1"
