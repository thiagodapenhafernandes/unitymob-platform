class Admin::WhatsappIntegrationsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :integracoes) }

  DEFAULT_EMBEDDED_SIGNUP_CONFIG_ID = "1980983762681491".freeze
  META_LEADS_CONFIG_ID = "1330907151751153".freeze

  def show
    return redirect_to admin_meta_integrations_path if params[:tab] == "forms"

    load_page_state
  end

  def embedded_signup_callback
    integration = WhatsappBusinessIntegration.current
    payload = callback_params
    event = payload[:event].to_s
    session_info = payload[:session_info].to_h

    if successful_event?(event)
      ensure_signup_ids!(session_info)
      token_info = Facebook::WhatsappEmbeddedSignupService.new(code: payload[:code]).exchange_code!
      integration.update!(
        waba_id: session_info["waba_id"],
        phone_number_id: session_info["phone_number_id"],
        business_id: session_info["business_id"],
        access_token: token_info["access_token"],
        token_expires_at: token_expiration(token_info),
        status: "connected",
        last_event: event,
        last_error_code: nil,
        last_error_message: nil,
        meta_session_id: session_info["session_id"],
        signup_payload: safe_payload,
        connected_by_admin_user: current_admin_user,
        connected_at: Time.current
      )

      render json: { ok: true, message: "WhatsApp conectado com sucesso." }
    else
      error_message = callback_error_message(event, session_info)
      integration.update!(
        status: event == "CANCEL" ? "canceled" : "failed",
        last_event: event.presence || "ERROR",
        last_error_code: session_info["error_code"],
        last_error_message: error_message,
        meta_session_id: session_info["session_id"],
        signup_payload: safe_payload
      )

      render json: { ok: false, message: error_message }, status: :unprocessable_content
    end
  rescue Facebook::WhatsappEmbeddedSignupService::Error => e
    WhatsappBusinessIntegration.current.update!(
      status: "failed",
      last_event: callback_params[:event].presence || "ERROR",
      last_error_message: e.message,
      signup_payload: safe_payload
    )
    render json: { ok: false, message: e.message }, status: :unprocessable_content
  end

  def disconnect
    WhatsappBusinessIntegration.current.update!(
      status: "disconnected",
      access_token: nil,
      last_event: "DISCONNECT",
      last_error_code: nil,
      last_error_message: nil,
      connected_at: nil
    )

    redirect_to admin_whatsapp_integration_path, notice: "Conexão WhatsApp removida."
  end

  def phone_settings
    integration = WhatsappBusinessIntegration.current

    if integration.update(phone_settings_params)
      redirect_to admin_whatsapp_integration_path(tab: "site_phones"), notice: "Telefones do site atualizados."
    else
      load_page_state
      @phone_settings_errors = integration.errors.full_messages
      render :show, status: :unprocessable_content
    end
  end

  private

  def load_page_state
    @whatsapp_integration = WhatsappBusinessIntegration.current
    @site_phone_settings = @whatsapp_integration.site_phone_settings
    @embedded_signup_config_id = embedded_signup_config_id
    @diagnostics = diagnostics
  end

  def embedded_signup_config_id
    ENV["WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID"].presence || DEFAULT_EMBEDDED_SIGNUP_CONFIG_ID
  end

  def diagnostics
    [
      diagnostic_item("FACEBOOK_APP_ID", ENV["FACEBOOK_APP_ID"].present?),
      diagnostic_item("FACEBOOK_APP_SECRET ou WHATSAPP_APP_SECRET", ENV["FACEBOOK_APP_SECRET"].present? || ENV["WHATSAPP_APP_SECRET"].present?),
      diagnostic_item("WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID", ENV["WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID"].present?, fallback: DEFAULT_EMBEDDED_SIGNUP_CONFIG_ID),
      diagnostic_item("Domínio HTTPS", ENV["APP_HOST"].to_s.start_with?("https://"), detail: ENV["APP_HOST"].presence || "APP_HOST não configurado")
    ]
  end

  def diagnostic_item(label, ok, fallback: nil, detail: nil)
    {
      label: label,
      ok: ok,
      fallback: fallback,
      detail: detail
    }
  end

  def callback_params
    permitted = params.permit(
      :code,
      :event,
      session_info: {},
      raw: {},
      whatsapp_integration: [
        :code,
        :event,
        { session_info: {}, raw: {} }
      ]
    ).to_h

    top_level = permitted.slice("code", "event", "session_info", "raw")
    wrapped = permitted.fetch("whatsapp_integration", {})
    top_level.merge(wrapped) { |_key, top_value, wrapped_value| wrapped_value.presence || top_value }.with_indifferent_access
  end

  def phone_settings_params
    params.require(:whatsapp_business_integration).permit(
      :default_whatsapp_number,
      :sale_whatsapp_number,
      :rent_whatsapp_number,
      :sale_rent_whatsapp_number,
      :sale_requires_lead_form,
      :rent_requires_lead_form,
      :sale_rent_requires_lead_form
    )
  end

  def safe_payload
    callback_params.to_h.except("code")
  end

  def callback_error_message(event, session_info)
    return "Conexão cancelada na Meta em #{session_info['current_step']}." if event == "CANCEL" && session_info["current_step"].present?
    return "Conexão cancelada na Meta." if event == "CANCEL"

    session_info["error_message"].presence ||
      session_info["current_step"].presence ||
      "A Meta retornou erro no Embedded Signup sem enviar detalhes. Verifique se a configuração WABA, domínio e permissões do app estão aprovados."
  end

  def successful_event?(event)
    event.to_s.start_with?("FINISH")
  end

  def ensure_signup_ids!(session_info)
    return if session_info["waba_id"].present? && session_info["phone_number_id"].present?

    raise Facebook::WhatsappEmbeddedSignupService::Error, "A Meta não retornou WABA ID e Phone Number ID para concluir a conexão."
  end

  def token_expiration(token_info)
    expires_in = token_info["expires_in"].to_i
    expires_in.positive? ? Time.current + expires_in.seconds : nil
  end
end
