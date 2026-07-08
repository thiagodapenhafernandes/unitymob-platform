class MetaFacebookPage < ApplicationRecord
  belongs_to :user_meta_integration
  has_many :meta_lead_forms, dependent: :destroy

  # Escopado por integração: a mesma página Meta pode existir em contas
  # diferentes (modelo agência). Antes era unique global.
  validates :page_id, presence: true, uniqueness: { scope: :user_meta_integration_id }
  validates :name, presence: true

  scope :enabled, -> { where(active: true) }
end
