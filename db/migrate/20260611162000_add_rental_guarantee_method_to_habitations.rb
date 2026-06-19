class AddRentalGuaranteeMethodToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :rental_guarantee_method, :string
  end
end
