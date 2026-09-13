class MetaFacebookPage < ApplicationRecord
  belongs_to :user_meta_integration
  has_many :meta_lead_forms, dependent: :destroy

  # Escopado por integração: a mesma página Meta pode existir em contas
  # diferentes (modelo agência). Antes era unique global.
  validates :page_id, presence: true, uniqueness: { scope: :user_meta_integration_id }
  validates :name, presence: true

  scope :available_for_distribution, ->(tenant_id) {
    joins(:user_meta_integration)
      .where(user_meta_integrations: { tenant_id: tenant_id })
      .where(active: true)
      .where("user_meta_integrations.selected_page_ids @> jsonb_build_array(meta_facebook_pages.page_id)")
  }

  scope :enabled, -> { where(active: true) }
end
