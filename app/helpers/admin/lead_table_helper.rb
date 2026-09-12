module Admin::LeadTableHelper
  def lead_table_interest_properties(leads, tenant:)
    lead_ids = leads.select { |lead| lead.tenant_id == tenant.id && lead.property_id.blank? }.map(&:id)
    return {} if lead_ids.empty?

    interests = LeadPropertyInterest.where(tenant_id: tenant.id).joins(:habitation)
      .where(lead_id: lead_ids, habitations: { tenant_id: tenant.id })
      .select("DISTINCT ON (lead_property_interests.lead_id) lead_property_interests.*")
      .order(:lead_id, :created_at, :id).includes(:habitation)
    interests.to_h { |interest| [interest.lead_id, interest.habitation] }
  end

  def lead_table_status_tone(status)
    { "info" => :cyan, "primary" => :blue, "warning" => :amber,
      "secondary" => :gray, "danger" => :red, "success" => :green }.fetch(Lead.status_badge_class(status), :gray)
  end

  def lead_table_property_badges(lead, property)
    return [] unless property

    badges = []
    business = lead.business_label.presence
    business ||= { "Venda" => "Venda", "Aluguel" => "Locação", "Venda e Aluguel" => "Venda / Locação" }[property.status]
    badges << [business, business.to_s.match?(/loca|alug/i) ? :green : :blue] if business
    badges << [property.categoria, :gray] if property.categoria.present?
    { dormitorios_qtd: "dorm.", suites_qtd: "suítes", vagas_qtd: "vagas" }.each do |field, label|
      count = property.public_send(field)
      label = { "suítes" => "suíte", "vagas" => "vaga" }.fetch(label, label) if count.to_i == 1
      badges << ["#{count.to_i} #{label}", :gray] if count.to_i.positive?
    end
    area = property.area_privativa_m2
    badges << ["#{number_with_precision(area, precision: 2, strip_insignificant_zeros: true)} m²", :gray] if area.to_f.positive?
    badges
  end

  # IDs diretos têm prioridade. Na importação, mantenha formulário e página
  # do mesmo bloco de origem, sem misturar referências de integrações distintas.
  def lead_meta_form_reference(lead)
    info = lead.other_information.to_h
    return { "form_id" => info["meta_form_id"], "page_id" => info["meta_page_id"] } if info["meta_form_id"].present?

    candidates = [lead.attribution_data.to_h["facebook"]]
    %w[external_lead_payload c2s_payload data].each do |key|
      payload = info[key]
      candidates << payload["facebook_attributes"] if payload.is_a?(Hash)
    end
    candidates.find { |item| item.is_a?(Hash) && item["form_id"].present? } || {}
  end

  def lead_table_meta_form_names(leads, tenant:)
    leads = leads.select { |lead| lead.tenant_id == tenant.id }
    references = leads.to_h { |lead| [lead.id, lead_meta_form_reference(lead)] }
    ids = references.values.filter_map { |reference| reference["form_id"].presence }.map(&:to_s)
    return {} if ids.empty?

    forms = MetaLeadForm.joins(meta_facebook_page: :user_meta_integration)
      .where(user_meta_integrations: {tenant_id: tenant.id}, form_id: ids)
      .pluck("meta_facebook_pages.page_id", :form_id, :name)
    leads.to_h do |lead|
      reference = references.fetch(lead.id)
      names = forms.select { |page_id, form_id, _| form_id == reference["form_id"].to_s &&
        (reference["page_id"].blank? || page_id == reference["page_id"].to_s) }.map(&:last).uniq
      [lead.id, names.one? ? names.first : nil]
    end
  end

  def lead_table_conversion(lead, conversion, form_name: nil)
    info = lead.other_information.is_a?(Hash) ? lead.other_information : {}
    return {label: "Cadastro: Extensão Unitymob", icon: "puzzle", tone: :purple, campaign: nil} if info["creation_source"] == "browser_extension"

    form_id = lead_meta_form_reference(lead)["form_id"]
    form_name ||= info["meta_form_name"].presence || info["form_name"].presence
    form_name ||= lead.product.presence if info["meta_form_id"].present?
    campaign = info["meta_campaign_name"].presence || info["campaign_name"].presence || conversion[:campaign].presence
    if form_id.present? || form_name.present?
      label = "Formulário: #{form_name || form_id}"
      { label: label, icon: "ui-checks", tone: :blue, campaign: campaign }
    elsif conversion[:conversion_origin_label].present?
      channel = conversion[:conversion_origin_label]
      { label: "Conversão: #{channel}", icon: channel == "WhatsApp" ? "whatsapp" : "globe2",
        tone: channel == "WhatsApp" ? :green : :blue, campaign: campaign }
    else
      { label: "Canal: #{conversion[:channel_label]}", icon: conversion[:icon].delete_prefix("bi-"),
        tone: conversion[:color].to_sym, campaign: campaign }
    end
  end
end
