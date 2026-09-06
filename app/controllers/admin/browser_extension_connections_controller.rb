class Admin::BrowserExtensionConnectionsController < Admin::BaseController
  prepend_before_action :remember_extension_login!, only: :new
  prepend_before_action :require_completed_login!
  before_action :allow_extension_connection!

  def new
    @challenge = params[:challenge].to_s
    @extension_id = params[:extension_id].to_s
    unless @challenge.match?(/\A[0-9a-f]{64}\z/) && BrowserExtensionGrant.allowed_extension?(@extension_id)
      return head :bad_request
    end

    session[:browser_extension_pairing] = { challenge: @challenge, extension_id: @extension_id, expires_at: 5.minutes.from_now.to_i }
    session.delete(:browser_extension_login_return)
    @page_title = "Conectar extensão Unitymob"
  end

  def create
    pairing = session.delete(:browser_extension_pairing)&.with_indifferent_access
    unless pairing && pairing[:expires_at].to_i > Time.current.to_i &&
        pairing[:challenge] == params[:challenge] && pairing[:extension_id] == params[:extension_id] &&
        BrowserExtensionGrant.allowed_extension?(pairing[:extension_id])
      return head :unprocessable_entity
    end

    access = AccessControl::Policy.call(admin_user: current_admin_user, request: request, controller: self)
    return head :forbidden unless access.allowed?

    grant = BrowserExtensionGrant.create!(
      tenant: current_tenant, admin_user: current_admin_user, trusted_device: access.device,
      extension_id: pairing[:extension_id], challenge_digest: pairing[:challenge],
      challenge_expires_at: 5.minutes.from_now, expires_at: 8.hours.from_now
    )
    callback = "https://#{grant.extension_id}.chromiumapp.org/unitymob"
    code = grant.signed_id(purpose: :browser_extension_pairing, expires_in: 5.minutes)
    redirect_to "#{callback}?#{ { login_token: code, state: pairing[:challenge], issuer: request.base_url }.to_query }", allow_other_host: true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    head :unprocessable_entity
  end

  def index
    @grants = BrowserExtensionGrant.where(tenant: current_tenant, admin_user: current_admin_user)
      .where(revoked_at: nil).where("expires_at > ?", Time.current).order(created_at: :desc).limit(30)
    @page_title = "Extensão Unitymob"
  end

  def destroy
    grant = BrowserExtensionGrant.where(tenant: current_tenant, admin_user: current_admin_user).find(params[:id])
    grant.update!(revoked_at: Time.current)
    redirect_to admin_browser_extension_connections_path, notice: "Acesso da extensão revogado."
  end

  private

  def remember_extension_login!
    challenge = params[:challenge].to_s
    extension_id = params[:extension_id].to_s
    return unless challenge.match?(/\A[0-9a-f]{64}\z/) && BrowserExtensionGrant.allowed_extension?(extension_id)

    session[:browser_extension_login_return] = { challenge: challenge, extension_id: extension_id, expires_at: 5.minutes.from_now.to_i }
  end

  def require_completed_login!
    head :forbidden if session[:otp_pending_id].present?
  end

  def allow_extension_connection!
    return head :forbidden if impersonating_admin_user? || !current_admin_user.active?
    return if action_name.in?(%w[index destroy])
    return head :forbidden unless BrowserExtensionGrant.enabled_for?(current_tenant)

    check_permission!(:view, :leads)
  end
end
