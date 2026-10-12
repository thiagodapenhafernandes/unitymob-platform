class AddSubscribedEventsToWebhookSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :webhook_settings, :subscribed_events, :jsonb,
      null: false, default: %w[lead_created lead_inquiry form_submitted]
  end
end
