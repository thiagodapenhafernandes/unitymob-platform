class AddIntakeWorkflowToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :intake_origin, :string
    add_column :habitations, :intake_status, :string
    add_column :habitations, :submitted_for_review_at, :datetime
    add_reference :habitations, :admin_reviewed_by, foreign_key: { to_table: :admin_users }
    add_column :habitations, :admin_reviewed_at, :datetime
    add_column :habitations, :admin_review_notes, :text
    add_column :habitations, :broker_released_at, :datetime
    add_column :habitations, :photo_flow_choice, :string
    add_column :habitations, :photo_session_requested_at, :datetime
    add_column :habitations, :photo_session_url, :string
    add_column :habitations, :aceita_parcelamento_flag, :boolean, default: false, null: false
    add_column :habitations, :salute_rental_management_answer, :string
    add_column :habitations, :aceita_permuta_answer, :string

    add_index :habitations, :intake_origin
    add_index :habitations, :intake_status
  end
end
