# Open lead activities follow its current owner; closed records preserve history.
module LeadActivityOwnership
  extend ActiveSupport::Concern

  included do
    before_validation :assign_current_lead_owner
    around_save :save_with_current_lead_owner
  end

  def open_activity?
    status.in?(%w[pendente agendado])
  end

  private

  def follows_lead_owner?
    lead.present? && (open_activity? || (persisted? && status_in_database.in?(%w[pendente agendado])))
  end

  def assign_current_lead_owner
    self.admin_user = lead.admin_user if follows_lead_owner? && lead.admin_user_id.present? && lead.tenant_id == tenant_id
  end

  def save_with_current_lead_owner
    return yield unless follows_lead_owner?

    lead.with_lock do
      if open_activity? && lead.admin_user_id.blank?
        errors.add(:lead, "precisa ter um corretor atribuído antes de criar ou agendar uma atividade")
        next false
      end
      assign_current_lead_owner
      yield
    end
  end
end
