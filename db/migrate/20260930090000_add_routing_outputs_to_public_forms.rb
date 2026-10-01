class AddRoutingOutputsToPublicForms < ActiveRecord::Migration[7.1]
  def change
    add_column :public_forms, :webhook_url, :string
    add_reference :public_forms, :distribution_rule, foreign_key: true, index: true
    add_reference :public_form_submissions, :lead, foreign_key: true, index: { unique: true }
  end
end
