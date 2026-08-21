# frozen_string_literal: true

ENV["RACK_ENV"] = "test"
ENV["META_WEBHOOK_VERIFY_TOKEN"] ||= "verify-token"
ENV["META_APP_SECRET"] ||= "app-secret"
ENV["INTERNAL_API_TOKEN"] ||= "internal-token"

require "rack/test"
require "webmock/rspec"
require_relative "../config/environment"

connection = ActiveRecord::Base.connection
connection.drop_table(:webhook_events, if_exists: true)
connection.drop_table(:webhook_routes, if_exists: true)

ActiveRecord::Schema.define do
  suppress_messages do
    create_table :webhook_routes do |t|
      t.string :provider, null: false, default: "whatsapp"
      t.string :client_key, null: false
      t.string :tenant_name
      t.string :waba_id
      t.string :phone_number_id
      t.string :page_id
      t.string :form_id
      t.string :target_url, null: false
      t.string :forwarding_secret, null: false
      t.boolean :active, null: false, default: true
      t.datetime :last_seen_at
      t.text :last_error
      t.timestamps
    end

    create_table :webhook_events do |t|
      t.references :webhook_route, foreign_key: true
      t.string :provider, null: false, default: "whatsapp"
      t.string :external_id
      t.string :event_type, null: false
      t.string :waba_id
      t.string :phone_number_id
      t.string :page_id
      t.string :form_id
      t.jsonb :payload, null: false, default: {}
      t.text :raw_body
      t.string :status, null: false, default: "received"
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.datetime :received_at, null: false
      t.datetime :last_attempted_at
      t.datetime :next_retry_at
      t.datetime :forwarded_at
      t.timestamps
    end
  end
end

RSpec.configure do |config|
  config.include Rack::Test::Methods

  config.before do
    WebhookEvent.delete_all
    WebhookRoute.delete_all
  end
end
