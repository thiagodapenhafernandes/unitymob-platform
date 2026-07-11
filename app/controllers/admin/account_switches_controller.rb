module Admin
  # Troca de conta sem relogin: valida o alvo (conta natal ∪ memberships
  # ativas), roda a política de acesso da CONTA ALVO antes, e troca a
  # identidade do warden (bypass_sign_in — mesmo padrão da impersonação).
  class AccountSwitchesController < Admin::BaseController
    include DeviceRequest

    skip_before_action :enforce_two_factor_setup!, raise: false

    def create
      if session[:impersonator_admin_user_id].present?
        redirect_back fallback_location: admin_root_path, alert: "Encerre a impersonação antes de trocar de conta."
        return
      end

      # Troca de contas é recurso de ADMIN DE CONTAS: a identidade primária
      # precisa ser Admin da Conta (tenant_owner) na conta natal. Vale nos dois
      # sentidos (o espelho volta porque o primário é owner). O guard de
      # revogação do BaseController segue independente deste gate.
      unless current_admin_user.login_identity.tenant_owner?
        redirect_back fallback_location: admin_root_path,
                      alert: "Troca de contas é exclusiva para Admins de Conta."
        return
      end

      target = resolve_target
      if target.nil?
        redirect_back fallback_location: admin_root_path, alert: "Conta indisponível para troca."
        return
      end

      if target.id == current_admin_user.id
        redirect_back fallback_location: admin_root_path
        return
      end

      access_result = AccessControl::Policy.call(admin_user: target, request: request, controller: self)
      unless access_result.allowed?
        begin
          AccessAuditLog.log!(event_type: "account_switch", result: "denied", request: request,
                              admin_user: current_admin_user, reason: access_result.reason,
                              metadata: { target_admin_user_id: target.id, target_tenant_id: target.tenant_id })
        rescue => e
          # Auditoria nunca derruba a troca de conta, mas a falha precisa ser visível.
          Rails.logger.error "[AccountSwitch] falha ao auditar troca negada: #{e.class}: #{e.message}"
        end
        redirect_back fallback_location: admin_root_path,
                      alert: "A conta #{target.tenant&.name} recusou o acesso: #{access_result.reason}"
        return
      end

      previous = current_admin_user
      target.remember_me = true
      bypass_sign_in(target, scope: :admin_user)

      begin
        AccessAuditLog.log!(event_type: "account_switch", result: "allowed", request: request,
                            admin_user: target, reason: "Troca de conta pelo próprio usuário",
                            metadata: { from_admin_user_id: previous.id, from_tenant_id: previous.tenant_id })
      rescue => e
        Rails.logger.error "[AccountSwitch] falha ao auditar troca permitida: #{e.class}: #{e.message}"
      end

      # Abas antigas não podem seguir recebendo cable da identidade anterior.
      begin
        ActionCable.server.remote_connections.where(current_admin_user: previous).disconnect
      rescue => e
        Rails.logger.warn "[AccountSwitch] cable disconnect: #{e.message}"
      end

      # A conta-alvo exige 2FA e este usuário ainda não ativou: leva JÁ à tela de
      # configuração — sem 1 request livre dentro da conta (enforce_two_factor_setup!
      # está skipado aqui e só rodaria no próximo request).
      if target.two_factor_required? && !target.otp_enabled?
        redirect_to admin_two_factor_settings_path,
                    notice: "Você está na conta #{target.tenant&.name}. Ela exige verificação em duas etapas — configure para continuar."
        return
      end

      redirect_to after_switch_path(target), notice: "Você está na conta #{target.tenant&.name}."
    end

    private

    # Alvo legítimo: a identidade primária OU um espelho ativo dela com
    # membership ativa naquele tenant.
    def resolve_target
      identity = current_admin_user.login_identity
      tenant_id = params[:tenant_id].to_i

      return identity if identity.tenant_id == tenant_id

      return nil unless identity.has_attribute?(:primary_admin_user_id)

      mirror = identity.mirror_users.find_by(tenant_id: tenant_id, active: true)
      return nil unless mirror
      return nil unless AccountMembership.table_exists? &&
                        AccountMembership.where(member_admin_user_id: mirror.id, status: :active).exists?

      mirror
    end

    def after_switch_path(target)
      # PWA: quem trocou a partir do /field permanece no /field.
      return field_root_path if mobile_device_request? && params[:context].to_s == "field"
      return field_root_path if mobile_device_request? && (!target.respond_to?(:can?) || !target.can?(:view, :dashboard))

      admin_root_path
    end
  end
end
