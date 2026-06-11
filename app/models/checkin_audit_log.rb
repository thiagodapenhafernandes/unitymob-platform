# frozen_string_literal: true

# Trilha de auditoria de check-ins — append-only via trigger PG.
# Qualquer UPDATE/DELETE no banco é rejeitado com PG::RaiseException.
class CheckinAuditLog < ApplicationRecord
  ACTIONS = %w[
    created
    closed
    forced_closed
    flagged_suspicious
    manual_request_created
    manual_request_approved
    manual_request_rejected
  ].freeze

  belongs_to :check_in, optional: true
  belongs_to :admin_user, optional: true
  belongs_to :actor_admin_user, class_name: "AdminUser", optional: true

  validates :action, presence: true, inclusion: { in: ACTIONS }

  # Sem updated_at — a tabela não é atualizável.
  self.record_timestamps = false
  before_create :set_created_at

  # Rails-side safeguard (o trigger PG é a garantia real).
  def readonly?
    persisted?
  end

  def self.log!(action:, check_in: nil, admin_user: nil, actor: nil, ip: nil, metadata: {})
    create!(
      action: action,
      check_in: check_in,
      admin_user: admin_user || check_in&.admin_user,
      actor_admin_user: actor,
      ip: ip,
      metadata: metadata
    )
  end

  private

  def set_created_at
    self.created_at ||= Time.current
  end
end
