# frozen_string_literal: true

set :stage, "conexaoimobiliaria"
set :application_name, "conexao_imobiliaria"
set :domain, "app.conexaobc.com"
set :user, "conexao"
set :deploy_to, "/home/conexao/deploy"

set :puma_service, "puma_conexao_imobiliaria_production"
set :solid_queue_service, "solid_queue_conexao_imobiliaria_production"
