class AddArchiveFieldsToLeads < ActiveRecord::Migration[7.1]
  def change
    add_reference :leads, :archive_reason, foreign_key: { to_table: :attribute_options, on_delete: :nullify }
    add_column :leads, :archive_note, :text
    add_column :leads, :archived_at, :datetime
    add_reference :leads, :archived_by_admin_user, foreign_key: { to_table: :admin_users }
  end
end
