module Vista
  class BackfillBrokersJob < ApplicationJob
    queue_as :default

    def perform
      Vista::BackfillBrokersService.call
    end
  end
end
