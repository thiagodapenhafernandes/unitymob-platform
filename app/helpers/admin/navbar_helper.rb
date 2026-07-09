module Admin::NavbarHelper
  ADMIN_CONTEXTBAR_TITLES = {
    "dashboard" => "Dashboard",
    "habitations" => "Imóveis",
    "proprietors" => "Proprietários",
    "leads" => "Leads",
    "tasks" => "Tarefas",
    "appointments" => "Agenda",
    "distribution_rules" => "Distribuição",
    "stores" => "Lojas",
    "captacoes" => "Captações",
    "habitation_intakes" => "Captações",
    "automation_rules" => "Automação",
    "automation_workflows" => "Automação",
    "whatsapp_inbox" => "Atendimento",
    "whatsapp_campaigns" => "Disparos WhatsApp",
    "whatsapp_campaign_recipients" => "Importados CSV",
    "whatsapp_campaign_unsubscribes" => "Descadastros WhatsApp",
    "marketing_campaigns" => "Campanhas",
    "marketing_opportunities" => "Oportunidades",
    "marketing_properties" => "Marketing",
    "seo_dashboard" => "Dashboard SEO",
    "seo_settings" => "Páginas SEO",
    "seo_redirects" => "Redirecionamentos SEO",
    "meta_integrations" => "Meta Leads",
    "whatsapp_integrations" => "WhatsApp",
    "admin_users" => "Usuários",
    "profiles" => "Perfis",
    "access_audit_logs" => "Auditoria",
    "data_export_audit_logs" => "Exportações",
    "layout_settings" => "Identidade e Marca",
    "lead_settings" => "Configurações de Leads",
    "email_settings" => "E-mail (SMTP)",
    "push_settings" => "Push no PWA",
    "webhook_settings" => "Webhooks",
    "landing_pages" => "Landing pages",
    "banners" => "Banners"
  }.freeze

  def admin_contextbar_title
    return content_for(:admin_contextbar_title) if content_for?(:admin_contextbar_title)

    ADMIN_CONTEXTBAR_TITLES.fetch(controller_name, controller_name.to_s.humanize)
  end

  def admin_contextbar_actions
    return content_for(:admin_contextbar_actions) if content_for?(:admin_contextbar_actions)

    actions = case controller_name
              when "dashboard"
                admin_dashboard_contextbar_actions
              when "habitations"
                admin_habitations_contextbar_actions
              when "proprietors"
                [
                  admin_contextbar_link("Novo proprietário", new_admin_proprietor_path, icon: "plus-lg", primary: true)
                ]
              when "leads"
                if action_name == "show"
                  view_mode = current_admin_user&.leads_view_mode.presence_in(%w[kanban list]) || "kanban"
                  [
                    admin_contextbar_link("Voltar", admin_leads_path(view: view_mode), icon: "arrow-left", if: can?(:view, :leads))
                  ]
                else
                  [
                    admin_contextbar_link("Atendimento", admin_whatsapp_conversations_path, icon: "whatsapp", if: can?(:view, :whatsapp_inbox)),
                    admin_contextbar_link("Tarefas", admin_tasks_path, icon: "check2-square", if: can?(:view, :comercial))
                  ]
                end
              when "tasks"
                [
                  admin_contextbar_link("Leads", admin_leads_path, icon: "megaphone", if: can?(:view, :comercial)),
                  admin_contextbar_link("Agenda", admin_appointments_path, icon: "calendar-event", if: can?(:view, :comercial))
                ]
              when "appointments"
                [
                  admin_contextbar_link("Tarefas", admin_tasks_path, icon: "check2-square", if: can?(:view, :comercial)),
                  admin_contextbar_link("Leads", admin_leads_path, icon: "megaphone", if: can?(:view, :comercial))
                ]
              when "distribution_rules"
                [
                  admin_contextbar_link("Nova regra", new_admin_distribution_rule_path, icon: "plus-lg", primary: true, if: can?(:manage, :distribution_rules))
                ]
              when "stores"
                [
                  admin_contextbar_link("Nova loja", new_admin_store_path, icon: "plus-lg", primary: true, if: can?(:manage, :lojas))
                ]
              when "captacoes", "habitation_intakes"
                admin_captacoes_contextbar_actions
              when "automation_rules"
                [
                  admin_contextbar_link("Nova automação", new_admin_automation_rule_path, icon: "plus-lg", primary: true, if: can?(:manage, :automacoes))
                ]
              when "marketing_campaigns"
                [
                  admin_contextbar_link("Nova campanha", new_admin_marketing_campaign_path, icon: "plus-lg", primary: true, if: can?(:view, :marketing))
                ]
              when "landing_pages"
                [
                  admin_contextbar_link("Nova landing", new_admin_landing_page_path, icon: "plus-lg", primary: true, if: can?(:view, :marketing))
                ]
              when "banners"
                [
                  admin_contextbar_link("Novo banner", new_admin_banner_path, icon: "plus-lg", primary: true, if: can?(:view, :marketing))
                ]
              when "admin_users"
                [
                  admin_contextbar_link("Hierarquia", hierarchy_admin_admin_users_path, icon: "diagram-3"),
                  admin_contextbar_link("Novo usuário", new_admin_admin_user_path, icon: "person-plus", primary: true, if: can?(:manage, :corretores))
                ]
              when "profiles"
                [
                  admin_contextbar_link("Perfil vertical", new_admin_profile_path(axis: "vertical"), icon: "diagram-3", primary: true, if: tenant_owner?),
                  admin_contextbar_link("Função horizontal", new_admin_profile_path(axis: "horizontal"), icon: "person-gear", if: tenant_owner?)
                ]
              else
                []
              end

    safe_join(Array(actions).compact)
  rescue StandardError
    "".html_safe
  end

  def admin_contextbar_breadcrumb
    return content_for(:admin_contextbar_breadcrumb) if content_for?(:admin_contextbar_breadcrumb)

    safe_join(
      [
        link_to(admin_contextbar_root_label, tenant_owner? ? admin_root_path : field_root_path),
        tag.i(class: "bi bi-chevron-right"),
        tag.strong(admin_contextbar_title)
      ]
    )
  end

  def admin_contextbar_navigation(breadcrumb = nil)
    safe_join(
      [
        admin_contextbar_back_link,
        breadcrumb.presence || admin_contextbar_breadcrumb
      ].compact
    )
  end

  def admin_contextbar_back_link
    path = admin_contextbar_back_path
    return nil if path.blank?

    link_to(path, class: "ax-breadcrumb__back", title: "Voltar para a tela anterior") do
      safe_join([tag.i(class: "bi bi-arrow-left"), tag.span("Voltar")])
    end
  end

  def admin_contextbar_back_path
    explicit_return_path = safe_admin_contextbar_return_path(params[:return_to], source_params: params)
    return explicit_return_path if explicit_return_path.present?

    inferred_return_path = admin_contextbar_inferred_back_path
    return inferred_return_path if inferred_return_path.present?

    safe_admin_contextbar_return_path(request.referer)
  end

  def admin_contextbar_root_label
    "Início"
  end

  # Contadores leves exibidos na navbar (rodam em toda página admin — sempre resilientes).
  def navbar_pending_tasks_count
    return 0 unless current_admin_user && can?(:view, :comercial)
    current_tenant.tasks.where(admin_user_id: current_admin_user.id, status: "pendente").count
  rescue StandardError
    0
  end

  def navbar_unread_conversations_count
    return 0 unless current_admin_user && can?(:view, :whatsapp_inbox)

    scope = current_tenant.whatsapp_conversations.where("unread_count > 0")
    unless tenant_owner? || current_admin_user.owns_all?(:whatsapp_inbox)
      scope = scope.left_joins(:lead).where(
        "whatsapp_conversations.assigned_admin_user_id = :id OR leads.admin_user_id = :id",
        id: current_admin_user.id
      )
    end
    scope.count
  rescue StandardError
    0
  end

  private

  def admin_dashboard_contextbar_actions
    if tenant_owner?
        [
          admin_contextbar_link("Lojas", admin_stores_path, icon: "shop", if: can?(:view, :lojas)),
          admin_contextbar_link("Regras", admin_distribution_rules_path, icon: "diagram-3", if: can?(:manage, :distribution_rules)),
          admin_contextbar_link("Check-ins", admin_field_check_ins_path, icon: "geo-fill", if: can?(:view, :field_checkins))
        ]
    else
      [
        admin_contextbar_link("Nova captação", new_admin_captacao_path, icon: "journal-plus", primary: true),
        admin_contextbar_link("Meus leads", admin_leads_path, icon: "megaphone", if: can?(:view, :comercial)),
        admin_contextbar_link("Ir para PWA", field_root_path, icon: "phone")
      ]
    end
  end

  def admin_habitations_contextbar_actions
    [
      admin_contextbar_link("Proprietários", admin_proprietors_path, icon: "person-vcard", if: can?(:view, :proprietarios)),
      admin_contextbar_button("Exportar", icon: "download", data: { ax_modal_open: "#habitationsExportModal" }, if: tenant_owner? || current_admin_user&.owns_all?(:imoveis)),
      admin_contextbar_link("Novo imóvel", new_admin_habitation_path, icon: "plus-lg", primary: true, if: can?(:manage, :imoveis))
    ]
  end

  def admin_captacoes_contextbar_actions
    actions = []
    actions << admin_contextbar_link("Exportar", export_admin_captacoes_path(request.query_parameters), icon: "file-earmark-spreadsheet", if: respond_to?(:can_export_captacoes?) && can_export_captacoes?)
    actions << admin_contextbar_link("Nova captação", new_admin_captacao_path, icon: "plus-lg", primary: true)
    actions
  end

  def admin_contextbar_inferred_back_path
    return admin_whatsapp_campaigns_path if controller_name == "whatsapp_campaigns" &&
                                           action_name == "index" &&
                                           params[:whatsapp_sender_number_id].present?

    nil
  end

  def admin_contextbar_link(label, path, icon:, primary: false, **options)
    condition = options.delete(:if)
    return nil if condition == false

    classes = ["ax-contextbar__button"]
    classes << "ax-contextbar__button--primary" if primary
    classes << options.delete(:class)

    link_to(path, options.merge(class: classes.compact.join(" "))) do
      safe_join([tag.i(class: "bi bi-#{icon}"), tag.span(label)])
    end
  end

  def admin_contextbar_button(label, icon:, primary: false, **options)
    condition = options.delete(:if)
    return nil if condition == false

    classes = ["ax-contextbar__button"]
    classes << "ax-contextbar__button--primary" if primary
    classes << options.delete(:class)

    tag.button(**options.merge(type: "button", class: classes.compact.join(" "))) do
      safe_join([tag.i(class: "bi bi-#{icon}"), tag.span(label)])
    end
  end

  def safe_admin_contextbar_return_path(value, source_params: nil)
    raw_value = value.to_s.strip
    return nil if raw_value.blank?

    uri = URI.parse(raw_value)
    return nil if uri.scheme.present? && !same_request_host?(uri)
    return nil if uri.host.present? && !same_request_host?(uri)
    return nil unless internal_contextbar_path?(uri.path)

    query = if uri.path == admin_habitations_path
              compact_admin_contextbar_return_query(
                admin_contextbar_habitations_return_query(uri, source_params)
              )
            else
              uri.query.presence
            end
    path = [uri.path, query].compact.join("?")
    return nil if same_contextbar_path?(path)

    fragment = uri.fragment.presence || admin_contextbar_return_source_params(source_params)["back_anchor"].to_s.presence
    fragment.present? ? "#{path}##{fragment}" : path
  rescue URI::InvalidURIError
    nil
  end

  def admin_contextbar_habitations_return_query(uri, source_params)
    Rack::Utils.build_nested_query(
      Rack::Utils.parse_nested_query(uri.query.to_s)
        .merge(admin_contextbar_return_source_params(source_params).except("back_anchor"))
    )
  end

  def admin_contextbar_return_source_params(source_params)
    raw_params =
      if source_params.respond_to?(:to_unsafe_h)
        source_params.to_unsafe_h
      elsif source_params.respond_to?(:to_h)
        source_params.to_h
      else
        {}
      end

    raw_params
      .except(*admin_contextbar_return_param_denylist)
      .compact_blank
  end

  def admin_contextbar_return_param_denylist
    %w[
      controller action id habitation_id return_to authenticity_token _method utf8 commit
      habitation save_anchor save_navigation save_context release_to_broker_after_save save_internal_after_save
    ]
  end

  def compact_admin_contextbar_return_query(query)
    compacted = compact_admin_contextbar_return_params(Rack::Utils.parse_nested_query(query.to_s))
    return nil if blank_admin_contextbar_return_param?(compacted)

    Rack::Utils.build_nested_query(compacted)
  end

  def compact_admin_contextbar_return_params(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested_value), compacted_hash|
        compacted_value = compact_admin_contextbar_return_params(nested_value)
        compacted_hash[key] = compacted_value unless blank_admin_contextbar_return_param?(compacted_value)
      end
    when Array
      value.filter_map do |nested_value|
        compacted_value = compact_admin_contextbar_return_params(nested_value)
        compacted_value unless blank_admin_contextbar_return_param?(compacted_value)
      end
    else
      value.to_s.strip.presence
    end
  end

  def blank_admin_contextbar_return_param?(value)
    value.blank? || (value.respond_to?(:empty?) && value.empty?)
  end

  def same_request_host?(uri)
    uri.host == request.host && (uri.port.blank? || uri.port == request.port)
  end

  def internal_contextbar_path?(path)
    normalized_path = path.to_s
    return false unless normalized_path.start_with?("/")
    return false if normalized_path.start_with?("//")

    normalized_path == admin_root_path ||
      normalized_path.start_with?("#{admin_root_path}/") ||
      normalized_path == field_root_path ||
      normalized_path.start_with?("#{field_root_path}/")
  end

  def same_contextbar_path?(path)
    current_path = request.fullpath.presence || request.path
    path.to_s == current_path.to_s
  end
end
