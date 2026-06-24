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
    "whatsapp_inbox" => "Atendimento",
    "marketing_campaigns" => "Campanhas",
    "marketing_opportunities" => "Oportunidades",
    "marketing_properties" => "Marketing",
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
                [
                  admin_contextbar_link("Atendimento", admin_whatsapp_conversations_path, icon: "whatsapp", if: can?(:view, :whatsapp_inbox)),
                  admin_contextbar_link("Tarefas", admin_tasks_path, icon: "check2-square", if: can?(:view, :comercial))
                ]
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
                  admin_contextbar_link("Nova regra", new_admin_distribution_rule_path, icon: "plus-lg", primary: true, if: can?(:view, :distribuicao_leads))
                ]
              when "stores"
                [
                  admin_contextbar_link("Nova loja", new_admin_store_path, icon: "plus-lg", primary: true, if: can?(:view, :lojas))
                ]
              when "captacoes", "habitation_intakes"
                admin_captacoes_contextbar_actions
              when "automation_rules"
                [
                  admin_contextbar_link("Nova automação", new_admin_automation_rule_path, icon: "plus-lg", primary: true, if: can?(:view, :automacao))
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
                  admin_contextbar_link("Novo usuário", new_admin_admin_user_path, icon: "person-plus", primary: true, if: current_admin_user&.admin?)
                ]
              when "profiles"
                [
                  admin_contextbar_link("Novo perfil", new_admin_profile_path, icon: "plus-lg", primary: true, if: current_admin_user&.admin?)
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
        link_to(admin_contextbar_root_label, current_admin_user&.admin? ? admin_root_path : field_root_path),
        tag.i(class: "bi bi-chevron-right"),
        tag.strong(admin_contextbar_title)
      ]
    )
  end

  def admin_contextbar_root_label
    return "Plataforma" if current_admin_user&.system_admin?

    @layout_setting&.respond_to?(:admin_area_label) ? @layout_setting.admin_area_label : "Plataforma"
  end

  # Contadores leves exibidos na navbar (rodam em toda página admin — sempre resilientes).
  def navbar_pending_tasks_count
    return 0 unless current_admin_user && can?(:view, :comercial)
    Task.where(admin_user_id: current_admin_user.id, status: "pendente").count
  rescue StandardError
    0
  end

  def navbar_unread_conversations_count
    return 0 unless current_admin_user && can?(:view, :whatsapp_inbox)

    scope = WhatsappConversation.where("unread_count > 0")
    unless current_admin_user.admin? || current_admin_user.owns_all?(:whatsapp_inbox)
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
    if current_admin_user&.admin?
      [
        admin_contextbar_link("Lojas", admin_stores_path, icon: "shop", if: can?(:view, :lojas)),
        admin_contextbar_link("Regras", admin_distribution_rules_path, icon: "diagram-3", if: can?(:view, :distribuicao_leads)),
        admin_contextbar_link("Check-ins", admin_field_check_ins_path, icon: "geo-fill", if: can?(:view, :campo))
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
      admin_contextbar_link("Proprietários", admin_proprietors_path, icon: "person-vcard", if: current_admin_user&.admin?),
      admin_contextbar_button("Exportar", icon: "download", data: { ax_modal_open: "#habitationsExportModal" }, if: current_admin_user&.admin? || current_admin_user&.profile&.administrativo?),
      admin_contextbar_link("Novo imóvel", new_admin_habitation_path, icon: "plus-lg", primary: true, if: can?(:view, :imoveis))
    ]
  end

  def admin_captacoes_contextbar_actions
    actions = []
    actions << admin_contextbar_link("Exportar", export_admin_captacoes_path(request.query_parameters), icon: "file-earmark-spreadsheet", if: respond_to?(:can_export_captacoes?) && can_export_captacoes?)
    actions << admin_contextbar_link("Nova captação", new_admin_captacao_path, icon: "plus-lg", primary: true)
    actions
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
end
