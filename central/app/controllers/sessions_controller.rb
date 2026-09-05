class SessionsController < ApplicationController
  skip_before_action :require_staff!
  before_action :activation_staff, only: [:edit, :update]
  def new; end
  def create
    staff = Staff.find_by(email: params[:email].to_s.strip.downcase, active: true)
    if staff&.email_verification?
      return create_email_challenge(staff)
    end
    ok = false
    if staff
      staff.with_lock do
        if staff.activated_at && !staff.locked_until&.future? && staff.authenticate(params[:password].to_s) && staff.verify_otp!(params[:code])
          staff.update!(failed_attempts: 0, locked_until: nil)
          ok = true
        else
          count = staff.failed_attempts + 1
          staff.update!(failed_attempts: count, locked_until: count >= 5 ? 15.minutes.from_now : nil)
        end
      end
    end
    unless ok
      flash.now[:alert] = "Dados inválidos ou acesso temporariamente bloqueado."
      return render :new, status: :unprocessable_entity
    end
    finish_login(staff)
  end
  def verify
    @staff = pending_email_staff
    redirect_to login_path, alert: "Entre novamente para receber um código." unless @staff
  end

  def verify_email
    @staff = pending_email_staff
    return redirect_to login_path, alert: "Entre novamente para receber um código." unless @staff
    if @staff.verify_email_code!(params[:code], session[:email_challenge])
      finish_login(@staff)
    else
      flash.now[:alert] = "Código inválido ou expirado. Confira seu e-mail ou entre novamente para receber outro."
      render :verify, status: :unprocessable_entity
    end
  end

  def destroy
    current_staff_session&.finish!("logout")
    reset_session
    redirect_to login_path
  end
  def edit
    return if @staff.email_verification?
    @qr = RQRCode::QRCode.new(ROTP::TOTP.new(@staff.otp_secret, issuer: "Unitymob Central").provisioning_uri(@staff.email)).as_svg(module_size: 4)
  end
  def update
    @staff.with_lock do
      return head :gone unless @staff.activation_expires_at&.future? && @staff.activation_digest == Digest::SHA256.hexdigest(params[:token].to_s)
      @staff.assign_attributes(params.permit(:password, :password_confirmation))
      stamp = @staff.email_verification? ? true : ROTP::TOTP.new(@staff.otp_secret).verify(params[:code].to_s, drift_behind: 30, after: @staff.otp_consumed_at)
      if @staff.valid? && params[:password].present? && stamp
        @staff.update!(activated_at: Time.current, activation_digest: nil, activation_expires_at: nil, otp_consumed_at: stamp == true ? nil : stamp)
        return redirect_to login_path, notice: "Acesso ativado. Entre com sua senha e o próximo código do aplicativo."
      end
    end
    @staff.reload
    edit
    flash.now[:alert] = "Confira a senha (mínimo 12 caracteres), confirmação e código."
    render :edit, status: :unprocessable_entity
  end
  private
  def finish_login(staff)
    current_staff_session&.finish!("replaced")
    reset_session
    tracked = StaffSession.create!(staff: staff, role: staff.role, started_at: Time.current, expires_at: 8.hours.from_now, last_activity_at: Time.current)
    session[:staff_session_id] = tracked.id
    session[:staff_id] = staff.id
    session[:staff_version] = staff.session_version
    session[:staff_expires_at] = 8.hours.from_now.to_i
    redirect_to root_path
  end

  def pending_email_staff
    return nil unless session[:email_challenge_expires_at].to_i > Time.current.to_i
    Staff.find_by(id: session[:email_staff_id], session_version: session[:email_staff_version], active: true, verification_method: "email")
  end

  def create_email_challenge(staff)
    challenge = nil
    staff.with_lock do
      if staff.activated_at && !staff.locked_until&.future? && staff.authenticate(params[:password].to_s)
        staff.update!(failed_attempts: 0, locked_until: nil)
        challenge = staff.issue_email_code!
      else
        count = staff.failed_attempts + 1
        staff.update!(failed_attempts: count, locked_until: count >= 5 ? 15.minutes.from_now : nil)
        flash.now[:alert] = "Dados inválidos ou acesso temporariamente bloqueado."
        return render :new, status: :unprocessable_entity
      end
    end
    unless challenge
      return redirect_to verify_login_path if pending_email_staff&.id == staff.id
      flash.now[:alert] = "Aguarde um minuto antes de solicitar outro código."
      return render :new, status: :too_many_requests
    end
    code, nonce = challenge
    # Entrega síncrona e limitada por timeout; evita guardar OTP em argumentos de jobs/logs.
    LoginMailer.verification(staff, code).deliver_now
    reset_session
    session[:email_staff_id] = staff.id
    session[:email_staff_version] = staff.session_version
    session[:email_challenge] = nonce
    session[:email_challenge_expires_at] = 10.minutes.from_now.to_i
    redirect_to verify_login_path, notice: "Enviamos um código para seu e-mail."
  rescue Net::SMTPError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
    staff.update_columns(email_code_digest: nil, email_challenge_digest: nil, email_code_expires_at: nil)
    flash.now[:alert] = "Não foi possível enviar o código. Tente novamente em um minuto."
    render :new, status: :service_unavailable
  end

  def activation_staff
    @staff = Staff.find_by!(activation_digest: Digest::SHA256.hexdigest(params[:token].to_s), active: true)
    head :gone unless @staff.activation_expires_at&.future?
  end
end
