# Diretório restrito à conta autenticada pela assinatura da central.
class Support::RecipientsController < Support::EventsController
  def create
    return head :not_found if SupportDesk.central?
    return head :forbidden unless @account.active?
    data = JSON.parse(request.raw_post)
    users = AdminUser.where(tenant_id: @account.local_tenant_id, active: true)
    users = users.where(id: data['id']) if data['id'].present?
    if data['q'].present?
      pattern = "%#{AdminUser.sanitize_sql_like(data['q'].to_s.first(100))}%"
      users = users.where('name ILIKE ? OR email ILIKE ?', pattern, pattern)
    end
    render json: {users: users.order(:name).limit(30).reject(&:system_admin?).map { |u| {id: u.id.to_s, name: u.name, email: u.email} }}
  end
end
