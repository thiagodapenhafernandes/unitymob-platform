module Admin::UiHelper
  AX_BADGE_TONES = {
    gray: "ax-badge--gray",
    neutral: "ax-badge--gray",
    green: "ax-badge--green",
    amber: "ax-badge--amber",
    orange: "ax-badge--amber",
    red: "ax-badge--red",
    blue: "ax-badge--blue",
    purple: "ax-badge--purple",
    cyan: "ax-badge--cyan"
  }.freeze

  AX_BUTTON_VARIANTS = {
    primary: "ax-btn--primary",
    secondary: nil,
    ghost: "ax-btn--ghost",
    danger: "ax-btn--danger",
    success: "ax-btn--success",
    warning: "ax-btn--warning",
    info: "ax-btn--info"
  }.freeze

  def ax_icon(name, class_name: nil, decorative: true)
    tag.i(
      class: ["bi", "bi-#{name}", class_name].compact_blank.join(" "),
      aria: (decorative ? { hidden: true } : nil)
    )
  end

  # Iniciais para avatares (WhatsApp inbox e afins): 2 primeiras letras do nome.
  # Botões "WhatsApp" de atendimento apontam para o inbox interno quando o
  # admin da conta ativa em Configurações → Atendimento WhatsApp (e o usuário
  # pode ver o inbox). Caso contrário, caem no wa.me externo.
  def whatsapp_inbox_attendance?
    return @_whatsapp_inbox_attendance if defined?(@_whatsapp_inbox_attendance)

    tenant = respond_to?(:current_tenant) ? current_tenant : Current.tenant
    user = respond_to?(:current_admin_user) ? current_admin_user : nil
    integration = tenant.present? ? WhatsappBusinessIntegration.current(tenant) : nil
    # can? direto no model: o layout de campo nao expoe o helper can? do admin
    @_whatsapp_inbox_attendance = integration.present? &&
      integration.try(:inbox_attendance_enabled?) &&
      integration.messaging_ready? &&
      user&.can?(:view, :whatsapp_inbox).present?
  end

  def wa_initials(name)
    name.to_s.split.map { |part| part[0] }.first(2).join.upcase.presence || "?"
  end

  # Cor CSS de uma etiqueta: hex livre é usado direto; tons do design system
  # mapeiam para a mesma paleta dos radios do catálogo (lead-labels__color--*).
  LEAD_LABEL_CSS_COLORS = {
    "gray" => "#667085", "green" => "#08875d", "amber" => "#d97706",
    "red" => "#e0402f", "blue" => "var(--admin-primary)",
    "purple" => "#7c3aed", "cyan" => "#0e9bb8"
  }.freeze

  LEAD_LABEL_COLOR_NAMES = {
    "red" => "Vermelho", "amber" => "Âmbar", "green" => "Verde", "blue" => "Azul",
    "cyan" => "Ciano", "purple" => "Roxo", "gray" => "Cinza"
  }.freeze

  def lead_label_css_color(color)
    color = color.to_s
    return color if color.match?(LeadLabel::HEX_COLOR)

    LEAD_LABEL_CSS_COLORS.fetch(color, LEAD_LABEL_CSS_COLORS["gray"])
  end

  def ax_badge(label, tone: :gray, dot: false, class_name: nil, **options)
    classes = ["ax-badge", AX_BADGE_TONES.fetch(tone.to_sym, AX_BADGE_TONES[:gray])]
    classes << "ax-badge--dot" if dot
    classes << class_name if class_name.present?

    render "admin/shared/ui/badge", label:, classes:, options:
  end

  def ax_avatar(name:, image: nil, size: :md, class_name: nil)
    size = size.to_sym
    size = :md unless %i[xxs xs sm md lg xl xxl].include?(size)

    render(
      "admin/shared/ui/avatar",
      name:,
      image:,
      initials: wa_initials(name),
      classes: ["ax-avatar", "ax-avatar--#{size}", class_name].compact_blank.join(" ")
    )
  end

  def ax_appointment_card(appointment:, expanded: false)
    render "admin/shared/ui/appointment_card", appointment:, expanded:
  end

  def ax_dismissible_hint(key:, text:, icon: "lightbulb", class_name: nil)
    storage_scope = "admin-user-#{current_admin_user&.id || 'anonymous'}"
    render "admin/shared/ui/dismissible_hint", key:, text:, icon:, class_name:, storage_scope:
  end

  def ax_confirm_submit(form_id:, message:, confirm_label: "Confirmar", cancel_label: "Cancelar", class_name: nil, &block)
    render(
      "admin/shared/ui/confirm_submit",
      form_id:,
      message:,
      confirm_label:,
      cancel_label:,
      class_name:,
      trigger: capture(&block)
    )
  end

  def ax_lead_label_chip(label, class_name: nil)
    tone = ax_lead_label_tone(label)
    render "admin/shared/ui/lead_label_chip", label:, tone:, class_name:
  end

  def ax_lead_label_chips(labels, class_name: nil)
    safe_join(Array(labels).map { |label| ax_lead_label_chip(label, class_name:) })
  end

  def ax_button(label = nil, url = nil, variant: :secondary, size: nil, icon: nil, class_name: nil, **options, &block)
    classes = ["ax-btn", AX_BUTTON_VARIANTS[variant.to_sym], ("ax-btn--#{size}" if size), class_name].compact
    options = ax_merge_class_options(options, classes)
    content = block_given? ? capture(&block) : safe_join([icon.present? ? ax_icon(icon, class_name: "ax-ico") : nil, label].compact, " ")

    if url.present?
      link_to(url, options) { content }
    else
      button_tag(content, options.reverse_merge(type: "button"))
    end
  end

  def ax_icon_button(label:, icon:, url: nil, variant: :secondary, size: :sm, class_name: nil, **options)
    ax_button(
      nil,
      url,
      variant:,
      size:,
      icon:,
      class_name: ["ax-btn--icon", class_name].compact.join(" "),
      aria: { label: }.merge(options.delete(:aria) || {}),
      title: options.delete(:title).presence || label,
      **options
    )
  end

  def ax_code_snippet(code:, title: nil, label: nil, class_name: nil)
    render "admin/shared/ui/code_snippet", code:, title:, label:, class_name:
  end

  def ax_page_header(title:, subtitle: nil, icon: nil, actions: nil, class_name: nil)
    render "admin/shared/ui/page_header", title:, subtitle:, icon:, actions:, class_name:
  end

  # Cabeçalho operacional do ax-main: eyebrow + título com pills, subtítulo,
  # métricas (array de { value:, label: }) e ações à direita.
  def ax_workspace_heading(title:, eyebrow: nil, icon: nil, subtitle: nil, pills: [], metrics: [], actions: nil, class_name: nil)
    render(
      "admin/shared/ui/workspace_heading",
      title:,
      eyebrow:,
      icon:,
      subtitle:,
      pills: Array(pills),
      metrics: Array(metrics),
      actions:,
      class_name:
    )
  end

  # Composição de processos operacionais com etapas, conteúdo principal e
  # inspector. A estrutura interna usa o contrato compartilhado `.ax-workflow`.
  def ax_workflow(label:, class_name: nil, data: {}, body: nil, &block)
    render(
      "admin/shared/ui/workflow",
      label:,
      class_name:,
      data:,
      body: block_given? ? capture(&block) : body
    )
  end

  # Board (kanban) reutilizável. `data:` recebe os atributos de comportamento do
  # consumidor (ex.: { controller: "lead-kanban" }); o conteúdo são as colunas.
  def ax_board(data: {}, class_name: nil, label: "Quadro de trabalho", body: nil, &block)
    render(
      "admin/shared/ui/board",
      data:,
      class_name:,
      label:,
      body: block_given? ? capture(&block) : body
    )
  end

  # Coluna do board. `count_data`/`body_data` carregam os hooks do controller
  # (ex.: data-lead-kanban-count, data-lead-kanban-target, data-lead-kanban-status).
  def ax_board_column(title:, eyebrow: nil, count: nil, count_data: {}, body_data: {}, empty_text: nil, class_name: nil, body: nil, &block)
    render(
      "admin/shared/ui/board_column",
      title:,
      eyebrow:,
      count:,
      count_data:,
      body_data:,
      empty_text:,
      class_name:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_panel(title: nil, subtitle: nil, actions: nil, class_name: nil, collapsible: false, collapsed: false, collapse_id: nil, body: nil, &block)
    render(
      "admin/shared/ui/panel",
      title:,
      subtitle:,
      actions:,
      class_name:,
      collapsible:,
      collapsed:,
      collapse_id:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_operational_panel(eyebrow: nil, title: nil, actions: nil, class_name: nil, body: nil, &block)
    render(
      "admin/shared/ui/operational_panel",
      eyebrow:,
      title:,
      actions:,
      class_name:,
      body: block_given? ? capture(&block) : body
    )
  end

  # Lista semântica e compacta de pares rótulo/estado para inspectors e
  # diagnósticos. `value` aceita texto ou HTML seguro, como `ax_badge`.
  def ax_status_list(rows:, class_name: nil, label: nil)
    render(
      "admin/shared/ui/status_list",
      rows: Array(rows),
      class_name:,
      label:
    )
  end

  # Card padrão com header colapsável (chevron) — para telas de trabalho, onde
  # o ax_form_section (contexto de formulário) ficaria sem o chrome de card.
  def ax_collapsible_card(title:, collapse_id:, icon: nil, badge: nil, actions: nil, collapsed: false, class_name: nil, body: nil, &block)
    render(
      "admin/shared/ui/collapsible_card",
      title:,
      collapse_id:,
      icon:,
      badge:,
      actions:,
      collapsed:,
      class_name:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_form_section(title:, eyebrow: nil, icon: nil, actions: nil, collapsed: false, collapse_id: nil, class_name: nil, tooltip: nil, body: nil, &block)
    render(
      "admin/shared/ui/form_section",
      eyebrow:,
      title:,
      icon:,
      actions:,
      collapsed:,
      collapse_id:,
      class_name:,
      tooltip:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_field_grid(columns: 12, gap: :compact, class_name: nil, data: {}, body: nil, &block)
    render(
      "admin/shared/ui/field_grid",
      columns:,
      gap:,
      class_name:,
      data:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_chip_grid(id: nil, class_name: nil, data: {}, body: nil, &block)
    render(
      "admin/shared/ui/chip_grid",
      id:,
      class_name:,
      data:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_inline_notice(tone: :neutral, icon: "info-circle", class_name: nil, body: nil, compact: false, announce: true, &block)
    danger = tone.to_s == "danger"
    render(
      "admin/shared/ui/inline_notice",
      tone:,
      icon:,
      class_name:,
      compact:,
      notice_role: announce ? (danger ? "alert" : "status") : nil,
      aria_live: announce ? (danger ? "assertive" : "polite") : nil,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_field_group(title:, token: nil, actions: nil, class_name: nil, tooltip: nil, body: nil, &block)
    render(
      "admin/shared/ui/field_group",
      title:,
      token:,
      actions:,
      class_name:,
      tooltip:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_field_label(form = nil, method = nil, text:, tooltip: nil, meta: nil, class_name: nil, **options)
    render(
      "admin/shared/ui/field_label",
      form:,
      method:,
      text:,
      tooltip:,
      meta:,
      class_name:,
      options:
    )
  end

  def ax_text_field(form:, method:, label:, tooltip: nil, label_meta: nil, hint: nil, type: :text, class_name: nil, field_class: nil, label_options: {}, clearable: false, **options)
    render(
      "admin/shared/ui/text_field",
      form:,
      method:,
      label:,
      tooltip:,
      label_meta:,
      hint:,
      type:,
      class_name:,
      field_class:,
      label_options:,
      clearable:,
      options:
    )
  end

  # Campo avulso para formulários que não pertencem a um model (OTP, senha de
  # confirmação, destino de teste etc.). Pode compor uma ação acoplada usando
  # o mesmo contrato visual de `ax_input_group`.
  def ax_standalone_field(name:, id:, label:, value: nil, type: :text, hint: nil, action: nil, class_name: nil, input_class: nil, **options)
    render(
      "admin/shared/ui/standalone_field",
      name:,
      id:,
      label:,
      value:,
      type:,
      hint:,
      action:,
      class_name:,
      input_class:,
      options:
    )
  end

  def ax_standalone_select_field(name:, id:, label:, choices:, selected: nil, include_blank: nil, hint: nil, class_name: nil, grouped: false, **options)
    render(
      "admin/shared/ui/standalone_select_field",
      name:,
      id:,
      label:,
      choices:,
      selected:,
      include_blank:,
      hint:,
      class_name:,
      grouped:,
      options:
    )
  end

  def ax_color_field(form:, method:, label:, value:, tooltip: nil, hint: nil, token: nil, default_value: nil, swatch_title: nil, class_name: nil, field_class: nil, color_options: {}, text_options: {})
    render(
      "admin/shared/ui/color_field",
      form:,
      method:,
      label:,
      value:,
      tooltip:,
      hint:,
      token:,
      default_value:,
      swatch_title:,
      class_name:,
      field_class:,
      color_options:,
      text_options:
    )
  end

  def ax_file_field(form:, method:, label:, tooltip: nil, hint: nil, accept: nil, input_id: nil, button_label: "Escolher arquivo", empty_label: "Nenhum arquivo escolhido", class_name: nil, field_class: nil, **options)
    render(
      "admin/shared/ui/file_field",
      form:,
      method:,
      label:,
      tooltip:,
      hint:,
      accept:,
      input_id:,
      button_label:,
      empty_label:,
      class_name:,
      field_class:,
      options:
    )
  end

  def ax_select_field(form:, method:, label:, choices:, select_options: {}, html_options: {}, tooltip: nil, class_name: nil, clearable: false)
    render(
      "admin/shared/ui/select_field",
      form:,
      method:,
      label:,
      choices:,
      select_options:,
      html_options:,
      tooltip:,
      class_name:,
      clearable:
    )
  end

  def ax_autocomplete_select_field(form:, method:, label:, choices:, select_options: {}, html_options: {},
                                   tooltip: nil, class_name: nil, placeholder: nil, create: false,
                                   tags: false, multiple: false, url: nil, search_param: nil,
                                   min_length: nil, tom_select_options: {}, option_descriptions: {}, clearable: false)
    render(
      "admin/shared/ui/autocomplete_select_field",
      form:,
      method:,
      label:,
      choices:,
      select_options:,
      html_options:,
      tooltip:,
      class_name:,
      placeholder:,
      create:,
      tags:,
      multiple:,
      url:,
      search_param:,
      min_length:,
      tom_select_options:,
      option_descriptions:,
      clearable:
    )
  end

  def ax_input_group(prefix: nil, suffix: nil, action: nil, size: :sm, class_name: nil, &block)
    render(
      "admin/shared/ui/input_group",
      prefix:,
      suffix:,
      action:,
      size:,
      class_name:,
      content: capture(&block)
    )
  end

  # Checkbox/radio simples reutilizável (substitui `form-check`/`form-check-input`/`form-check-label`).
  # Para toggles deslizantes use ax_switch_field; para chips de filtro, ax_toggle_chip.
  def ax_check_field(label:, type: :checkbox, form: nil, method: nil, name: nil, value: "1",
                     checked: false, id: nil, class_name: nil, input_html: {})
    render "admin/shared/ui/check_field",
           label:, type:, form:, method:, name:, value:, checked:, id:, class_name:, input_html:
  end

  # Barra de progresso reutilizável (substitui `progress`/`progress-bar` do Bootstrap).
  # tone: :green/:red/:amber/:blue (cor da barra); value: 0-100.
  def ax_progress(value:, tone: nil, class_name: nil, label: nil, data: {})
    render "admin/shared/ui/progress", value:, tone:, class_name:, label:, data:
  end

  # Switch deslizante reutilizável (substitui o markup Bootstrap `form-check form-switch`).
  # Usa com form builder (form:/method:) OU com nome solto (name:/checked:). Atributos extras
  # do input (data-action etc.) via input_html.
  def ax_switch_field(label: nil, form: nil, method: nil, name: nil, checked: false, value: "1",
                      checked_value: "1", unchecked_value: "0", id: nil, class_name: nil, input_html: {})
    render "admin/shared/ui/switch_field",
           label:, form:, method:, name:, checked:, value:,
           checked_value:, unchecked_value:, id:, class_name:, input_html:
  end

  def ax_toggle_chip(form = nil, method = nil, label:, checked_value: "1", unchecked_value: "0", disabled: false, class_name: nil, id: nil, input_data: {}, name: nil, checked: false, include_hidden: true)
    render(
      "admin/shared/ui/toggle_chip",
      form:,
      method:,
      label:,
      checked_value:,
      unchecked_value:,
      disabled:,
      class_name:,
      id:,
      input_data:,
      name:,
      checked:,
      include_hidden:
    )
  end

  def ax_multiselect_field(form:, method:, label:, choices:, selected: [], id: nil, disabled: false, placeholder: "Selecione...", manager: nil, class_name: nil, tooltip: nil, data: {})
    render(
      "admin/shared/ui/multiselect_field",
      form:,
      method:,
      label:,
      choices:,
      selected:,
      id:,
      disabled:,
      placeholder:,
      manager:,
      class_name:,
      tooltip:,
      data:
    )
  end

  def ax_info_badge(label:, value:, tooltip: nil, tone: :default, class_name: nil)
    render "admin/shared/ui/info_badge", label:, value:, tooltip:, tone:, class_name:
  end

  def ax_relationship_select(form:, method:, label:, collection:, value_method:, text_method:, select_options: {}, html_options: {}, action: nil, tooltip: nil, class_name: nil)
    render(
      "admin/shared/ui/relationship_select",
      form:,
      method:,
      label:,
      collection:,
      value_method:,
      text_method:,
      select_options:,
      html_options:,
      action:,
      tooltip:,
      class_name:
    )
  end

  def ax_currency_field(form:, method:, label:, tooltip: nil, class_name: nil, input_class: nil, **options)
    render(
      "admin/shared/ui/currency_field",
      form:,
      method:,
      label:,
      tooltip:,
      class_name:,
      input_class:,
      options:
    )
  end

  def ax_number_field(form:, method:, label:, tooltip: nil, hint: nil, class_name: nil, input_class: nil, clearable: false, **options)
    render(
      "admin/shared/ui/number_field",
      form:,
      method:,
      label:,
      tooltip:,
      hint:,
      class_name:,
      input_class:,
      clearable:,
      options:
    )
  end

  def ax_date_field(form:, method:, label:, tooltip: nil, class_name: nil, input_class: nil, clearable: false, **options)
    render(
      "admin/shared/ui/date_field",
      form:,
      method:,
      label:,
      tooltip:,
      class_name:,
      input_class:,
      clearable:,
      options:
    )
  end

  def ax_measure_field(form:, method:, label:, unit:, tooltip: nil, class_name: nil, input_class: nil, **options)
    render(
      "admin/shared/ui/measure_field",
      form:,
      method:,
      label:,
      unit:,
      tooltip:,
      class_name:,
      input_class:,
      options:
    )
  end

  def ax_quick_modal(id:, title:, size: :md, footer: nil, class_name: nil, data: {}, body: nil, &block)
    render(
      "admin/shared/ui/quick_modal",
      id:,
      title:,
      size:,
      footer:,
      class_name:,
      data:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_radio_group(form:, method:, label:, choices:, class_name: nil, item_class: nil, disabled: false, input_data: {})
    render(
      "admin/shared/ui/radio_group",
      form:,
      method:,
      label:,
      choices:,
      class_name:,
      item_class:,
      disabled:,
      input_data:
    )
  end

  def ax_range_field(form:, method:, label:, value:, suffix: nil, hint: nil, class_name: nil, input_data: {}, output_data: {}, **options)
    render(
      "admin/shared/ui/range_field",
      form:,
      method:,
      label:,
      value:,
      suffix:,
      hint:,
      class_name:,
      input_data:,
      output_data:,
      options:
    )
  end

  def ax_dynamic_list_field(label:, values:, input_name:, placeholder: nil, add_label: "Adicionar", class_name: nil)
    render(
      "admin/shared/ui/dynamic_list_field",
      label:,
      values:,
      input_name:,
      placeholder:,
      add_label:,
      class_name:
    )
  end

  def ax_file_upload_button(label:, input_id:, form: nil, method: nil, multiple: true, direct_upload: false, accept: nil, capture: nil, input_data: {}, label_data: {}, input_class: nil, input_options: {}, class_name: "ax-btn ax-btn--sm ax-upload-button")
    render(
      "admin/shared/ui/file_upload_button",
      label:,
      input_id:,
      form:,
      method:,
      multiple:,
      direct_upload:,
      accept:,
      capture:,
      input_data:,
      label_data:,
      input_class:,
      input_options:,
      class_name:
    )
  end

  def ax_attachment_item(attachment:, url:, title: nil, meta: nil, image_preview: false, actions: nil)
    render(
      "admin/shared/ui/attachment_item",
      attachment:,
      url:,
      title: title.presence || attachment.filename.to_s,
      meta:,
      image_preview:,
      actions:
    )
  end

  def ax_media_tile(link_url:, image_source:, caption:, position:, root_class: nil, data: {}, hidden_from_site: false, image_class: nil, fallback_image_sources: [], top_right: nil, center: nil, bottom_left: nil, bottom_right: nil)
    render(
      "admin/shared/ui/media_tile",
      link_url:,
      image_source:,
      caption:,
      position:,
      root_class:,
      data:,
      hidden_from_site:,
      image_class:,
      fallback_image_sources:,
      top_right:,
      center:,
      bottom_left:,
      bottom_right:
    )
  end

  def ax_media_grid(class_name: nil, data: {}, body: nil, &block)
    render(
      "admin/shared/ui/media_grid",
      class_name:,
      data:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_media_preview(label: nil, icon: "image", image: nil, variant: :desktop, size: :default, empty_text: "Sem imagem", class_name: nil, body: nil, &block)
    render(
      "admin/shared/ui/media_preview",
      label:,
      icon:,
      image:,
      variant:,
      size:,
      empty_text:,
      class_name:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_media_source_notice(title:, description:, icon: "building", action: nil)
    render(
      "admin/shared/ui/media_source_notice",
      title:,
      description:,
      icon:,
      action:
    )
  end

  def ax_media_upload_panel(title:, description:, icon: "images", controls: nil, actions: nil, feedback: nil, hidden_fields: nil, class_name: nil)
    render(
      "admin/shared/ui/media_upload_panel",
      title:,
      description:,
      icon:,
      controls:,
      actions:,
      feedback:,
      hidden_fields:,
      class_name:
    )
  end

  def ax_portal_publication_section(title:, collapse_id:, class_name: nil, body: nil, &block)
    render(
      "admin/shared/ui/portal_publication_section",
      title:,
      collapse_id:,
      class_name:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_portal_publication_option(form:, method:, label:, class_name: nil, body: nil, &block)
    render(
      "admin/shared/ui/portal_publication_option",
      form:,
      method:,
      label:,
      class_name:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_record_item(title:, eyebrow: nil, meta: nil, icon: nil, class_name: nil, data: {}, actions: nil, body: nil, &block)
    render(
      "admin/shared/ui/record_item",
      title:,
      eyebrow:,
      meta:,
      icon:,
      class_name:,
      data:,
      actions:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_aside_panel(title:, token: nil, rail_label:, rail_icon: "layout-sidebar-inset-reverse", collapse_icon: "arrow-bar-right", collapse_label: nil, controller: "ax-aside", class_name: nil, rail_class: nil, rail_body: nil, panel_class: nil, header_class: nil, actions_class: nil, toggle_class: nil, body: nil, &block)
    render(
      "admin/shared/ui/aside_panel",
      title:,
      token:,
      rail_label:,
      rail_icon:,
      collapse_icon:,
      collapse_label: collapse_label.presence || "Recolher #{title}",
      controller:,
      class_name:,
      rail_class:,
      rail_body:,
      panel_class:,
      header_class:,
      actions_class:,
      toggle_class:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_filter_section(title:, icon: nil, count: nil, open: false, class_name: nil, body: nil, &block)
    render(
      "admin/shared/ui/filter_section",
      title:,
      icon:,
      count:,
      open:,
      class_name:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_filter_check(name:, value: "1", checked: false, label:, id: nil, class_name: nil)
    render(
      "admin/shared/ui/filter_check",
      name:,
      value:,
      checked:,
      label:,
      id:,
      class_name:
    )
  end

  def ax_metric_card(label:, value:, badge: nil, hint: nil, progress: nil, class_name: nil)
    render "admin/shared/ui/metric_card", label:, value:, badge:, hint:, progress:, class_name:
  end

  # Toggle reutilizável "+ equipe": recorta uma listagem pela subárvore de gestão.
  # Só renderiza quando o usuário tem escopo "team" no recurso E possui subordinados
  # (team_available?). Opt-out: vem marcado por padrão (include_team?); o link alterna
  # team=0/1 preservando os demais filtros da URL. Não usa form (seguro dentro de filtros).
  def ax_team_toggle(resource, label: "+ equipe", icon: "people-fill", class_name: nil)
    return unless team_available?(resource)

    render "admin/shared/ui/team_toggle",
           checked: include_team?(resource),
           label:, icon:, class_name:
  end

  def ax_field(label: nil, hint: nil, error: nil, class_name: nil, &block)
    render "admin/shared/ui/field", label:, hint:, error:, class_name:, content: capture(&block)
  end

  def ax_error_summary(record, title: "Ops! Verifique os erros abaixo:", grouped_errors: nil, labels: {}, order: nil)
    return if record.blank? || record.errors.blank?

    render "admin/shared/ui/error_summary", record:, title:, grouped_errors:, labels:, order:
  end

  def ax_form_actions(cancel_path: nil, submit_label: nil, form: nil, cancel_label: "Cancelar", sticky: true, class_name: nil, &block)
    render(
      "admin/shared/ui/form_actions",
      cancel_path:,
      submit_label:,
      form:,
      cancel_label:,
      sticky:,
      class_name:,
      body: block_given? ? capture(&block) : nil
    )
  end

  def ax_sticky_action_footer(meta: nil, sticky: true, class_name: nil, body: nil, &block)
    render(
      "admin/shared/ui/sticky_action_footer",
      meta:,
      sticky:,
      class_name:,
      body: block_given? ? capture(&block) : body
    )
  end

  def ax_filter_form(url:, method: :get, reset_path: nil, submit_label: "Filtrar", reset_label: "Limpar", filter_label: "Filtros", class_name: nil, **options, &block)
    form_with(url:, method:, local: true, **options) do |form|
      fields = capture(form, &block)
      render(
        "admin/shared/ui/filter_form",
        fields:,
        reset_path:,
        submit_label:,
        reset_label:,
        filter_label:,
        class_name:
      )
    end
  end

  def ax_empty_state(title:, description: nil, icon: "inbox", action: nil, compact: false, class_name: nil)
    render "admin/shared/ui/empty_state", title:, description:, icon:, action:, compact:, class_name:
  end

  def ax_pagination(collection, params: nil, class_name: nil, show_summary: true, **options)
    return "".html_safe unless collection.respond_to?(:total_pages) && collection.total_pages.to_i > 1

    pagination = will_paginate(
      collection,
      {
        renderer: WillPaginate::ActionView::AxPaginationRenderer,
        params: params || request.query_parameters.except(:page),
        previous_label: safe_join([ax_icon("chevron-left"), tag.span("Anterior", class: "ax-pagination__nav-label")], " "),
        next_label: safe_join([tag.span("Próxima", class: "ax-pagination__nav-label"), ax_icon("chevron-right")], " "),
        inner_window: 2,
        outer_window: 1
      }.merge(options.except(:class, :container, :renderer))
    )

    tag.nav(class: ["ax-pagination", class_name].compact.join(" "), role: "navigation", aria: { label: "Paginação" }) do
      safe_join(
        [
          (tag.div(ax_pagination_summary(collection), class: "ax-pagination__summary") if show_summary),
          tag.div(pagination, class: "ax-pagination__controls")
        ].compact
      )
    end
  end

  def ax_pagination_summary(collection)
    total = collection.total_entries.to_i
    return "Nenhum registro" if total.zero?

    current_page = collection.current_page.to_i
    per_page = collection.per_page.to_i
    first_item = ((current_page - 1) * per_page) + 1
    last_item = [current_page * per_page, total].min

    "#{number_with_delimiter(first_item)}-#{number_with_delimiter(last_item)} de #{number_with_delimiter(total)}"
  end

  private

  def ax_lead_label_tone(label)
    label.color.to_s.presence || "gray"
  end

  def ax_merge_class_options(options, classes)
    merged = options.dup
    merged[:class] = [*classes, merged[:class]].compact.join(" ")
    merged
  end
end
