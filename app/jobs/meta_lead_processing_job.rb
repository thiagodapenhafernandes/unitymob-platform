class MetaLeadProcessingJob < ApplicationJob
  queue_as :default

  # Detalhes do lead indisponíveis na Graph API (oscilação, rate limit, token
  # expirado): fetch_lead_details engole erros por candidato, então esta classe
  # é o que materializa a falha para o retry do ActiveJob.
  class LeadDetailsUnavailableError < StandardError; end

  # Todos os tenants do fan-out falharam: nenhum lead foi criado, então é
  # seguro (e necessário) retentar o job inteiro.
  class AllTenantsFailedError < StandardError; end

  # Erros transitórios (Graph API, rede, banco) estouram para o retry; após
  # esgotar as tentativas o job cai em failed_executions do SolidQueue
  # (visível/retentável no Mission Control) em vez de sumir silenciosamente.
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  # Modelo agência: a mesma página Meta pode estar conectada em VÁRIAS contas
  # (integrações diferentes). O lead é criado uma vez POR TENANT que possui a
  # página ativa — nunca por integração (dois usuários da mesma conta com a
  # mesma página ≠ dois leads). Dedupe por leadgen_id dentro de cada tenant
  # cobre retries do webhook e o fan-out.
  def perform(lead_id, page_id, form_id)
    Rails.logger.info "[MetaLeadProcessingJob] Iniciando processamento do Lead: #{lead_id} (Form: #{form_id})"

    pages = MetaFacebookPage.where(page_id: page_id.to_s, active: true)
                            .includes(user_meta_integration: :admin_user)
                            .to_a
    if pages.empty?
      Rails.logger.error "[MetaLeadProcessingJob] Nenhuma página ativa encontrada para a Page ID: #{page_id}"
      return
    end

    pages_by_tenant = pages.group_by { |page| page.user_meta_integration&.owner_tenant_id }
    pages_by_tenant.delete(nil)
    if pages_by_tenant.empty?
      Rails.logger.error "[MetaLeadProcessingJob] Páginas da Page ID #{page_id} sem tenant resolvível."
      return
    end

    # Detalhes do lead são os mesmos para todos os tenants: busca 1x com o
    # primeiro token que funcionar (preferindo integrações não expiradas).
    lead_details = fetch_lead_details(lead_id, ordered_candidates(pages_by_tenant.values.flatten))
    if lead_details.blank? || lead_details["field_data"].blank?
      # Não descarta: levanta para o retry_on — o webhook já respondeu 200 à
      # Meta e este job é a única chance de materializar o lead.
      raise LeadDetailsUnavailableError,
            "Detalhes do lead #{lead_id} indisponíveis na Graph API (page #{page_id}, form #{form_id})"
    end

    attributes = extract_lead_attributes(lead_details)

    tenant_errors = {}
    pages_by_tenant.each do |tenant_id, tenant_pages|
      create_lead_for_tenant(tenant_id, tenant_pages, lead_id, page_id, form_id, lead_details, attributes)
    rescue => e
      # Falha em uma conta não pode impedir as demais de receberem o lead.
      tenant_errors[tenant_id] = e
      Rails.logger.error "[MetaLeadProcessingJob] Erro no tenant #{tenant_id} para lead (leadgen_id: #{lead_id}): #{e.class}: #{e.message}"
      Rails.logger.error Array(e.backtrace).first(5).join("\n")
    end

    # Se TODOS os tenants falharam, nada foi criado: re-levanta para o retry
    # (o dedupe em create_lead_for_tenant torna a re-execução idempotente).
    if tenant_errors.any? && tenant_errors.size == pages_by_tenant.size
      last_error = tenant_errors.values.last
      raise AllTenantsFailedError,
            "Lead #{lead_id} falhou em todos os #{tenant_errors.size} tenant(s) " \
            "(#{tenant_errors.keys.join(', ')}) — último erro: #{last_error.class}: #{last_error.message}"
    end

    Rails.logger.info "[MetaLeadProcessingJob] Lead #{lead_id} processado com sucesso."
  end

  private

  # Ordem determinística de tentativa: integração não expirada primeiro,
  # depois a sincronizada mais recentemente.
  def ordered_candidates(pages)
    pages.sort_by do |page|
      integration = page.user_meta_integration
      [integration&.expired? ? 1 : 0, -(integration&.last_synced_at || Time.at(0)).to_i]
    end
  end

  def fetch_lead_details(lead_id, candidates)
    candidates.each do |page|
      token = page.access_token.presence || page.user_meta_integration&.access_token
      next if token.blank?

      details = Facebook::MetaService.new(token).get_lead_details(lead_id)
      return details if details.present? && details["field_data"].present?
    rescue => e
      Rails.logger.warn "[MetaLeadProcessingJob] Falha ao buscar lead #{lead_id} com a página #{page.id}: #{e.message} — tentando próxima."
    end
    nil
  end

  def extract_lead_attributes(lead_details)
    field_data = lead_details["field_data"]

    email = extract_field(field_data, [ "email", "email_address" ])
    phone = extract_field(field_data, [ "phone_number", "phone", "whatsapp", "tel" ])
    name  = extract_field(field_data, [ "full_name", "fullname", "name", "first_name" ])

    if name && !field_data.any? { |f| f["name"].to_s.downcase.include?("full") }
      last_name = extract_field(field_data, [ "last_name", "surname" ])
      name = "#{name} #{last_name}".strip if last_name.present?
    end

    { name: name.presence || "Lead Facebook", email: email, phone: phone, field_data: field_data }
  end

  def create_lead_for_tenant(tenant_id, tenant_pages, lead_id, page_id, form_id, lead_details, attributes)
    tenant = Tenant.find_by(id: tenant_id)
    return unless tenant

    reference_page = ordered_candidates(tenant_pages).first
    integration = reference_page.user_meta_integration
    form_record = integration&.meta_lead_forms&.find_by(form_id: form_id.to_s)
    product_name = form_record&.name || "Meta Lead (#{form_id})"

    Current.set(tenant: tenant) do
      # Idempotência por conta: retries do webhook e fan-out não duplicam.
      if tenant.leads.where("other_information->>'meta_leadgen_id' = ?", lead_id.to_s).exists?
        Rails.logger.info "[MetaLeadProcessingJob] Lead #{lead_id} já existe no tenant #{tenant_id} — ignorado."
        next
      end

      begin
        tenant.leads.create!(
          # NÃO pré-atribuir ao dono da integração: o lead entra SEM corretor para
          # as regras de distribuição rodarem (RoutingService só distribui quando
          # admin_user_id é nil). O dono da integração fica auditado abaixo.
          name: attributes[:name],
          email: attributes[:email],
          phone: attributes[:phone],
          client_name: attributes[:name],
          client_email: attributes[:email],
          client_phone: attributes[:phone],
          origin: "Facebook Lead Ads",
          product: product_name,
          custom_answers: map_to_custom_answers(attributes[:field_data]),
          other_information: lead_details.as_json.merge({
            "meta_leadgen_id" => lead_id.to_s,
            "meta_page_id" => page_id.to_s,
            "meta_form_id" => form_id.to_s,
            "meta_integration_user_id" => integration&.admin_user_id,
            "processed_at" => Time.current
          })
        )
      rescue ActiveRecord::RecordNotUnique
        # Corrida entre jobs concorrentes do mesmo leadgen_id: outro processo
        # criou primeiro (índice único parcial em tenant_id + meta_leadgen_id).
        # Dedupe, não erro — o create! falhou antes do commit, então nenhum
        # after_create_commit (route_lead) disparou pela metade.
        Rails.logger.info "[MetaLeadProcessingJob] Lead #{lead_id} já criado concorrentemente no tenant #{tenant_id} — ignorado."
      end
    end
  end

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
