class Admin::AccessSecurityController < Admin::BaseController
  before_action -> { check_permission!(:manage, :access_security) }

  def show
    load_dashboard
  end

  def update
    unless tenant_owner?
      redirect_to admin_access_security_path(anchor: "rules-pane"), alert: "Apenas o Dono da conta pode alterar configurações globais de segurança."
      return
    end

    # Formulários da seção "Sessões" retornam cedo: não reprocessam os toggles
    # gerais (params ausentes desligariam tudo).
    return end_all_sessions! if truthy?(params[:end_all_sessions]) && current_tenant.respond_to?(:session_epoch_at)
    return update_session_settings if params[:section].to_s == "sessions"

    if current_tenant.respond_to?(:enforce_broker_ip_allowlist)
      current_tenant.update(
        enforce_broker_ip_allowlist: truthy?(params[:enforce_broker_ip_allowlist]),
        enforce_broker_trusted_devices: truthy?(params[:enforce_broker_trusted_devices])
      )
    else
      # pré-migration: mantém o Setting global antigo
      Setting.set(AccessControl::Settings::ENFORCE_BROKER_IP_KEY, truthy?(params[:enforce_broker_ip_allowlist]).to_s, "Exigir IP permitido para corretores")
      Setting.set(AccessControl::Settings::ENFORCE_BROKER_DEVICE_KEY, truthy?(params[:enforce_broker_trusted_devices]).to_s, "Exigir aparelho confiável para corretores")
    end

    # Exigir 2FA de todos os usuários da conta (coluna do tenant; guard pré-migration)
    if current_tenant.respond_to?(:require_two_factor)
      current_tenant.update(require_two_factor: truthy?(params[:require_two_factor]))
    end

    redirect_to admin_access_security_path, notice: "Configurações de segurança atualizadas."
  end

  private

  # Expiração de sessão por conta (colunas do tenant; guard pré-migration).
  # Valores clampados aqui para o update nunca falhar silenciosamente.
  def update_session_settings
    if current_tenant.respond_to?(:session_timeout_enabled)
      current_tenant.update(
        session_timeout_enabled: truthy?(params[:session_timeout_enabled]),
        session_timeout_days: clamped_days(params[:session_timeout_days], max: 90) || current_tenant.session_timeout_days || 7,
        session_remember_days: clamped_days(params[:session_remember_days], max: 180)
      )
    end

    redirect_to admin_access_security_path, notice: "Configurações de sessão atualizadas."
  end

  # "Encerrar todas as sessões agora": o epoch invalida as sessões antigas no
  # warden e limpar remember_created_at mata os cookies "lembrar-me". A sessão
  # do próprio dono é re-carimbada para ele não derrubar a si mesmo.
  def end_all_sessions!
    affected = current_tenant.admin_users.where.not(id: current_admin_user.id).count
    # Isenção curta pro autor: request em voo de outra aba dele (cookie com
    # carimbo antigo) re-carimba em vez de derrubar (corrida multi-aba).
    Rails.cache.write(AdminSessionEpoch.exempt_cache_key(current_tenant.id), current_admin_user.id, expires_in: 2.minutes)
    current_tenant.update(session_epoch_at: Time.current)
    current_tenant.admin_users.update_all(remember_created_at: nil)
    request.env["warden"].session(:admin_user)[AdminSessionEpoch::SESSION_KEY] = Time.current.to_i

    # WebSockets já abertos não re-autenticam sozinhos — corta o cable dos
    # demais usuários (mesmo padrão do AccountSwitchesController).
    begin
      current_tenant.admin_users.where.not(id: current_admin_user.id).find_each do |user|
        ActionCable.server.remote_connections.where(current_admin_user: user).disconnect
      end
    rescue => e
      Rails.logger.warn "[AccessSecurity] cable disconnect: #{e.message}"
    end

    redirect_to admin_access_security_path, notice: "Sessões encerradas: #{affected} usuário(s) da conta precisarão entrar novamente. A sua sessão atual foi preservada."
  end

  def clamped_days(raw, max:)
    return nil if raw.blank?

    raw.to_i.clamp(1, max)
  end

  def load_dashboard
    scoped_admin_user_ids = accessible_owner_ids(:access_security)

    rules_scope = current_tenant.access_control_rules.includes(:profile, :admin_user, :created_by).recent
    rules_scope = rules_scope.where(scope_type: "user", admin_user_id: scoped_admin_user_ids) if scoped_admin_user_ids
    rules_scope = rules_scope.where(rule_type: params[:rule_type]) if params[:rule_type].present?
    rules_scope = rules_scope.where(scope_type: params[:scope_type]) if params[:scope_type].present?
    rules_scope = rules_scope.where(profile_id: params[:rule_profile_id]) if params[:rule_profile_id].present?
    rules_scope = rules_scope.where(admin_user_id: params[:rule_admin_user_id]) if params[:rule_admin_user_id].present?
    rules_scope = rules_scope.where(enabled: ActiveModel::Type::Boolean.new.cast(params[:rule_enabled])) if params[:rule_enabled].present?
    rules_scope = rules_scope.where("ip_value ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:rule_ip].to_s)}%") if params[:rule_ip].present?

    devices_scope = current_tenant.trusted_devices.includes(admin_user: :profile).includes(:created_by).recent
    devices_scope = devices_scope.where(admin_user_id: scoped_admin_user_ids) if scoped_admin_user_ids
    devices_scope = devices_scope.where(status: params[:device_status]) if params[:device_status].present?
    devices_scope = devices_scope.where(admin_user_id: params[:device_admin_user_id]) if params[:device_admin_user_id].present?
    if params[:device_profile_id].present?
      device_profile = current_tenant.profiles.find_by(id: params[:device_profile_id])
      devices_scope = devices_scope.where(admin_user_id: scoped_admin_users(scoped_admin_user_ids).matching_access_profile(device_profile).select(:id)) if device_profile
    end
    devices_scope = devices_scope.where(last_ip: params[:device_ip]) if params[:device_ip].present?
    devices_scope = devices_scope.where(device_type: params[:device_type]) if params[:device_type].present?
    devices_scope = devices_scope.where(browser: params[:device_browser]) if params[:device_browser].present?

    @rules = rules_scope
    @trusted_devices = devices_scope.limit(120)
    @profiles = scoped_profile_relation(scoped_admin_user_ids).order(:name)
    @admin_users = scoped_admin_users(scoped_admin_user_ids).order(:name)
    @can_manage_global_access_security = tenant_owner?
    @access_scope_types = tenant_owner? ? AccessControlRule::SCOPE_TYPES : AccessControlRule::SCOPE_TYPES.slice("user")
    device_filter_scope = current_tenant.trusted_devices
    device_filter_scope = device_filter_scope.where(admin_user_id: scoped_admin_user_ids) if scoped_admin_user_ids
    @available_device_types = device_filter_scope.where.not(device_type: [nil, ""]).distinct.order(:device_type).pluck(:device_type)
    @available_browsers = device_filter_scope.where.not(browser: [nil, ""]).distinct.order(:browser).pluck(:browser)
    @active_tab = access_security_active_tab
    @new_rule = current_tenant.access_control_rules.new(scope_type: tenant_owner? ? "global" : "user", rule_type: "allow_ip", enabled: true)
    @broker_ip_allowlist_enabled = AccessControl::Settings.broker_ip_allowlist_enabled?(tenant: current_tenant)
    @broker_trusted_devices_enabled = AccessControl::Settings.broker_trusted_devices_enabled?(tenant: current_tenant)
  end

  def access_security_active_tab
    return "devices" if params.slice(:device_status, :device_admin_user_id, :device_profile_id, :device_ip, :device_type, :device_browser).values.any?(&:present?)
    return "rules" if params.slice(:rule_type, :scope_type, :rule_profile_id, :rule_admin_user_id, :rule_enabled, :rule_ip).values.any?(&:present?)

    tenant_owner? ? "settings" : "rules"
  end

  def scoped_admin_users(scoped_admin_user_ids)
    users = current_tenant.admin_users.account_members
    scoped_admin_user_ids ? users.where(id: scoped_admin_user_ids) : users
  end

  def scoped_profile_relation(scoped_admin_user_ids)
    return current_tenant.profiles if scoped_admin_user_ids.nil?

    users = scoped_admin_users(scoped_admin_user_ids)
    profile_ids = users.where(horizontal_profile_id: nil).where.not(profile_id: nil).distinct.pluck(:profile_id)
    profile_ids += users.where.not(horizontal_profile_id: nil).distinct.pluck(:horizontal_profile_id)
    current_tenant.profiles.where(id: profile_ids.compact.uniq)
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
