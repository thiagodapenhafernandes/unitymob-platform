class AddAssociationsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_reference :habitations, :constructor, null: true, foreign_key: true
    add_reference :habitations, :development, null: true, foreign_key: true
  end
end
