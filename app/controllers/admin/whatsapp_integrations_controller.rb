class Admin::WhatsappIntegrationsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :integracoes) }

  DEFAULT_EMBEDDED_SIGNUP_CONFIG_ID = "1980983762681491".freeze
  META_LEADS_CONFIG_ID = "1330907151751153".freeze

  def show
    return redirect_to admin_meta_integrations_path if params[:tab] == "forms"

    load_page_state
  end

  def embedded_signup_callback
    integration = current_whatsapp_integration
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
    current_whatsapp_integration.update!(
      status: "failed",
      last_event: callback_params[:event].presence || "ERROR",
      last_error_message: e.message,
      signup_payload: safe_payload
    )
    render json: { ok: false, message: e.message }, status: :unprocessable_content
  end

  def update
    integration = current_whatsapp_integration

    if integration.update(webhook_settings_params)
      redirect_to admin_whatsapp_integration_path, notice: "Webhook do WhatsApp atualizado."
    else
      load_page_state
      @webhook_settings_errors = integration.errors.full_messages
      render :show, status: :unprocessable_content
    end
  end

  # Conexão manual via credenciais de System User / Cloud API (sem Embedded Signup).
  # Útil para apenas notificar/enviar mensagens, igual ao NL.
  def manual_connection
    integration = current_whatsapp_integration
    attrs = manual_connection_params
    # Campos sensíveis em branco => mantém o atual (não sobrescreve credencial já salva).
    attrs.delete(:access_token) if attrs[:access_token].blank?
    attrs.delete(:app_secret) if attrs[:app_secret].blank?
    integration.assign_attributes(attrs)

    if integration.access_token.present? && integration.phone_number_id.present?
      integration.status = "connected"
      integration.last_event = "MANUAL"
      integration.last_error_code = nil
      integration.last_error_message = nil
      integration.connected_by_admin_user = current_admin_user
      integration.connected_at ||= Time.current
    end

    if integration.save
      redirect_to admin_whatsapp_integration_path, notice: "Conexão manual do WhatsApp salva."
    else
      load_page_state
      @manual_connection_errors = integration.errors.full_messages
      render :show, status: :unprocessable_content
    end
  end

  # Testa conexão real contra a Graph API: envio (consulta o número) e recebimento
  # (apps inscritos no webhook da WABA). Não envia mensagem.
  def test_connection
    client = Whatsapp::CloudClient.new(current_whatsapp_integration)

    unless client.configured?
      return render json: { ok: false, message: "Configure Access Token e Phone Number ID antes de testar." }, status: :unprocessable_content
    end

    phone = client.phone_info
    subs = client.subscribed_apps
    subscribed = Array(subs.dig(:data, "data"))

    render json: {
      ok: phone[:ok],
      send: {
        ok: phone[:ok],
        label: phone.dig(:data, "display_phone_number").presence || phone.dig(:data, "verified_name"),
        error: phone[:error]
      },
      receive: {
        ok: subs[:ok] && subscribed.any?,
        error: subs[:error],
        apps: subscribed.filter_map { |app| app.dig("whatsapp_business_api_data", "name") }
      }
    }
  end

  # Envia uma mensagem de texto de teste pelo número conectado.
  def send_test
    to = params[:to].to_s.strip
    return render json: { ok: false, message: "Informe um número (ex.: 5547999999999)." }, status: :unprocessable_content if to.blank?

    result = Whatsapp::CloudClient.new(current_whatsapp_integration).send_text(
      to: to,
      body: params[:body].presence || "Teste de conexão do CRM ✅"
    )

    if result[:ok]
      render json: { ok: true, message: "Mensagem enviada com sucesso (id #{result[:message_id]})." }
    else
      render json: { ok: false, message: result[:error].presence || "Falha ao enviar a mensagem." }, status: :unprocessable_content
    end
  end

  def sync_notification_templates
    integration = current_whatsapp_integration

    unless integration.messaging_ready? && integration.waba_id.present?
      redirect_to admin_whatsapp_integration_path, alert: "Configure o número fixo das notificações antes de sincronizar templates."
      return
    end

    result = Whatsapp::SyncTemplatesJob.perform_now(current_tenant.id)
    if result[:ok]
      redirect_to admin_whatsapp_integration_path, notice: "#{result[:synced]} template(s) sincronizado(s) do número das notificações."
    else
      redirect_to admin_whatsapp_integration_path, alert: result[:error].presence || "Não foi possível sincronizar os templates das notificações."
    end
  end

  def disconnect
    current_whatsapp_integration.update!(
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
    integration = current_whatsapp_integration

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
    @whatsapp_integration = current_whatsapp_integration
    @whatsapp_transport = Notifications::TransportResolver.whatsapp(current_tenant)
    @whatsapp_using_global = @whatsapp_transport&.global?
    @whatsapp_effective_ready = @whatsapp_transport.present?
    @site_phone_settings = @whatsapp_integration.site_phone_settings
    @embedded_signup_config_id = embedded_signup_config_id
    @diagnostics = diagnostics
    @default_webhook_callback_url = default_webhook_callback_url
    @webhook_callback_url = @whatsapp_integration.webhook_callback_url.presence || @default_webhook_callback_url
    @webhook_verify_token = @whatsapp_integration.webhook_verify_token!
    @phone_info = whatsapp_phone_info
    @whatsapp_sender_numbers = campaign_sender_numbers
    @new_whatsapp_sender_number = current_tenant.whatsapp_sender_numbers.new
    @notification_template_settings = current_tenant.notification_template_settings.includes(:whatsapp_template).ordered
    @new_notification_template_setting = current_tenant.notification_template_settings.new(
      channel: "whatsapp",
      purpose: "lead_distribution_broker",
      active: true
    )
    @notification_template_purpose_options = NotificationTemplateSetting.purpose_options
    @notification_template_options = notification_template_options
  end

  def notification_template_options
    scope = current_tenant.whatsapp_templates.approved
    scope = scope.where(waba_id: @whatsapp_integration.waba_id) if @whatsapp_integration&.waba_id.present?

    scope.ordered.map do |template|
      label = "#{template.name} · #{template.language.presence || 'pt_BR'} · #{template.variable_count} variáveis"
      [label, template.id]
    end
  end

  def campaign_sender_numbers
    scope = current_tenant.whatsapp_sender_numbers.active
    notification_phone_id = @whatsapp_integration.phone_number_id.to_s.presence
    scope = scope.where.not(phone_number_id: notification_phone_id) if notification_phone_id
    scope.ordered
  end

  # Snapshot do número (display, nome verificado, quality) vindo da Cloud API.
  # Cacheado por alguns minutos para não bater na Graph a cada carregamento.
  def whatsapp_phone_info
    return nil unless @whatsapp_integration.messaging_ready?

    Rails.cache.fetch("whatsapp_phone_info/#{@whatsapp_integration.id}", expires_in: 10.minutes, skip_nil: true) do
      result = Whatsapp::CloudClient.new(@whatsapp_integration).phone_info
      next nil unless result[:ok]

      {
        number: result.dig(:data, "display_phone_number"),
        name: result.dig(:data, "verified_name"),
        quality: result.dig(:data, "quality_rating")
      }
    end
  rescue StandardError
    nil
  end

  def default_webhook_callback_url
    webhooks_whatsapp_url(host: request.host_with_port, protocol: request.protocol.delete("://"))
  rescue StandardError
    "#{request.base_url}/webhooks/whatsapp"
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

  def current_whatsapp_integration
    @current_whatsapp_integration ||= WhatsappBusinessIntegration.current(current_tenant)
  end

  def manual_connection_params
    params.require(:whatsapp_business_integration).permit(
      :access_token,
      :phone_number_id,
      :waba_id,
      :business_id,
      :app_secret
    )
  end

  def webhook_settings_params
    params.require(:whatsapp_business_integration).permit(
      :webhook_callback_url,
      :webhook_verify_token
    )
  end

  def phone_settings_params
    params.require(:whatsapp_business_integration).permit(
      :allow_photo_presentation,
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
