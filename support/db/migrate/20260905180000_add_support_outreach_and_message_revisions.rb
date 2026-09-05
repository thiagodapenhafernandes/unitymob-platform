class AddSupportOutreachAndMessageRevisions < ActiveRecord::Migration[7.1]
  def change
    add_column :support_tickets, :origin, :string, null: false, default: 'receptivo'
    add_column :support_tickets, :outreach_kind, :string
    add_column :support_tickets, :requester_email, :string
    add_index :support_tickets, [:origin, :created_at]
    add_column :support_messages, :author_staff_id, :bigint # Identidade da central, projetada também nas contas.
    add_column :support_messages, :edited_at, :datetime
    add_column :support_messages, :deleted_at, :datetime
    add_column :support_messages, :revision, :integer, null: false, default: 0
  end
end
