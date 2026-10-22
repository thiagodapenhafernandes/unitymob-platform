class DeliveryDestination < ApplicationRecord
  has_many :webhook_events
end
