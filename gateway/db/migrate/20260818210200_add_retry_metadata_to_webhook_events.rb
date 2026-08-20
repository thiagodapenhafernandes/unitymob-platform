# frozen_string_literal: true

class AddRetryMetadataToWebhookEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :webhook_events, :raw_body, :text
    add_column :webhook_events, :last_attempted_at, :datetime
    add_column :webhook_events, :next_retry_at, :datetime

    add_index :webhook_events, %i[status next_retry_at], name: "index_webhook_events_on_status_and_next_retry_at"
  end
end
