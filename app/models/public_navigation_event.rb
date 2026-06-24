class PublicNavigationEvent < ApplicationRecord
  PROPERTY_EVENT_NAMES = %w[
    property_view
    property_engaged
    property_whatsapp_click
    property_phone_click
    property_share
    lead_form_started
    lead_form_submitted
  ].freeze
  SEARCH_EVENT_NAMES = %w[property_search page_view search_no_results].freeze

  belongs_to :public_navigation_session
  belongs_to :lead, optional: true
  belongs_to :habitation, optional: true

  validates :name, presence: true
  validates :occurred_at, presence: true

  before_validation :set_defaults

  scope :recent, -> { order(occurred_at: :desc, id: :desc) }
  scope :property_signals, -> { where(name: PROPERTY_EVENT_NAMES) }
  scope :search_signals, -> { where(name: SEARCH_EVENT_NAMES) }

  def property_signal?
    PROPERTY_EVENT_NAMES.include?(name.to_s)
  end

  private

  def set_defaults
    self.occurred_at ||= Time.current
    self.search_params = {} unless search_params.is_a?(Hash)
    self.property_snapshot = {} unless property_snapshot.is_a?(Hash)
    self.metadata = {} unless metadata.is_a?(Hash)
  end
end
