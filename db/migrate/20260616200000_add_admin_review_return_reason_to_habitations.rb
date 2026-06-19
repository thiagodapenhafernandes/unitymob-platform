class AddAdminReviewReturnReasonToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :admin_review_return_reason, :text
  end
end
