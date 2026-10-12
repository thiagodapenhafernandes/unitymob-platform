module Admin::WebhookSettingsHelper
  def webhook_payload_example(event_name)
    data = Lead.new.attributes.merge(
      "id" => 48213, "name" => "Cliente Exemplo", "email" => "cliente@example.com",
      "phone" => "5547999999999", "tenant_id" => current_tenant.id,
      "property_id" => 9981, "property_code" => "AP1234", "business_type" => "sale",
      "value" => 150.0, "currency" => "BRL",
      "lead_type" => "whatsapp_modal", "status" => "Novo",
      "other_information" => { "unitymob_data_processing_policy" => Privacy::LegalBases.record },
      "source_url" => "#{request.base_url}/imoveis/exemplo", "placement" => "property_card",
      "attribution_data" => { "gclid" => "TEST_GCLID", "gbraid" => "TEST_GBRAID", "wbraid" => "TEST_WBRAID",
        "utm_source" => "google", "utm_medium" => "cpc", "utm_campaign" => "campanha_exemplo" }
    )
    if event_name == "lead_inquiry"
      data["complemented_inquiry"] = true
    elsif event_name == "form_submitted"
      data = { "name" => "Cliente Exemplo", "email" => "cliente@example.com", "message" => "Gostaria de saber mais.",
        "public_form_id" => 123, "public_form_slug" => "fale-conosco", "page_url" => "#{request.base_url}/contato" }
    elsif event_name == "lead_stage_changed"
      data["status"] = "Em Atendimento"
      data["changes"] = { "status" => { "from" => "Novo", "to" => "Em Atendimento" } }
    elsif %w[lead_qualification_changed qualified_lead].include?(event_name)
      data["broker_qualification_status"] = "qualified"
      data["changes"] = { "broker_qualification_status" => { "from" => "missing_data", "to" => "qualified" } }
    end
    browser = Struct.new(:original_url, :referer, :user_agent, :remote_ip, :query_parameters, :cookies).new(
      "#{request.base_url}/leads", "https://google.com/", "Mozilla/5.0 (exemplo)", "203.0.113.10", {},
      { "unitymob_lgpd_consent" => "accepted", "_fbc" => "fb.1.1779816600000.TEST",
        "_fbp" => "fb.1.1779816600000.1234567890", "_ga" => "GA1.1.1234567890.1779816600" })
    origin = { "lead_created" => "whatsapp_lead", "lead_inquiry" => "whatsapp_lead", "form_submitted" => "contact_form" }.fetch(event_name, event_name)
    options = %w[lead_stage_changed lead_qualification_changed qualified_lead].include?(event_name) ? {} : { request: browser }
    WebhookService.build_payload(origin, data, options)
  end
end
