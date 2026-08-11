class CommercialContractEvent < ApplicationRecord
  EVENT_TYPES = %w[
    created updated sent viewed otp_requested otp_failed accepted canceled pdf_generated
  ].freeze

  belongs_to :tenant
  belongs_to :proposal, class_name: "CommercialContractProposal", foreign_key: :proposal_id
  belongs_to :admin_user, optional: true

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }

  scope :ordered, -> { order(created_at: :desc) }
end
