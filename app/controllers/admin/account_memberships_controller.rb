module Admin
  # Convites de acesso EXTERNO (multi-conta): quem gerencia usuários convida um
  # e-mail de fora; o convite escolhe o perfil que o convidado terá NESTA conta.
  class AccountMembershipsController < Admin::BaseController
    before_action -> { check_permission!(:manage, :corretores) }
    before_action :ensure_feature_available!

    def index
      @memberships = current_tenant.account_memberships
                                   .includes(:profile, :horizontal_profile, :invited_by, :member_admin_user)
                                   .order(created_at: :desc)
      @membership = current_tenant.account_memberships.new
      load_form_options
    end

    def create
      attrs = membership_params.to_h.symbolize_keys
      resolve_access_profile!(attrs)

      service = AccountMemberships::InviteService.new(
        tenant: current_tenant,
        invited_by: current_admin_user,
        attributes: attrs,
        invite_url_builder: ->(raw_token) { membership_invitation_url(raw_token) }
      )
      membership = service.call

      if membership.persisted?
        flash[:invite_url] = service.invite_url
        notice = service.mail_delivered ? "Convite enviado para #{membership.invited_email}." : "Convite criado, mas o e-mail falhou — copie o link abaixo e envie por outro canal."
        redirect_to admin_account_memberships_path, notice: notice
      else
        redirect_to admin_account_memberships_path, alert: membership.errors.full_messages.to_sentence
      end
    end

    def destroy
      membership = current_tenant.account_memberships.find(params[:id])
      membership.revoke!(by: current_admin_user)
      AccessAuditLog.log!(
        event_type: "membership_revoked", result: "allowed", request: request,
        admin_user: current_admin_user, email: membership.invited_email,
        reason: "Acesso externo revogado", metadata: { membership_id: membership.id }
      ) rescue nil
      redirect_to admin_account_memberships_path, notice: "Acesso de #{membership.invited_email} revogado."
    end

    private

    def ensure_feature_available!
      return if AccountMembership.table_exists?

      redirect_to admin_root_path, alert: "Convites externos indisponíveis: migração pendente."
    end

    def membership_params
      params.require(:account_membership).permit(
        :invited_email, :access_profile_id, :acting_type, :manager_id, :rentals_manager_id
      )
    end

    # Mesmo contrato do cadastro de usuários: um único "Perfil de acesso";
    # o sistema resolve o eixo (horizontal ancora no vertical raiz).
    def resolve_access_profile!(attrs)
      raw_id = attrs.delete(:access_profile_id)
      profile = current_tenant.profiles.find_by(id: raw_id)
      return if profile.nil?

      if profile.vertical?
        attrs[:profile_id] = profile.id
        attrs[:horizontal_profile_id] = nil
      else
        attrs[:profile_id] = profile.root_vertical_profile&.id
        attrs[:horizontal_profile_id] = profile.id
        attrs[:manager_id] = nil
        attrs[:rentals_manager_id] = nil
      end
    end

    def load_form_options
      profiles = current_tenant.profiles.where(active: true).to_a
      vertical = profiles.select(&:vertical?).reject(&:tenant_owner?).sort_by { |p| p.position.to_i }
      horizontal = profiles.select(&:horizontal?).sort_by { |p| p.name.to_s.downcase }
      @access_profile_options = {
        "Hierarquia" => vertical.map { |p| [p.name, p.id] },
        "Funções operacionais" => horizontal.map { |p| [p.name, p.id] }
      }
      @manager_options = current_tenant.admin_users.active.where.not(profile_id: nil)
                                       .includes(:profile)
                                       .select { |u| u.profile&.vertical? && !u.profile.agent? }
                                       .sort_by(&:name)
                                       .map { |u| ["#{u.name} (#{u.profile.name})", u.id] }
    end
  end
end
