class AutomationWebhookDelivery < ApplicationRecord
  STATUSES = %w[pending success failed retry].freeze
  HTTP_METHODS = %w[post put patch].freeze

  belongs_to :automation_event, optional: true
  belongs_to :automation_run, optional: true
  belongs_to :automation_execution_step, optional: true
  belongs_to :lead, optional: true

  before_validation :normalize_http_method

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :http_method, inclusion: { in: HTTP_METHODS }
  validates :status, inclusion: { in: STATUSES }

  private

  def normalize_http_method
    self.http_method = http_method.to_s.downcase.presence || "post"
  end
end
