class RemoveGlobalUniqueProfileKeyIndex < ActiveRecord::Migration[7.1]
  def up
    remove_index :profiles, name: :index_profiles_on_key if index_exists?(:profiles, :key, name: :index_profiles_on_key)
  end

  def down
    add_index :profiles, :key, unique: true, where: "key IS NOT NULL", name: :index_profiles_on_key unless index_exists?(:profiles, :key, name: :index_profiles_on_key)
  end
end
