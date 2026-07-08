class Admin::TwoFactorSettingsController < Admin::BaseController
  # Tela do PRÓPRIO usuário (sem check_permission!): qualquer um pode proteger
  # a própria conta — inclusive usuários field-only.
  skip_before_action :enforce_two_factor_setup!, raise: false

  def show
    @otp_enabled = current_admin_user.otp_enabled?
    unless @otp_enabled
      unless current_admin_user.has_attribute?(:otp_secret)
        redirect_to admin_root_path, alert: "Verificação em duas etapas indisponível: migração pendente."
        return
      end
      session[:otp_setup_secret] ||= ROTP::Base32.random
      @pending_secret = session[:otp_setup_secret]
      @provisioning_uri = ROTP::TOTP.new(@pending_secret, issuer: current_admin_user.otp_issuer)
                                    .provisioning_uri(current_admin_user.email)
      @qr_svg = RQRCode::QRCode.new(@provisioning_uri).as_svg(module_size: 4, viewbox: true, use_path: true)
    end
    @backup_codes_remaining = Array(current_admin_user.otp_backup_codes).size if @otp_enabled
  end

  # Confirma o código lido do app e LIGA o 2FA (+ backup codes exibidos 1x).
  def create
    secret = session[:otp_setup_secret]
    if secret.blank?
      redirect_to admin_two_factor_settings_path, alert: "Sessão de configuração expirou. Escaneie o QR novamente."
      return
    end

    code = params[:otp_code].to_s.gsub(/\s+/, "")
    if ROTP::TOTP.new(secret).verify(code, drift_behind: 30)
      current_admin_user.update!(otp_secret: secret, otp_enabled_at: Time.current)
      @backup_codes = current_admin_user.generate_backup_codes!
      session.delete(:otp_setup_secret)
      AccessAuditLog.log!(event_type: "two_factor_enabled", result: "allowed", request: request,
                          admin_user: current_admin_user, reason: "2FA ativado pelo usuário")
      render :backup_codes
    else
      redirect_to admin_two_factor_settings_path, alert: "Código inválido — confira o aplicativo e tente de novo."
    end
  end

  # Desativa (exige senha; bloqueado quando a conta exige 2FA).
  def destroy
    if current_admin_user.two_factor_required?
      redirect_to admin_two_factor_settings_path, alert: "Esta conta exige verificação em duas etapas — não é possível desativar."
      return
    end

    unless current_admin_user.valid_password?(params[:current_password].to_s)
      redirect_to admin_two_factor_settings_path, alert: "Senha atual incorreta."
      return
    end

    current_admin_user.update!(otp_secret: nil, otp_enabled_at: nil, otp_backup_codes: [], otp_consumed_timestep: nil)
    AccessAuditLog.log!(event_type: "two_factor_disabled", result: "allowed", request: request,
                        admin_user: current_admin_user, reason: "2FA desativado pelo usuário")
    redirect_to admin_two_factor_settings_path, notice: "Verificação em duas etapas desativada."
  end

  # Novo conjunto de backup codes (exige um código TOTP válido).
  def regenerate_backup_codes
    unless current_admin_user.verify_totp!(params[:otp_code].to_s)
      redirect_to admin_two_factor_settings_path, alert: "Código inválido — é preciso um código atual do aplicativo."
      return
    end

    @backup_codes = current_admin_user.generate_backup_codes!
    AccessAuditLog.log!(event_type: "two_factor_enabled", result: "allowed", request: request,
                        admin_user: current_admin_user, reason: "Backup codes regenerados",
                        metadata: { backup_codes_regenerated: true })
    render :backup_codes
  end
end
