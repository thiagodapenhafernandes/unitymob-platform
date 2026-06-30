class MetaLeadProcessingJob < ApplicationJob
  queue_as :default

  def perform(lead_id, page_id, form_id)
    Rails.logger.info "[MetaLeadProcessingJob] Iniciando processamento do Lead: #{lead_id} (Form: #{form_id})"

    # 1. Obter Integração para o Token
    integration = UserMetaIntegration.joins(:meta_facebook_pages).where(meta_facebook_pages: { page_id: page_id }).first
    unless integration
      Rails.logger.error "[MetaLeadProcessingJob] Nenhuma integração encontrada para a Page ID: #{page_id}"
      return
    end
    tenant = integration.admin_user&.tenant
    unless tenant
      Rails.logger.error "[MetaLeadProcessingJob] Integração #{integration.id} sem Tenant associado."
      return
    end

    # 2. Buscar detalhes do Lead na API
    # Usamos o token da página se disponível, ou o do usuário
    page = integration.meta_facebook_pages.find_by(page_id: page_id)
    token = page&.access_token || integration.access_token
    
    service = Facebook::MetaService.new(token)
    lead_details = service.get_lead_details(lead_id)

    if lead_details.blank? || lead_details["field_data"].blank?
      Rails.logger.error "[MetaLeadProcessingJob] Erro ao buscar detalhes do lead #{lead_id} ou dados vazios."
      return
    end

    # 3. Extrair e Mapear Dados
    field_data = lead_details["field_data"]

    email = extract_field(field_data, [ "email", "email_address" ])
    phone = extract_field(field_data, [ "phone_number", "phone", "whatsapp", "tel" ])
    name  = extract_field(field_data, [ "full_name", "fullname", "name", "first_name" ])

    if name && !field_data.any? { |f| f["name"].to_s.downcase.include?("full") }
      last_name = extract_field(field_data, [ "last_name", "surname" ])
      name = "#{name} #{last_name}".strip if last_name.present?
    end

    name ||= "Lead Facebook"

    form_record = integration.meta_lead_forms.find_by(form_id: form_id.to_s)
    product_name = form_record&.name || "Meta Lead (#{form_id})"

    # 4. Criar o Lead no CRM
    # Note: O RoutingService será chamado automaticamente pelo callback after_create do model Lead
    Current.set(tenant: tenant) do
      tenant.leads.create!(
        admin_user_id: integration.admin_user_id, # Atribuído inicialmente ao dono da integração
        name: name,
        email: email,
        phone: phone,
        client_name: name,
        client_email: email,
        client_phone: phone,
        origin: "Facebook Lead Ads",
        product: product_name,
        custom_answers: map_to_custom_answers(field_data),
        other_information: lead_details.as_json.merge({
          "meta_page_id" => page_id.to_s,
          "meta_form_id" => form_id.to_s,
          "processed_at" => Time.current
        })
      )
    end

    Rails.logger.info "[MetaLeadProcessingJob] Lead #{lead_id} processado com sucesso."

  rescue => e
    Rails.logger.error "[MetaLeadProcessingJob] Erro Crítico no lead #{lead_id}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  private

  def extract_field(field_data, keys)
    keys = Array(keys)
    field = field_data.find do |f|
      field_name = f["name"].to_s.downcase
      keys.any? { |k| field_name.include?(k) }
    end

    field ? field["values"]&.first : nil
  end

  def map_to_custom_answers(field_data)
    field_data.map do |f|
      {
        "key" => f["name"],
        "answer" => f["values"]&.first
      }
    end
  end
end
