# Aceite público do convite multi-conta (via token do e-mail).
# Exige login com o e-mail convidado: a posse do e-mail é a credencial.
class MembershipInvitationsController < ApplicationController
  layout "admin_login"

  def show
    @membership = AccountMembership.find_by_raw_token(params[:token])

    if @membership.nil? || @membership.revoked?
      render :invalid, status: :not_found
      return
    end

    if @membership.active?
      redirect_to new_admin_user_session_path, notice: "Este convite já foi aceito — entre e troque de conta pelo menu."
      return
    end

    if @membership.invite_expired?
      render :expired, status: :gone
      return
    end

    unless admin_user_signed_in?
      session[:pending_membership_token] = params[:token]
      redirect_to new_admin_user_session_path,
                  alert: "Entre com a conta #{@membership.invited_email} para aceitar o convite."
      return
    end
  end

  def update
    membership = AccountMembership.find_by_raw_token(params[:token])
    unless admin_user_signed_in?
      redirect_to new_admin_user_session_path, alert: "Entre para aceitar o convite."
      return
    end

    result = AccountMemberships::AcceptService.new(
      membership: membership,
      accepting_user: current_admin_user
    ).call

    session.delete(:pending_membership_token)
    if result.ok?
      redirect_to admin_root_path,
                  notice: "Convite aceito! Agora você pode trocar para a conta #{membership.tenant.name} pelo menu do usuário."
    else
      redirect_to new_admin_user_session_path, alert: result.error
    end
  end
end
