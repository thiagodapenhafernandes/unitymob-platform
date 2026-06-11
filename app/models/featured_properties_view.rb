class FeaturedPropertiesView < ApplicationRecord
  self.table_name = 'featured_properties_view'
  self.primary_key = 'id'

  # The view is read-only
  def readonly?
    true
  end

  # Associations can be defined here if needed, e.g.:
  # belongs_to :habitation, foreign_key: :id
end
