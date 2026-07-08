class AccountMembershipMailer < ApplicationMailer
  # Convite de acesso externo (multi-conta). Enviado inline no request para o
  # SMTP da conta (Current.tenant) valer.
  def invite
    @membership = params[:membership]
    @invite_url = params[:invite_url]
    @tenant = @membership.tenant
    @invited_by = @membership.invited_by

    mail(
      to: @membership.invited_email,
      subject: "Convite: acesso à conta #{@tenant.name}"
    )
  end
end
