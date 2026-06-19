class AddReviewNotificationsToPropertySettings < ActiveRecord::Migration[7.1]
  def change
    add_column :property_settings, :notify_internal_review_events, :boolean, null: false, default: true
    add_column :property_settings, :notify_email_review_events, :boolean, null: false, default: false
    add_column :property_settings, :review_notification_emails, :text
  end
end
