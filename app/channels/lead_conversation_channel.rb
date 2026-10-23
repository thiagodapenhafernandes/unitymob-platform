class LeadConversationChannel < ApplicationCable::Channel
  def self.stream_name(lead)
    "lead_conversation:#{lead.tenant_id}:#{lead.id}"
  end

  def subscribed
    user = current_admin_user
    return reject unless user&.can?(:view, :leads)
    tenant_id = params[:tenant_id].to_i
    return reject unless tenant_id == user.tenant_id || user.system_admin?
    tenant = Tenant.find_by(id: tenant_id)
    lead = tenant && Lead.accessible_to_admin(user, tenant: tenant).find_by(id: params[:lead_id])
    return reject unless lead

    # Somente invalidação; o GET revalida permissões antes de retornar conteúdo.
    stream_from self.class.stream_name(lead)
  end
end
