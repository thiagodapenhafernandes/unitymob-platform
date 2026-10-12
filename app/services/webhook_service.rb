class WebhookService
  include HTTParty
  
  TIMEOUT = 5 # segundos

  class << self
    # Envia dados de formulário para o webhook configurado
    # @param origin_form [String] Identificador do formulário (ex: 'contact_form')
    # @param data [Hash] Dados do formulário
    # @param options [Hash] Opções adicionais (ex: :url para override)
    # @return [Boolean] true se ao menos um envio foi disparado
    #
    # O POST roda em background (WebhookDeliveryJob, com retry/backoff no
    # ActiveJob) para não segurar a thread do request/worker. O payload é
    # montado aqui porque options[:request] só existe durante o request.
    def send_form_data(origin_form, data, options = {})
      # If specific URL is provided (e.g. testing), just use that
      if options[:url].present?
        payload = build_payload(origin_form, data, options)
        # O teste do admin precisa do resultado imediato para o feedback na
        # tela; os demais destinos vão para a fila.
        return deliver(options[:url], payload)[:success] if origin_form.to_s == "test_webhook"

        WebhookDeliveryJob.perform_later(options[:url].to_s, payload)
        return true
      end

      tenant = options[:tenant] || Current.tenant
      return false unless tenant

      active_settings = tenant.webhook_settings.active.select do |setting|
        event = WebhookSetting.event_name_for(origin_form, data)
        setting.delivers_event?(event) &&
          (%w[lead_stage_changed lead_qualification_changed qualified_lead].include?(event) || setting.delivers_form?(origin_form, public_form: options[:public_form]))
      end
      return false if active_settings.empty?

      payload = build_payload(origin_form, data, options)
      results = active_settings.map do |setting|
        # Prioritize WhatsApp URL if present (legacy behavior preservation)
        # or maybe we should send to both if both exist?
        # The previous code was: target_url = whatsapp_webhook_url.presence || webhook_url
        # This implies "use WhatsApp URL if set, otherwise standard URL".
        # I will keep this logic for now.
        target_url = setting.whatsapp_webhook_url.presence || setting.webhook_url
        next false if target_url.blank?

        WebhookDeliveryJob.perform_later(target_url, payload)
        true
      end

      results.any?
    end

    # Entrega única (tentativa individual, sem retry interno — retry/backoff
    # ficam no WebhookDeliveryJob). Nunca levanta exceção.
    # @return [Hash] { success: Boolean, status: Integer|nil, error: String|nil }
    def deliver(url, payload)
      body = payload.to_json
      response = HTTParty.post(
        url,
        body: body,
        headers: {
          'Content-Type' => 'application/json',
          'User-Agent' => 'Unitymob-Webhook/1.0'
        }.merge(signature_headers(body)),
        timeout: TIMEOUT
      )

      if response.success?
        { success: true, status: response.code, error: nil }
      else
        { success: false, status: response.code, error: "HTTP #{response.code}" }
      end
    rescue StandardError => e
      { success: false, status: nil, error: "#{e.class}: #{e.message}" }
    end

    private
    
    def build_payload(origin_form, data, options = {})
      values = data.to_h.with_indifferent_access
      attribution = values[:attribution_data].is_a?(Hash) ? values[:attribution_data].with_indifferent_access : {}.with_indifferent_access
      values = attribution.merge(values.reject { |key, value| value.nil? || (Leads::Attribution::TRACKING_KEYS.include?(key.to_s) && value.blank?) })
      request = options[:request]
      now = Time.current
      event_name = WebhookSetting.event_name_for(origin_form, values)
      event_id = SecureRandom.uuid
      tracking = tracking_params(request, values)
      lead_event = !%w[form_submitted test_webhook].include?(event_name)
      tenant = options[:tenant] || Current.tenant
      property = tenant.habitations.find_by(id: values[:property_id]) if lead_event && tenant && values[:property_code].blank? && values[:property_id].present? && values[:tenant_id].to_s == tenant.id.to_s
      property_code = values[:property_code].presence || property&.codigo
      {
        origin_form: origin_form,
        timestamp: now.iso8601,
        event_name: event_name,
        event_id: event_id,
        transaction_id: event_id,
        event_timestamp: now.to_i,
        action_source: request ? "website" : "system_generated",
        legal_bases: Privacy::LegalBases.for_information(values[:other_information]),
        lead_id: event_name != "form_submitted" && event_name != "test_webhook" ? values[:id]&.to_s : nil,
        business_type: { "sale" => "venda", "rent" => "locacao" }.fetch(values[:business_type].to_s, values[:business_type]),
        value: values[:value],
        currency: values[:value].present? ? (values[:currency].presence || "BRL") : nil,
        user_data: lead_event ? lead_user_data(values) : nil,
        property_id: property_code&.to_s,
        property_code: property_code,
        placement: values[:placement],
        client_ip_address: request ? request.remote_ip : values[:client_ip_address],
        client_user_agent: request ? request.user_agent : values[:client_user_agent],
        source: source_metadata(request, values),
        data: sanitize_data(data)
      }.merge(tracking).merge(Leads::Attribution.browser_identifiers(request)).compact
    end

    public :build_payload

    def lead_user_data(values)
      first_name, last_name = (values[:name].presence || values[:client_name]).to_s.strip.split(/\s+/, 2)
      phone = Phones::Normalizer.call(values[:phone].presence || values[:client_phone]).presence
      {
        email_address: values[:email].presence || values[:client_email].presence,
        phone_number: phone ? "+#{phone}" : nil,
        external_id: values[:id]&.to_s,
        address: { first_name: first_name.presence, last_name: last_name.presence }.compact.presence
      }.compact
    end

    def sanitize_data(data)
      # Remove dados sensíveis do Rails
      data.except('authenticity_token', 'commit', 'controller', 'action', 'utf8',
        'c2s_export_external_id', 'c2s_exported_at', :c2s_export_external_id, :c2s_exported_at)
    end

    def source_metadata(request, data)
      metadata = {
        page_url: data["page_url"] || data[:page_url] || data["source_url"] || data[:source_url],
        request_url: request&.original_url,
        referrer_url: data["referrer_url"] || data[:referrer_url] || request&.referer,
        user_agent: request&.user_agent,
        utm: tracking_params(request, data)
      }.compact

      metadata = metadata[:utm].present? ? metadata : metadata.except(:utm)
      metadata.presence
    end

    def tracking_params(request, data)
      params = {}
      request_query = request&.query_parameters || {}
      source_data = data.respond_to?(:to_h) ? data.to_h : {}

      (Leads::Attribution::TRACKING_KEYS - %w[landing_url referrer_url]).each do |key|
        value = source_data[key] || source_data[key.to_sym] || request_query[key] || request_query[key.to_sym]
        params[key] = value if value.present?
      end

      if !request || request.cookies["unitymob_lgpd_consent"] == "accepted"
        Leads::Attribution::BROWSER_KEYS.each do |key|
          params[key.to_sym] = source_data[key] if source_data[key].present?
        end
      end

      params
    end
    
    def signing_secret
      ENV["WEBHOOK_SIGNING_SECRET"].presence ||
        (Rails.application.credentials.dig(:webhook, :signing_secret) rescue nil)
    end

    # Assinatura HMAC-SHA256 do corpo + timestamp: o receptor confirma que o
    # payload veio de nós e não foi adulterado. Sem segredo configurado, envia
    # sem assinar (compatível com integrações antigas).
    def signature_headers(body)
      secret = signing_secret
      return {} if secret.blank?

      timestamp = Time.current.to_i.to_s
      digest = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
      {
        "X-Unitymob-Timestamp" => timestamp,
        "X-Unitymob-Signature" => "sha256=#{digest}"
      }
    end
  end
end
