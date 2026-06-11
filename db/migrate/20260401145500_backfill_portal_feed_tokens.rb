class BackfillPortalFeedTokens < ActiveRecord::Migration[7.1]
  class PortalIntegrationRecord < ApplicationRecord
    self.table_name = "portal_integrations"
  end

  def up
    say_with_time "Backfilling portal feed tokens" do
      PortalIntegrationRecord.where("feed_token IS NULL OR btrim(feed_token) = ''").find_each do |row|
        row.update_columns(feed_token: generate_unique_token)
      end
    end

    add_index :portal_integrations, :feed_token, unique: true unless index_exists?(:portal_integrations, :feed_token)
    change_column_null :portal_integrations, :feed_token, false
  end

  def down
    change_column_null :portal_integrations, :feed_token, true
    remove_index :portal_integrations, :feed_token if index_exists?(:portal_integrations, :feed_token)
  end

  private

  def generate_unique_token
    loop do
      candidate = SecureRandom.hex(24)
      break candidate unless PortalIntegrationRecord.exists?(feed_token: candidate)
    end
  end
end
