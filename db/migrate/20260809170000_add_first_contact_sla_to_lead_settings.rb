class AddFirstContactSlaToLeadSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :lead_settings, :first_contact_sla_hours, :integer, null: false, default: 4
  end
end
