class AddUniqueVerticalProfilePositionPerTenant < ActiveRecord::Migration[7.1]
  def change
    add_index :profiles,
              [:tenant_id, :position],
              unique: true,
              where: "axis = 'vertical'",
              name: :index_profiles_on_tenant_and_vertical_position
  end
end
