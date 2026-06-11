class AddAdminUserToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_reference :habitations, :admin_user, null: true, foreign_key: true
  end
end
