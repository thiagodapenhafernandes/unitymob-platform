# frozen_string_literal: true

class AddMetaLeadRoutingToWebhookRoutes < ActiveRecord::Migration[7.1]
  def change
    change_column_null :webhook_routes, :phone_number_id, true

    add_column :webhook_routes, :page_id, :string
    add_column :webhook_routes, :form_id, :string
    add_index :webhook_routes, %i[provider page_id form_id],
              unique: true,
              where: "provider = 'meta' AND form_id IS NOT NULL",
              name: "index_webhook_routes_on_provider_page_form"
    add_index :webhook_routes, %i[provider page_id],
              unique: true,
              where: "provider = 'meta' AND form_id IS NULL",
              name: "index_webhook_routes_on_provider_page"

    add_column :webhook_events, :page_id, :string
    add_column :webhook_events, :form_id, :string
    add_index :webhook_events, %i[provider page_id received_at],
              name: "index_webhook_events_on_provider_page_received"
    add_index :webhook_events, %i[provider page_id form_id received_at],
              name: "index_webhook_events_on_provider_page_form_received"
  end
end
