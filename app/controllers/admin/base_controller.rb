class Admin::BaseController < ApplicationController
  class PermissionDenied < StandardError; end

  rescue_from PermissionDenied, with: :render_permission_denied

  include Admin::ContextItems
  include UserActivityTrackable

  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_invalid_admin_session

  SENSITIVE_ACCESS_AUDIT_CONTROLLERS = %w[
    admin/access_security
    admin/two_factor_settings
    admin/admin_users
    admin/profiles
    admin/account_memberships
    admin/system
    admin/system/tenants
    admin/system/tenant_domains
  ].freeze

  SYSTEM_ADMIN_GLOBAL_CONTROLLERS = %w[
    admin/push_settings
    admin/theme_preferences
  ].freeze
  ADMIN_LANDING_SECTIONS = %i[
    product
    operation
    management
    growth
    public_site
    integrations
    settings
    account
  ].freeze
  # Controllers admin que NÃO são módulos de conta/perfil:
  # sessão, preferências pessoais, manifesto PWA, upload direto, contexto visual
  # e troca/impersonação de identidade. Todo controller operacional fora desta
  # lista deve declarar requires_permission ou um gate equivalente testável.
  PERMISSION_GATE_EXEMPT_CONTROLLER_FILES = {
    "app/controllers/admin/account_switches_controller.rb" => "troca de conta já valida owner/membership/política de acesso",
    "app/controllers/admin/context_items_controller.rb" => "estado visual da sessão do próprio usuário",
    "app/controllers/admin/impersonations_controller.rb" => "encerra sessão de impersonação já iniciada por Admin do Sistema",
    "app/controllers/admin/manifests_controller.rb" => "manifesto PWA público/dinâmico sem operação de conta",
    "app/controllers/admin/my_profiles_controller.rb" => "perfil pessoal do usuário autenticado",
    "app/controllers/admin/sessions_controller.rb" => "login/logout/2FA do Devise",
    "app/controllers/admin/tenant_direct_uploads_controller.rb" => "infra de upload direto com tenant metadata",
    "app/controllers/admin/theme_preferences_controller.rb" => "preferência visual pessoal"
  }.freeze

  before_action :authenticate_admin_user!
  before_action :set_current_admin_user
  before_action :ensure_tenant_context_selected!
  before_action :enforce_access_control_policy!
  before_action :enforce_two_factor_setup!
  before_action :enforce_mirror_still_active!
  before_action :prevent_search_indexing
  before_action :prevent_admin_page_cache
  around_action :track_unhandled_admin_exception
  around_action :measure_admin_page_render
  after_action :record_allowed_admin_access
  layout 'admin'

  # DSL padrão para proteger URLs administrativas pelo catálogo Profile::RESOURCES.
  # Novo controller não deve chamar `check_permission!` em before_action manual:
  # use `requires_permission :view, :leads` ou `requires_permission :manage, :conta`.
  # A UI pode esconder menus, mas a URL direta continua bloqueada aqui no backend.
  def self.requires_permission(action, resource, **options)
    before_action(options) { check_permission!(action, resource) }
  end

  private
  
  def prevent_search_indexing
    response.set_header("X-Robots-Tag", "noindex, nofollow, noarchive, nosnippet")
  end

  def prevent_admin_page_cache
    response.set_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
    response.set_header("Pragma", "no-cache")
    response.set_header("Expires", "0")
  end

  def render_lead_operational_turbo_stream(lead, notice: nil, alert: nil, status: :ok)
    unless lead.tenant_id == current_tenant.id && can?(:view, :leads) && owner_in_scope?(:leads, lead.admin_user_id)
      return redirect_back(fallback_location: admin_root_path, notice: notice, alert: alert)
    end

    flash.now[:notice] = notice if notice.present?
    flash.now[:alert] = alert if alert.present?

    render(
      turbo_stream: turbo_stream.replace(
        view_context.dom_id(lead, :pwa_operational_panel),
        partial: "admin/leads/pwa_operational_panel",
        locals: { lead: lead }
      ),
      status: status
    )
  end

  def handle_invalid_admin_session
    Rails.logger.info(
      "[admin_session] invalid_authenticity_token path=#{request.fullpath} " \
      "method=#{request.request_method} admin_user_id=#{Current.admin_user&.id}"
    )

    reset_session
    redirect_to new_admin_user_session_path, alert: "Sua sessão expirou. Entre novamente para continuar."
  end

  def track_unhandled_admin_exception
    yield
  rescue PermissionDenied
    raise
  rescue StandardError => exception
    Rails.logger.error(
      "[admin_exception] request_id=#{request.request_id} " \
      "page=#{controller_path}##{action_name} path=#{admin_filtered_path} " \
      "admin_user_id=#{Current.admin_user&.id || current_admin_user&.id} " \
      "tenant_id=#{Current.tenant&.id || current_tenant&.id} " \
      "#{exception.class}: #{exception.message.to_s.truncate(300)}"
    )

    Rails.error.report(
      exception,
      handled: false,
      severity: :error,
      source: (defined?(ErrorTracking::ACTION_DISPATCH_SOURCE) ? ErrorTracking::ACTION_DISPATCH_SOURCE : "application.action_dispatch"),
      context: admin_exception_context
    )
    raise
  end

  def admin_exception_context
    {
      request_id: request.request_id,
      path: admin_filtered_path.to_s[0, 300],
      method: request.request_method,
      controller: controller_path,
      action: action_name,
      format: request.format&.ref,
      params: admin_filtered_params,
      admin_user_id: Current.admin_user&.id || current_admin_user&.id,
      tenant_id: Current.tenant&.id || current_tenant&.id,
      ip: request.remote_ip,
      user_agent: request.user_agent.to_s[0, 300],
      referer: request.referer.to_s[0, 300],
      admin_controller: true
    }.compact
  rescue StandardError
    {}
  end

  def admin_filtered_path
    query = admin_parameter_filter.filter(request.query_parameters)
    query_string = Rack::Utils.build_nested_query(query)
    query_string.present? ? "#{request.path}?#{query_string}" : request.path
  rescue StandardError
    request.filtered_path
  end

  def admin_filtered_params
    admin_parameter_filter
      .filter(request.filtered_parameters)
      .except("controller", "action")
  rescue StandardError
    {}
  end

  def admin_parameter_filter
    @admin_parameter_filter ||= ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
  end

  def measure_admin_page_render
    @admin_render_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    if @admin_render_started_at
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @admin_render_started_at) * 1000).round(1)
      @admin_render_duration_ms = duration_ms

      unless response.committed?
        response.set_header("X-Admin-Render-Duration-Ms", duration_ms.to_s)
        response.set_header("X-Admin-Page", "#{controller_path}##{action_name}")
        response.set_header("Server-Timing", "admin_render;dur=#{duration_ms}")
      end

      Rails.logger.info(
        "[admin_render] page=#{controller_path}##{action_name} status=#{response.status} duration_ms=#{duration_ms} " \
        "method=#{request.request_method} path=#{request.fullpath}"
      )
    end
  end

  def set_current_admin_user
    Current.admin_user = current_admin_user
    Current.tenant = resolve_admin_tenant_context
  end

  # Espelho revogado/desativado não permanece logado: volta ao primário no
  # request seguinte (corte imediato pós-revogação; zero custo p/ usuários comuns).
  # Defense-in-depth: além de active?, exige membership ATIVA — se a revogação
  # desativou o espelho mas a flag active ficou dessincronizada, a ausência de
  # membership viva ainda expulsa o espelho.
  def enforce_mirror_still_active!
    return unless current_admin_user.respond_to?(:mirror?) && current_admin_user&.mirror?
    return unless mirror_access_revoked?

    primary = current_admin_user.primary_admin_user
    if primary
      bypass_sign_in(primary, scope: :admin_user)
      redirect_to admin_root_path, alert: "Seu acesso à conta anterior foi revogado — você voltou para #{primary.tenant&.name}."
    else
      sign_out(:admin_user)
      redirect_to new_admin_user_session_path, alert: "Seu acesso foi revogado."
    end
  end

  # Verdadeiro quando o espelho não deve mais ter acesso: espelho inativo OU
  # sem nenhuma AccountMembership ativa amarrando-o ao tenant. Tolerante
  # pré-migration (tabela/coluna podem não existir).
  def mirror_access_revoked?
    return true unless current_admin_user.active?

    return false unless defined?(AccountMembership) && AccountMembership.table_exists?

    !AccountMembership.where(member_admin_user_id: current_admin_user.id, status: :active).exists?
  rescue ActiveRecord::StatementInvalid
    # Coluna/enum ausente pré-migration: não expulsa por falta de infra.
    false
  end

  # Conta exige 2FA: quem ainda não ativou é levado à tela de configuração
  # (não bloqueia o login — sem lockout por design).
  def enforce_two_factor_setup!
    return unless current_admin_user
    return unless current_admin_user.two_factor_required? && !current_admin_user.otp_enabled?
    return if controller_path == "admin/two_factor_settings"

    redirect_to admin_two_factor_settings_path,
                alert: "Sua conta exige verificação em duas etapas. Configure para continuar."
  end

  def resolve_admin_tenant_context
    return current_admin_user&.tenant unless current_admin_user&.system_admin?

    session.delete(:admin_current_tenant_id)
    nil
  end

  def ensure_tenant_context_selected!
    return unless current_admin_user&.system_admin?
    return if Current.tenant.present?
    return if controller_path == "admin/system" || controller_path.start_with?("admin/system/")
    # Push/VAPID é config GLOBAL editada pelo Admin do Sistema — precisa ser
    # alcançável sem contexto de conta (senão ninguém edita: dono vê read-only).
    return if SYSTEM_ADMIN_GLOBAL_CONTROLLERS.include?(controller_path)

    redirect_to admin_system_path, alert: "Admin do Sistema acessa áreas da conta apenas por impersonação."
  end

  def enforce_access_control_policy!
    return unless current_admin_user
    return if impersonating_admin_user?

    access_result = AccessControl::Policy.call(admin_user: current_admin_user, request: request, controller: self)
    return if access_result.allowed?

    AccessAuditLog.log!(
      event_type: "access_denied",
      result: "denied",
      request: request,
      admin_user: current_admin_user,
      reason: access_result.reason,
      metadata: { trusted_device_id: access_result.device&.id, trusted_device_status: access_result.device&.status }.compact
    )

    @access_audit_denied = true
    sign_out(current_admin_user)
    redirect_to new_admin_user_session_path, alert: access_result.reason
  end
  
  def require_admin!
    unless tenant_owner?
      redirect_to admin_root_path, alert: 'Acesso negado. Apenas administradores.'
    end
  end

  def current_tenant
    Current.tenant || (current_admin_user&.system_admin? ? nil : current_admin_user&.tenant)
  end
  helper_method :current_tenant

  def selected_tenant_context?
    current_tenant.present?
  end
  helper_method :selected_tenant_context?

  def system_admin?
    current_admin_user&.system_admin?
  end
  helper_method :system_admin?

  def tenant_owner?
    current_admin_user&.tenant_owner?
  end
  helper_method :tenant_owner?

  def admin_or_administrative_user?
    return false unless current_admin_user
    return true if current_admin_user.admin? || tenant_owner?

    [
      current_admin_user.access_profile,
      current_admin_user.profile,
      current_admin_user.horizontal_profile
    ].compact.any? { |profile| profile.respond_to?(:administrativo?) && profile.administrativo? }
  end
  helper_method :admin_or_administrative_user?

  def require_admin_or_administrative_user!
    return if admin_or_administrative_user?

    respond_to do |format|
      format.json { render json: { errors: ["Acesso restrito ao Administrador e Administrativo."] }, status: :forbidden }
      format.html { redirect_to admin_root_path, alert: "Acesso restrito ao Administrador e Administrativo." }
    end
  end

  def require_system_admin!
    unless system_admin?
      redirect_to admin_root_path, alert: 'Acesso restrito ao Admin do Sistema.'
    end
  end

  def check_permission!(action, resource)
    unless current_admin_user&.can?(action, resource)
      AccessAuditLog.log!(
        event_type: "access_denied",
        result: "denied",
        request: request,
        admin_user: current_admin_user,
        reason: "Permissão insuficiente",
        metadata: { required_action: action, required_resource: resource }
      )

      @access_audit_denied = true
      raise PermissionDenied
    end
  end

  # Para telas que aceitam mais de uma permissão equivalente (ex: seção macro
  # ou recurso granular). Mantém o OR no backend central, sem espalhar `can?`
  # manual por controllers; se nenhuma passar, audita a primeira exigência.
  def check_any_permission!(*requirements)
    return if requirements.any? { |action, resource| current_admin_user&.can?(action, resource) }

    check_permission!(*requirements.first)
  end

  def render_permission_denied
    respond_to do |format|
      format.html { redirect_to admin_root_path, alert: "Você não tem permissão para acessar esta área." }
      format.json { render json: { error: "forbidden" }, status: :forbidden }
      format.any { head :forbidden }
    end
  end

  # Fallback abstrato da raiz do admin: usa o mesmo catálogo do sidebar para
  # mandar usuários sem Dashboard para o primeiro módulo permitido. Não crie
  # regra por nome de perfil aqui; novo módulo entra em Profile::RESOURCES.
  def first_permitted_admin_path
    ADMIN_LANDING_SECTIONS.each do |section|
      Profile.sidebar_items_for(section).each do |item|
        path = permitted_sidebar_item_path(item)
        return path if path.present? && path != admin_root_path
      end
    end

    nil
  end

  def permitted_sidebar_item_path(item)
    return nil if item[:caption].present?
    return nil if item[:dynamic].present?

    if item[:group].present?
      return nil unless sidebar_catalog_item_permitted?(item)

      Array(item[:children]).each do |child|
        path = permitted_sidebar_item_path(child)
        return path if path.present?
      end
      return nil
    end

    return nil unless sidebar_catalog_item_permitted?(item)

    public_send(item.fetch(:path), **item.fetch(:path_params, {}))
  rescue NoMethodError, KeyError
    nil
  end

  def sidebar_catalog_item_permitted?(item)
    case item[:condition].to_s
    when "whatsapp_service_ready"
      return false unless current_tenant.present?
      return false unless WhatsappBusinessIntegration.current(current_tenant)&.messaging_ready?
    end

    permission_all = Array(item[:permission_all])
    return false if permission_all.any? && !permission_all.all? { |action, resource| can?(action, resource) }

    permission_any = Array(item[:permission_any])
    return permission_any.any? { |action, resource| can?(action, resource) } if permission_any.any?

    action, resource = item[:permission]
    return can?(action, resource) if action.present?

    true
  end

  def accessible_commercial_leads
    check_permission!(:view, :leads)
    %i[leads comercial].reduce(current_tenant.leads) do |scope, resource|
      ids = accessible_owner_ids(resource)
      ids.nil? ? scope : scope.where(admin_user_id: ids)
    end
  end

  def record_allowed_admin_access
    return unless current_admin_user
    return if @access_audit_denied
    return if request.format.json?
    return unless response.successful? || (!request.get? && response.status < 400)
    return unless SENSITIVE_ACCESS_AUDIT_CONTROLLERS.include?(controller_path)

    AccessAuditLog.log!(
      event_type: "sensitive_access",
      result: "allowed",
      request: request,
      admin_user: current_admin_user,
      reason: "Acesso permitido a área sensível",
      metadata: {
        response_status: response.status,
        format: request.format&.symbol
      }.compact
    )
  end

  # Retorna scope do usuário para o recurso ("own", "team" ou "all").
  def scope_for_resource(resource)
    current_admin_user&.scope_for(resource) || "own"
  end

  def owns_all_resource?(resource)
    current_admin_user&.owns_all?(resource)
  end

  # IDs do próprio usuário + subárvore (equipe).
  def team_scope_ids
    current_admin_user&.team_scope_ids || []
  end

  # Mostra o toggle "+ equipe"? Só quando o perfil tem escopo "team" para o recurso
  # E o usuário tem subordinados na árvore de gestão.
  def team_available?(resource)
    return false unless current_admin_user
    current_admin_user.can_view_team?(resource) && current_admin_user.descendant_ids.any?
  end

  # Estado efetivo do toggle. Opt-out: ligado por padrão quando disponível;
  # só desliga quando o usuário envia explicitamente team=0.
  def include_team?(resource)
    return false unless team_available?(resource)
    params[:team].to_s != "0"
  end

  # IDs dos donos visíveis para o recurso. nil = sem filtro (vê tudo, escopo "all"/admin).
  def visible_owner_ids(resource)
    return nil if owns_all_resource?(resource)
    return team_scope_ids if include_team?(resource)
    [current_admin_user&.id].compact
  end

  # Conjunto de owner-ids que o usuário pode ACESSAR (nível de registro), ignorando o
  # toggle "+ equipe" (que é só recorte de listagem). nil = sem restrição (escopo total).
  def accessible_owner_ids(resource)
    return nil if owns_all_resource?(resource)
    current_admin_user&.can_view_team?(resource) ? team_scope_ids : [current_admin_user&.id].compact
  end

  # O usuário pode acessar um registro cujo dono é um dos owner_ids?
  def owner_in_scope?(resource, *owner_ids)
    allowed = accessible_owner_ids(resource)
    return true if allowed.nil?
    ids = owner_ids.flatten.compact.map(&:to_i)
    ids.intersect?(allowed)
  end

  def restrict_owner_param_to_scope!(attrs, resource, key: :admin_user_id)
    value = attrs[key]
    return attrs if value.blank?
    return attrs if owner_in_scope?(resource, value)

    attrs.delete(key)
    attrs
  end

  helper_method :can?, :scope_for_resource, :owns_all_resource?,
                :team_scope_ids, :team_available?, :include_team?,
                :impersonating_admin_user?, :impersonation_admin_user,
                :can_review_captacao?, :manager_team_user_ids

  def can?(action, resource)
    current_admin_user&.can?(action, resource)
  end

  # Equipe do gestor = própria subárvore recursiva (team_scope_ids), ainda recortada
  # por tipo de atuação (venda/locação) quando o gestor não é "both".
  def manager_team_user_ids
    return [] unless current_admin_user

    ids = current_admin_user.team_scope_ids
    return ids if current_admin_user.both?

    current_tenant.admin_users.where(id: ids, acting_type: manager_allowed_acting_types).pluck(:id)
  end

  def manager_allowed_acting_types
    case current_admin_user&.acting_type
    when "sales" then AdminUser.acting_types.values_at("sales", "both")
    when "rentals" then AdminUser.acting_types.values_at("rentals", "both")
    else AdminUser.acting_types.values
    end
  end

  # A permissão "review" de captações respeita o escopo do perfil:
  # "all" revisa a conta inteira; "team" revisa apenas captações da própria
  # hierarquia de gestão (captador ou corretor designado na equipe); "own",
  # apenas as próprias.
  def can_review_captacao?(habitation)
    return false unless can?(:review, :captacoes)
    return true if tenant_owner? || owns_all_resource?(:captacoes)
    return false unless habitation
    return true if habitation.admin_user_id == current_admin_user&.id
    return false unless current_admin_user&.can_view_team?(:captacoes)

    team_ids = manager_team_user_ids
    return false if team_ids.blank?

    habitation.admin_user_id.in?(team_ids) || habitation.broker_assignments.exists?(admin_user_id: team_ids)
  end

  def impersonation_admin_user
    impersonator_id = session[:impersonator_admin_user_id]
    return nil if impersonator_id.blank?

    @impersonation_admin_user ||= AdminUser.find_by(id: impersonator_id)
  end

  def impersonating_admin_user?
    impersonation_admin_user.present? &&
      current_admin_user.present? &&
      current_admin_user.id != impersonation_admin_user.id
  end
end
