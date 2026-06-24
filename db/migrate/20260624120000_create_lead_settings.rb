class CreateLeadSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :lead_settings do |t|
      # Fidelização: lead recorrente volta para o mesmo corretor.
      t.boolean :stickiness_enabled, default: false, null: false
      t.string  :stickiness_match,    default: "phone",          null: false # phone | phone_or_email | phone_and_email
      t.string  :stickiness_owner,    default: "attended",       null: false # attended | any_assignment
      t.string  :stickiness_fallback, default: "active_in_rule", null: false # active_in_rule | active_any
      t.integer :stickiness_window_days # nil = para sempre

      t.timestamps
    end
  end
end
