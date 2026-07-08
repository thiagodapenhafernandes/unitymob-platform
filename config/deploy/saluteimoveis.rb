# frozen_string_literal: true

set :stage, "saluteimoveis"
set :application_name, "salute_imoveis_v3"
set :domain, "143.110.138.67"
set :user, "salute"
set :deploy_to, "/home/salute/deploy"

set :puma_service, "puma_salute_imoveis_v3_production"
set :solid_queue_service, "solid_queue_salute_imoveis_v3_production"
