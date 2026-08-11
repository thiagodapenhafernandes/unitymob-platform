class OpenAiUsageEvent < ApplicationRecord
  include TenantScoped

  STATUSES = %w[succeeded failed skipped].freeze

  belongs_to :admin_user, optional: true

  validates :feature, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :input_tokens, :output_tokens, :estimated_cost_cents,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :for_feature, ->(feature) { where(feature: feature) }
  scope :succeeded, -> { where(status: "succeeded") }
  scope :since, ->(time) { where("created_at >= ?", time) }

  def self.requests_count(tenant:, feature:, since:)
    where(tenant: tenant).for_feature(feature).succeeded.since(since).count
  end

  def self.estimated_cost_cents(tenant:, feature:, since:)
    where(tenant: tenant).for_feature(feature).succeeded.since(since).sum(:estimated_cost_cents).to_i
  end
end
