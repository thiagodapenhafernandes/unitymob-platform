# frozen_string_literal: true

# Pedido de check-in manual — usado quando GPS falha e o corretor precisa
# de aprovação do admin para registrar presença.
class ManualCheckinRequest < ApplicationRecord
  include TenantScoped

  enum status: { pending: 0, approved: 1, rejected: 2 }

  belongs_to :admin_user
  belongs_to :store
  belongs_to :reviewed_by_admin_user, class_name: "AdminUser", optional: true
  belongs_to :approved_check_in, class_name: "CheckIn", optional: true

  validates :justification, presence: true, length: { minimum: 10, maximum: 1000 }

  scope :recent, -> { order(created_at: :desc) }

  def review!(reviewer:, approve:, notes: nil)
    if approve
      update!(status: :approved, reviewed_by_admin_user: reviewer, reviewed_at: Time.current, review_notes: notes)
    else
      update!(status: :rejected, reviewed_by_admin_user: reviewer, reviewed_at: Time.current, review_notes: notes)
    end
  end
end
