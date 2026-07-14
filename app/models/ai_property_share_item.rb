class AiPropertyShareItem < ApplicationRecord
  belongs_to :ai_property_share_collection
  belongs_to :habitation
  validates :habitation_id, uniqueness: { scope: :ai_property_share_collection_id }
  validate :same_tenant

  private

  def same_tenant
    return if habitation.blank? || ai_property_share_collection.blank?
    errors.add(:habitation, "deve pertencer ao mesmo Tenant") if habitation.tenant_id != ai_property_share_collection.tenant_id
  end
end
