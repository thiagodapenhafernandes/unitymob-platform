module Vista
  # Dispara Vista::ImportAgentsService em background (queue :default) para não
  # bloquear o request HTTP — o serviço pagina a API e baixa avatares, podendo
  # levar minutos.
  class ImportAgentsJob < ApplicationJob
    queue_as :default

    def perform
      Vista::ImportAgentsService.call
    end
  end
end
