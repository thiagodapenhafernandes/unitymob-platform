class Support::AccessGrantsController < Support::EventsController
  skip_forgery_protection only: :consume
  skip_before_action :authenticate_account!, only: [:consume, :destroy]

  def create
    return head :not_found if SupportDesk.central?
    return head :forbidden unless @account.active?
    data = JSON.parse(request.raw_post)
    ticket = @account.tickets.find_by!(uid: data.fetch("ticket_uid"))
    user = AdminUser.find_by!(id: ticket.requester_id, tenant_id: @account.local_tenant_id, active: true)
    return head :forbidden if user.system_admin?
    token = SecureRandom.urlsafe_base64(32)
    # ponytail: acesso sem consentimento nesta versão; exigir aprovação do solicitante/owner aqui quando habilitado.
    Support::AccessSession.create!(account: @account, ticket: ticket, requester_id: user.id.to_s,
      operator_id: data.fetch("operator_id"), operator_name: data.fetch("operator_name"),
      token_digest: Digest::SHA256.hexdigest(token), redeem_before: 1.minute.from_now)
    render json: { token: token }
  end

  def consume
    return head :not_found if SupportDesk.central?
    grant = Support::AccessSession.find_by!(token_digest: Digest::SHA256.hexdigest(params[:token].to_s))
    grant.with_lock do
      return head :gone unless grant.account.active? && grant.started_at.nil? && grant.ended_at.nil? && grant.redeem_before.future?
      user = AdminUser.find_by!(id: grant.requester_id, tenant_id: grant.account.local_tenant_id, active: true)
      return head :forbidden if user.system_admin?
      # ponytail: antes de consumir o token, validar o consentimento futuro; não criar autorização fictícia agora.
      reset_session
      request.env["warden"].set_user(user, scope: :admin_user)
      session[:support_access_id] = grant.id
      grant.update!(started_at: Time.current, expires_at: 30.minutes.from_now)
      Support::Audit.create!(account_id: grant.account_id, ticket_id: grant.ticket_id, actor: "staff:#{grant.operator_id}", action: "access_started", details: { requester_id: user.id })
    end
    redirect_to "/admin"
  end

  def destroy
    return head :not_found if SupportDesk.central?
    if (grant = Support::AccessSession.find_by(id: session[:support_access_id]))
      grant.update!(ended_at: Time.current)
      Support::Audit.create!(account_id: grant.account_id, ticket_id: grant.ticket_id, actor: "staff:#{grant.operator_id}", action: "access_ended")
    end
    request.env["warden"]&.logout(:admin_user)
    reset_session
    redirect_to "/admin/sign_in"
  end
end
