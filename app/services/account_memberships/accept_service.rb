module AccountMemberships
  # Aceite do convite: cria (ou REATIVA) o admin_user espelho no tenant
  # convidado com o snapshot de acesso do convite. O trigger de governança do
  # banco valida perfil/gestor de graça, como para qualquer admin_user.
  class AcceptService
    Result = Struct.new(:ok?, :membership, :mirror, :error, keyword_init: true)

    def initialize(membership:, accepting_user:)
      @membership = membership
      @accepting_user = accepting_user # AdminUser logado (primário) dono do e-mail
    end

    def call
      return failure("Convite inválido.") if @membership.blank? || !@membership.invited?
      return failure("Convite expirado — peça um novo convite.") if @membership.invite_expired?

      primary = @accepting_user.login_identity
      unless owns_invited_email?(primary)
        return failure("Este convite foi emitido para #{@membership.invited_email} — entre com essa conta para aceitar.")
      end

      mirror = nil
      ActiveRecord::Base.transaction do
        Current.set(tenant: @membership.tenant) do
          mirror = find_or_build_mirror(primary)
          mirror.assign_attributes(
            profile_id: @membership.profile_id,
            horizontal_profile_id: @membership.horizontal_profile_id,
            manager_id: @membership.manager_id,
            rentals_manager_id: (@membership.rentals_manager_id if mirror.has_attribute?(:rentals_manager_id)),
            acting_type: @membership.acting_type || mirror.acting_type,
            active: true,
            display_on_site: false
          )
          mirror.save!

          @membership.update!(
            status: :active,
            primary_admin_user: primary,
            member_admin_user: mirror,
            accepted_at: Time.current,
            invite_token_digest: nil
          )
        end
      end

      Current.set(tenant: @membership.tenant) do
        AccessAuditLog.log!(
          event_type: "membership_accepted", result: "allowed", request: nil,
          admin_user: primary, email: @membership.invited_email,
          reason: "Convite aceito — acesso externo ativo",
          metadata: { membership_id: @membership.id, tenant_id: @membership.tenant_id }
        )
      end rescue nil

      Result.new(ok?: true, membership: @membership, mirror: mirror)
    rescue ActiveRecord::RecordInvalid => e
      failure("Não foi possível ativar o acesso: #{e.record.errors.full_messages.to_sentence}")
    end

    private

    def failure(message)
      Result.new(ok?: false, membership: @membership, error: message)
    end

    def owns_invited_email?(primary)
      normalized = @membership.invited_email.to_s.downcase
      primary.email.to_s.downcase == normalized || primary.notification_email.to_s.downcase == normalized
    end

    def find_or_build_mirror(primary)
      existing = @membership.tenant.admin_users.find_by(primary_admin_user_id: primary.id)
      return existing if existing

      @membership.tenant.admin_users.new(
        primary_admin_user_id: primary.id,
        name: primary.name,
        email: AdminUser.mirror_email_for(primary, @membership.tenant),
        contact_email: primary.email,
        password: SecureRandom.hex(24),
        role: :editor
      )
    end
  end
end
