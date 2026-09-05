module Admin::LeadsHelper
  def lead_contact_kind_label(activity)
    LeadActivity::CONTACT_KIND_LABELS[activity.meta("contact_kind").to_s] || "Anotação interna"
  end

  def lead_contact_result_label(activity)
    LeadActivity::CONTACT_RESULT_LABELS[activity.meta("contact_result").to_s]
  end

  def lead_unsuccessful_attempt_count(lead)
    lead&.unsuccessful_attempt_count || 0
  end
end
