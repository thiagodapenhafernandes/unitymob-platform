namespace :vista do
  desc "Importa corretores da API Vista (endpoints: /usuarios)"
  task import_agents: :environment do
    Vista::ImportAgentsService.call
  end
end
