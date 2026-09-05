class SessionsController < ApplicationController
  skip_before_action :require_staff!
  before_action :activation_staff, only: [:edit, :update]
  def new; end
  def create
    staff = Staff.find_by(email: params[:email].to_s.strip.downcase, active: true)
    session.delete(:totp_staff_id)
    if staff&.email_verification?
      return create_email_challenge(staff)
    end
    error = "E-mail ou senha incorretos. Confira os dados e tente novamente."
    if staff
      staff.with_lock do
        if staff.locked_until&.future?
          error = lock_message(staff)
        elsif !staff.authenticate(params[:password].to_s)
          register_login_failure(staff)
          error = lock_message(staff) if staff.locked_until&.future?
        elsif !staff.activated_at
          error = "Seu acesso ainda não foi ativado. Abra o link de ativação e conclua o cadastro da senha e do autenticador."
        else
          reset_session
          session[:totp_staff_id] = staff.id
          session[:totp_version] = staff.session_version
          session[:totp_expires_at] = 10.minutes.from_now.to_i
          return redirect_to verify_authenticator_path
        end
      end
    end
    flash.now[:alert] = error
    render :new, status: :unprocessable_entity
  end

  def authenticator
    @staff = pending_totp_staff
    redirect_to login_path, alert: "A verificação expirou. Informe seu e-mail e senha novamente." unless @staff
  end

  def verify_authenticator
    @staff = pending_totp_staff
    return redirect_to login_path, alert: "A verificação expirou. Informe seu e-mail e senha novamente." unless @staff
    ok = false
    @staff.with_lock do
      if @staff.locked_until&.future?
        flash.now[:alert] = lock_message(@staff)
      elsif @staff.verify_otp!(params[:code].to_s.strip)
        @staff.update!(failed_attempts: 0, locked_until: nil)
        ok = true
      else
        register_login_failure(@staff)
        flash.now[:alert] = @staff.locked_until&.future? ? lock_message(@staff) : "Código inválido, expirado ou já utilizado. Aguarde um novo código no aplicativo e tente novamente."
      end
    end
    return finish_login(@staff) if ok
    render :authenticator, status: :unprocessable_entity
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
  def pending_totp_staff
    return unless session[:totp_expires_at].to_i > Time.current.to_i
    Staff.where.not(activated_at: nil).find_by(id: session[:totp_staff_id], session_version: session[:totp_version], active: true, verification_method: "totp")
  end

  def register_login_failure(staff)
    count = staff.locked_until ? 1 : staff.failed_attempts + 1
    staff.update!(failed_attempts: count, locked_until: count >= 5 ? 15.minutes.from_now : nil)
  end

  def lock_message(staff)
    minutes = [(staff.locked_until - Time.current).fdiv(60).ceil, 1].max
    "Acesso bloqueado temporariamente após várias tentativas. Tente novamente em #{minutes} #{minutes == 1 ? 'minuto' : 'minutos'}."
  end

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
        register_login_failure(staff) unless staff.locked_until&.future?
        flash.now[:alert] = staff.locked_until&.future? ? lock_message(staff) : "E-mail ou senha incorretos, ou ativação pendente. Confira os dados e seu link de ativação."
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
