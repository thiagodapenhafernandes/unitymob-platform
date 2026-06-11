class CreateWebhookSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :webhook_settings do |t|
      t.string :webhook_url
      t.boolean :enabled, default: true, null: false
      t.text :description

      t.timestamps
    end
  end
end
