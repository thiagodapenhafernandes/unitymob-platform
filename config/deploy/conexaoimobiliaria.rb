# frozen_string_literal: true

set :stage, "conexaoimobiliaria"
set :application_name, "conexao_imobiliaria"
set :domain, "157.245.253.175"
set :user, "bc.imobiliariaconexao.com.br"
set :deploy_to, "/home/bc.imobiliariaconexao.com.br/deploy"

set :puma_service, "puma_conexao_imobiliaria_production"
set :solid_queue_service, "solid_queue_conexao_imobiliaria_production"
