class MetaCampaignInsight < ApplicationRecord
  include TenantScoped

  validates :campaign_id, presence: true
  validates :date, presence: true
  validates :campaign_id, uniqueness: { scope: [:tenant_id, :date] }

  scope :in_period, ->(from, to) { where(date: from..to) }
  scope :ordered, -> { order(date: :desc, spend: :desc) }
end
