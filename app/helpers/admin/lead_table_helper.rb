module Admin::LeadTableHelper
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

  def lead_table_meta_form_names(leads, tenant:)
    ids = leads.filter_map { |lead| lead.other_information.to_h["meta_form_id"].presence }.map(&:to_s)
    return {} if ids.empty?

    forms = MetaLeadForm.joins(meta_facebook_page: :user_meta_integration)
      .where(user_meta_integrations: {tenant_id: tenant.id}, form_id: ids)
      .pluck("meta_facebook_pages.page_id", :form_id, :name)
    leads.to_h do |lead|
      info = lead.other_information.to_h
      names = forms.select { |page_id, form_id, _| form_id == info["meta_form_id"].to_s &&
        (info["meta_page_id"].blank? || page_id == info["meta_page_id"].to_s) }.map(&:last).uniq
      [lead.id, names.one? ? names.first : nil]
    end
  end

  def lead_table_conversion(lead, conversion, form_name: nil)
    info = lead.other_information.is_a?(Hash) ? lead.other_information : {}
    return {label: "Cadastro: Extensão Unitymob", icon: "puzzle", tone: :purple, campaign: nil} if info["creation_source"] == "browser_extension"

    form_name ||= info["meta_form_name"].presence || info["form_name"].presence
    form_name ||= lead.product.presence if info["meta_form_id"].present?
    campaign = info["meta_campaign_name"].presence || info["campaign_name"].presence || conversion[:campaign].presence
    if info["meta_form_id"].present? || form_name.present?
      label = "Formulário: #{form_name || info['meta_form_id']}"
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
