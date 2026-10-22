class RemoveRedundantReceiptIndex < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    # The original 20260818210100 migration already indexes this receipt lookup.
    unless index_exists?(:webhook_events, [:provider, :external_id], name: 'index_webhook_events_on_provider_and_external_id')
      raise 'Original receipt lookup index missing; preserve the replacement'
    end
    remove_index :webhook_events, name: 'index_webhook_events_receipt_identity', algorithm: :concurrently
  end

  def down
    add_index :webhook_events, [:provider, :external_id], name: 'index_webhook_events_receipt_identity', algorithm: :concurrently
  end
end
