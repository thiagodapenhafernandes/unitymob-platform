class AddActivityReminderSettings < ActiveRecord::Migration[7.1]
  def change
    { reminder_first_minutes: 60, reminder_second_minutes: 30, reminder_third_minutes: 15,
      reminder_overdue_minutes: 120, reminder_retry_minutes: 30 }.each do |name, default|
      add_column :lead_settings, name, :integer, null: false, default: default
      add_check_constraint :lead_settings, "#{name} BETWEEN 1 AND 10080", name: "lead_settings_#{name}_range"
    end
    add_column :lead_settings, :reminder_due_enabled, :boolean, null: false, default: true
    add_column :lead_settings, :reminder_start_time, :string, null: false, default: "08:00"
    add_column :lead_settings, :reminder_end_time, :string, null: false, default: "18:00"
    add_check_constraint :lead_settings,
      "reminder_first_minutes > reminder_second_minutes AND reminder_second_minutes > reminder_third_minutes",
      name: "lead_settings_reminder_order"
    add_check_constraint :lead_settings,
      "reminder_start_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' AND reminder_end_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' AND reminder_start_time < reminder_end_time",
      name: "lead_settings_reminder_hours"
    add_column :tasks, :reminder_state, :jsonb, null: false, default: {}
    add_column :appointments, :reminder_state, :jsonb, null: false, default: {}
  end
end
