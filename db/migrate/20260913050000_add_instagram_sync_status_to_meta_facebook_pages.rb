class AddInstagramSyncStatusToMetaFacebookPages < ActiveRecord::Migration[7.1]
  def change
    add_column :meta_facebook_pages, :instagram_sync_error, :text
    add_column :meta_facebook_pages, :instagram_checked_at, :datetime
  end
end
