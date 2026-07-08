module AccountMemberships
  # Cria o convite de acesso externo e envia o e-mail com o token (inline no
  # request: o SMTP da conta depende de Current.tenant). Retorna a membership;
  # erros de validação ficam em membership.errors.
  class InviteService
    attr_reader :invite_url, :mail_delivered

    def initialize(tenant:, invited_by:, attributes:, invite_url_builder:)
      @tenant = tenant
      @invited_by = invited_by
      @attributes = attributes
      @invite_url_builder = invite_url_builder # ->(raw_token) { url }
    end

    def call
      membership = @tenant.account_memberships.new(@attributes)
      membership.invited_by = @invited_by
      membership.status = :invited
      membership.invited_email = membership.invited_email.to_s.strip.downcase

      # Se o e-mail já é de um usuário do sistema, resolve o primário agora
      # (o aceite ainda valida a posse do e-mail via login).
      primary = AdminUser.find_by("lower(email) = ?", membership.invited_email)
      membership.primary_admin_user = primary&.login_identity

      return membership unless membership.save

      raw_token = membership.generate_invite_token!
      @invite_url = @invite_url_builder.call(raw_token)

      # E-mail é o caminho feliz, mas falha de SMTP não pode perder o convite:
      # a URL fica disponível para envio manual (WhatsApp etc.).
      begin
        AccountMembershipMailer.with(membership: membership, invite_url: @invite_url).invite.deliver_now
        @mail_delivered = true
      rescue => e
        @mail_delivered = false
        Rails.logger.error "[AccountMemberships] Falha ao enviar convite ##{membership.id}: #{e.message}"
      end

      AccessAuditLog.log!(
        event_type: "membership_invited", result: "allowed", request: nil,
        admin_user: @invited_by, email: membership.invited_email,
        reason: "Convite de acesso externo enviado",
        metadata: { membership_id: membership.id, profile_id: membership.profile_id }
      ) rescue nil

      membership
    end
  end
end
