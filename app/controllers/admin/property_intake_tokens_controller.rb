class Admin::PropertyIntakeTokensController < Admin::BaseController
  requires_permission :manage, :integracoes
  before_action :require_account_admin!

  def show
    @token_version = token_version
  end

  def create
    issue_token(replace: false)
  end

  def update
    issue_token(replace: true)
  end

  def destroy
    revoked = current_tenant.with_lock do
      current_tenant.update!(property_intake_token_digest: nil) if current_version?
    end
    return token_changed unless revoked

    redirect_to admin_property_intake_token_path, notice: "Token Bearer revogado.", status: :see_other
  end

  private

  def require_account_admin!
    raise PermissionDenied unless property_intake_token_admin?
  end

  def token_version
    digest = current_tenant.property_intake_token_digest
    Digest::SHA256.hexdigest(digest) if digest.present?
  end

  def current_version?
    version = token_version
    version.present? && version == params[:token_version]
  end

  def token_changed
    redirect_to admin_property_intake_token_path,
                alert: "A situação do token mudou. Confira antes de tentar novamente.", status: :see_other
  end

  def issue_token(replace:)
    @issued_token = current_tenant.with_lock do
      allowed = replace ? current_version? : token_version.nil?
      next unless allowed

      token = SecureRandom.hex(32)
      current_tenant.update!(property_intake_token_digest: Digest::SHA256.hexdigest(token))
      @token_version = token_version
      token
    end

    return token_changed unless @issued_token

    render :show
  end
end
