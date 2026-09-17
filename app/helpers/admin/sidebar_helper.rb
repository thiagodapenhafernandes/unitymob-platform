module Admin::SidebarHelper
  # Sidebar é uma projeção do catálogo Profile::RESOURCES.
  # Para adicionar menu de um módulo, prefira editar `sidebar_section`,
  # `sidebar_actions` e `sidebar_items` no catálogo em vez de colocar regra
  # manual na partial. A visibilidade sempre passa por `can?`, igual ao backend.
  def admin_sidebar_section_visible?(section)
    Profile.sidebar_permissions_for(section).any? do |action, resource|
      can?(action, resource)
    end
  end

  def admin_sidebar_section_items(section)
    safe_join(Profile.sidebar_items_for(section, profile: current_admin_user&.access_profile).filter_map { |item| admin_sidebar_item_node(item) })
  end

  def admin_sidebar_item_node(item)
    return tag.li(item.fetch(:caption), class: "ax-nav__caption") if item[:caption].present?
    return admin_sidebar_dynamic_item_node(item) if item[:dynamic].present?
    return admin_sidebar_group_node(item) if item[:group].present?
    return unless admin_sidebar_item_visible?(item)

    path = admin_sidebar_item_path(item)
    active = admin_sidebar_item_active?(item)

    tag.li do
      link_to(path, class: "ax-nav__link #{'active' if active}") do
        safe_join([
          tag.i(class: "bi #{item.fetch(:icon)}"),
          tag.span(item.fetch(:label))
        ])
      end
    end
  end

  def admin_sidebar_group_node(item)
    return unless admin_sidebar_item_visible?(item)

    children = Array(item[:children]).filter_map { |child| admin_sidebar_item_node(child) }
    return if children.empty?

    open = admin_sidebar_item_active?(item)
    tag.li(class: "ax-nav__group #{'is-open' if open}", data: { controller: "ax-disclosure", ax_disclosure_open_value: open }) do
      safe_join([
        tag.button(type: "button", class: "ax-nav__link ax-nav__link--group", data: { action: "ax-disclosure#toggle", ax_disclosure_target: "trigger" }, aria: { expanded: open }) do
          safe_join([
            tag.i(class: "bi #{item.fetch(:icon)}"),
            tag.span(item.fetch(:group)),
            tag.i(class: "bi bi-chevron-down ax-nav__chevron")
          ])
        end,
        tag.ul(safe_join(children), class: "ax-nav__sub", data: { ax_disclosure_target: "content" }, hidden: !open)
      ])
    end
  end

  def admin_sidebar_dynamic_item_node(item)
    case item[:dynamic].to_s
    when "dashboard_home"
      admin_sidebar_dashboard_home_node(item)
    when "lead_pipelines"
      admin_sidebar_lead_pipelines_node(item)
    end
  end

  def admin_sidebar_dashboard_home_node(item)
    return unless admin_sidebar_item_visible?(item)

    field_home_navigation = current_admin_user&.field_agent_enabled? || current_admin_user&.profile&.key.to_s == "agent"
    path = field_home_navigation ? field_root_path : admin_root_path
    label = field_home_navigation ? "Início" : "Painel"

    tag.li do
      link_to(path, class: "ax-nav__link #{'active' if request.path == path}") do
        safe_join([
          tag.i(class: "bi #{item.fetch(:icon)}"),
          tag.span(label)
        ])
      end
    end
  end

  def admin_sidebar_lead_pipelines_node(item)
    return unless admin_sidebar_item_visible?(item)

    pipelines = current_tenant.lead_pipelines.active.ordered.select do |pipeline|
      can?(:view, admin_sidebar_lead_pipeline_resource(pipeline))
    end
    return if pipelines.empty?

    open = controller_name == "leads" && params[:lead_pipeline_id].present?
    tag.li(class: "ax-nav__group #{'is-open' if open}", data: { controller: "ax-disclosure", ax_disclosure_open_value: open }) do
      safe_join([
        tag.button(type: "button", class: "ax-nav__link ax-nav__link--group", data: { action: "ax-disclosure#toggle", ax_disclosure_target: "trigger" }, aria: { expanded: open }) do
          safe_join([
            tag.i(class: "bi #{item.fetch(:icon)}"),
            tag.span(item.fetch(:group)),
            tag.i(class: "bi bi-chevron-down ax-nav__chevron")
          ])
        end,
        tag.ul(class: "ax-nav__sub", data: { ax_disclosure_target: "content" }, hidden: !open) do
          safe_join(pipelines.map do |pipeline|
            tag.li do
              link_to(admin_lead_pipeline_leads_path(pipeline, view: "kanban"), class: "ax-nav__link #{'active' if params[:lead_pipeline_id].to_i == pipeline.id}") do
                safe_join([
                  tag.i(class: "bi bi-kanban"),
                  tag.span(pipeline.name)
                ])
              end
            end
          end)
        end
      ])
    end
  end

  def admin_sidebar_lead_pipeline_resource(pipeline)
    case pipeline.kind
    when "rental" then :lead_funnel_rental
    when "sale" then :lead_funnel_sale
    else :lead_funnels
    end
  end

  def admin_sidebar_item_visible?(item)
    case item[:condition].to_s
    when "whatsapp_service_ready"
      sidebar_tenant = respond_to?(:current_tenant) ? current_tenant : Current.tenant
      return false unless sidebar_tenant.present?
      return false unless WhatsappBusinessIntegration.current(sidebar_tenant)&.messaging_ready?
    end

    permission_all = Array(item[:permission_all])
    return false if permission_all.any? && !permission_all.all? { |action, resource| can?(action, resource) }

    permission_any = Array(item[:permission_any])
    return permission_any.any? { |action, resource| can?(action, resource) } if permission_any.any?

    action, resource = item[:permission]
    return can?(action, resource) if action.present?

    true
  end

  def admin_sidebar_item_path(item)
    public_send(item.fetch(:path), **item.fetch(:path_params, {}))
  end

  def admin_sidebar_item_active?(item)
    controllers = Array(item[:controllers])
    controller_paths = Array(item[:controller_paths])
    active_actions = Array(item[:active_actions])
    active_params = (item[:active_params] || {}).stringify_keys
    inactive_actions = Array(item[:inactive_actions])
    inactive_params = Array(item[:inactive_params]).map(&:to_s)

    return false if controllers.any? && !controllers.include?(controller_name)
    return false if controller_paths.any? && !controller_paths.include?(controller_path)
    return false if active_actions.any? && !active_actions.include?(action_name)
    return false if active_params.any? { |key, value| params[key].to_s != value.to_s }
    return false if inactive_actions.include?(action_name)
    return false if inactive_params.any? { |key| params[key].present? }

    controllers.any? || controller_paths.any?
  end
end
