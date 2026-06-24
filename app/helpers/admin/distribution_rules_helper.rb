module Admin::DistributionRulesHelper
  DISTRIBUTION_RULE_DAY_LABELS = {
    "mon" => "Segunda",
    "tue" => "Terça",
    "wed" => "Quarta",
    "thu" => "Quinta",
    "fri" => "Sexta",
    "sat" => "Sábado",
    "sun" => "Domingo"
  }.freeze

  def distribution_rule_business_label(rule)
    {
      "venda" => "Venda",
      "locacao" => "Locação",
      "ambos" => "Venda e locação"
    }.fetch(rule.business_type, rule.business_type.to_s.humanize)
  end

  def distribution_rule_mode_label(rule)
    {
      "rotary" => "Rotativo",
      "performance" => "Performance",
      "shark_tank" => "Shark Tank"
    }.fetch(rule.distribution_mode, rule.distribution_mode.to_s.humanize)
  end

  def distribution_rule_price_range(rule)
    min = rule.min_price.to_f.positive? ? number_to_currency(rule.min_price) : "R$ 0"
    max = rule.max_price.to_f.positive? ? number_to_currency(rule.max_price) : "Ilimitado"
    "#{min} até #{max}"
  end

  def distribution_rule_enabled_sources(rule)
    [
      ["Meta Ads", rule.source_meta?],
      ["Site/WhatsApp", rule.source_site?],
      ["Portais", rule.source_portal?],
      ["Webhook", rule.source_webhook?]
    ].select(&:second).map(&:first)
  end

  def distribution_rule_enabled_notifications(rule)
    [
      ["WhatsApp", rule.notify_whatsapp?],
      ["E-mail", rule.notify_email?],
      ["Push PWA", rule.respond_to?(:notify_push?) && rule.notify_push?],
      ["Webhook externo", rule.notify_webhook?]
    ].select(&:second).map(&:first)
  end

  def distribution_rule_meta_pages(rule)
    page_ids = Array(rule.meta_page_ids).compact_blank.map(&:to_s)
    return MetaFacebookPage.none if page_ids.blank?

    MetaFacebookPage.where(page_id: page_ids).order(:name)
  end

  def distribution_rule_meta_forms(rule, limit: 8)
    form_ids = Array(rule.meta_forms).compact_blank.map(&:to_s)
    return MetaLeadForm.none if form_ids.blank?

    MetaLeadForm.includes(:meta_facebook_page).where(form_id: form_ids).order(:name).limit(limit)
  end

  def distribution_rule_meta_forms_summary(rule)
    selected_count = Array(rule.meta_forms).compact_blank.size
    return "Nenhum formulário selecionado" if selected_count.zero?
    return "Todos os forms das páginas selecionadas entram automaticamente" if rule.auto_add_forms?

    "#{selected_count} formulário#{'s' if selected_count != 1} selecionado#{'s' if selected_count != 1}"
  end

  def distribution_rule_checkin_rows(rule)
    [
      ["Exigir check-in ativo", rule.require_active_checkin?],
      ["Exigir corretor dentro do raio da loja", rule.respond_to?(:require_inside_radius?) && rule.require_inside_radius?],
      ["Exigir turno ativo no momento", rule.respond_to?(:require_active_shift?) && rule.require_active_shift?],
      ["Excluir check-ins suspeitos", rule.respond_to?(:exclude_suspicious_checkins?) && rule.exclude_suspicious_checkins?]
    ]
  end

  def distribution_rule_store_names(rule)
    store_ids = rule.checkin_store_id_list
    return [] if store_ids.blank?

    Store.where(id: store_ids).order(:name).pluck(:name)
  end

  def distribution_rule_schedule_rows(rule)
    rule.ensure_full_schedule
    DISTRIBUTION_RULE_DAY_LABELS.map do |day, label|
      config = rule.represamento_schedule[day] || {}
      [label, config["active"] == "true", config["start"].presence || "09:00", config["end"].presence || "18:00"]
    end
  end

  # Estado de cada canal de notificação de saída usado pelo gate do formulário.
  # `configured` decide se o canal pode ser marcado; quando false, o front abre
  # um modal com instruções + link para a tela de configuração correspondente e
  # reverte o toggle. O Webhook externo é tratado à parte (configuração inline,
  # validação de URL no submit).
  def notification_channel_states
    {
      whatsapp: {
        label: "WhatsApp",
        configured: WhatsappBusinessIntegration.current.connected?,
        path: admin_whatsapp_integration_path,
        instructions: "Conecte uma conta WhatsApp Business (Cloud API) para enviar avisos de novos leads ao corretor."
      },
      email: {
        label: "E-mail ao corretor",
        configured: EmailSetting.instance.configured?,
        path: edit_admin_email_setting_path,
        instructions: "Configure e ative o servidor SMTP (remetente, host, usuário e senha) para enviar e-mails de novos leads."
      },
      push: {
        label: "Push no PWA",
        configured: PushSetting.instance.configured?,
        path: edit_admin_push_setting_path,
        instructions: "Gere as chaves VAPID, informe o e-mail de contato e ative o Web Push para notificar o app dos corretores."
      }
    }
  end

  # data-* aplicados ao checkbox do canal para o controller Stimulus distribution-rule.
  def notify_channel_guard_data(key, state)
    {
      action: "change->distribution-rule#guardChannel",
      channel: key.to_s,
      configured: state[:configured].to_s,
      channel_label: state[:label],
      config_path: state[:path],
      config_instructions: state[:instructions]
    }
  end
end
