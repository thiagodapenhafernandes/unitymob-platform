module PublicFormsHelper
  def public_form_modal(form, trigger_label: nil, trigger_class: nil, trigger: true)
    return unless form&.active? && form.modal_enabled?

    rendered_public_form_modals << form.slug

    render(
      "shared/public_form_modal",
      form: form,
      trigger_label: trigger_label.presence || form.name,
      trigger_class: trigger_class.presence || "inline-flex items-center justify-center gap-2 rounded-lg bg-golden-one px-6 py-3 font-bold text-blue-three hover:bg-golden-two transition-colors",
      trigger: trigger
    )
  end

  # Overlays dos modais ativos ainda não renderizados na página, para os
  # gatilhos #modal-<slug> funcionarem de qualquer lugar do site.
  def public_form_modals_registry
    forms = public_tenant.public_forms.active.where(modal_enabled: true).includes(:fields).where.not(slug: rendered_public_form_modals)
    safe_join(forms.map { |form| public_form_modal(form, trigger: false) })
  end

  # Cores do modal (modal_config) viram variáveis CSS no diálogo; o CSS de cada tema usa com fallback.
  MODAL_COLOR_VARS = {
    "aside_bg" => "--pfm-aside-bg", "aside_fg" => "--pfm-aside-fg", "aside_accent" => "--pfm-aside-accent",
    "body_bg" => "--pfm-body-bg", "submit_bg" => "--pfm-submit-bg", "submit_fg" => "--pfm-submit-fg"
  }.freeze

  def public_form_modal_style(form)
    config = form.modal_config.to_h
    MODAL_COLOR_VARS.filter_map do |key, css_var|
      color = config[key].to_s
      "#{css_var}:#{color}" if color.match?(PublicForm::HEX_COLOR)
    end.join(";")
  end

  # Só no preview do builder: marca a região para as ferramentas de edição ao passar o mouse.
  def public_form_edit_attrs(preview, region, bind: nil, mode: nil)
    return "".html_safe unless preview

    tag.attributes(data: { edit: region, bind: bind, edit_mode: mode })
  end

  def public_form_output_summary(form)
    parts = [form.webhook_url.present? ? "webhook do formulário" : "webhook da conta"]
    parts << "distribui para #{form.distribution_rule.name}" if form.distribution_rule
    parts << "redireciona após enviar" if form.redirect_url.present?
    "Envio: #{parts.join(" · ")}"
  end

  # Texto principal do modal (HTML do Trix), sempre sanitizado na saída.
  def public_form_rich_text(text)
    sanitize(text.to_s, tags: PublicForm::RICH_TEXT_TAGS, attributes: PublicForm::RICH_TEXT_ATTRIBUTES)
  end

  def rendered_public_form_modals
    @rendered_public_form_modals ||= []
  end

  # Área de upload (clique ou arraste). O <input type="file"> nativo fica por baixo: teclado, validação e envio continuam os mesmos.
  def public_form_file_dropzone(field, id:, name:)
    tag.div(class: "public-file", data: {
      controller: "public-file-field",
      public_file_field_max_mb_value: field.file_max_mb,
      public_file_field_max_files_value: field.file_max_files,
      public_file_field_accept_value: field.file_accept
    }) do
      safe_join([
        tag.label(class: "public-file__drop", for: id, data: { public_file_field_target: "drop", action: "dragover->public-file-field#dragOver dragleave->public-file-field#dragLeave drop->public-file-field#drop" }) do
          safe_join([
            tag.input(type: "file", id: id, name: name, required: field.required?, accept: field.file_accept, multiple: field.file_multiple?,
                      class: "public-file__input", data: { max_mb: field.file_max_mb, max_files: field.file_max_files, public_file_field_target: "input", action: "change->public-file-field#changed" }),
            tag.span(tag.i(class: "bi bi-cloud-arrow-up", aria: { hidden: true }), class: "public-file__icon"),
            tag.span(safe_join([tag.strong("Clique para escolher"), " ou arraste #{field.file_multiple? ? "os arquivos" : "o arquivo"} aqui"]), class: "public-file__text"),
            tag.span(field.file_summary, class: "public-file__hint")
          ])
        end,
        tag.ul(class: "public-file__list", hidden: true, data: { public_file_field_target: "list" }),
        tag.p(class: "public-file__error", role: "alert", hidden: true, data: { public_file_field_target: "error" })
      ])
    end
  end

  def public_form_field_input(form_builder, field)
    name = "public_form_submission[#{field.name}]"
    id = "public_form_#{field.public_form_id}_#{field.name}"
    common = {
      id: id,
      name: name,
      required: field.required?,
      placeholder: field.placeholder,
      class: "public-form-modal__control"
    }

    case field.field_type
    when "textarea"
      tag.textarea(**common.merge(rows: field.config.to_h.fetch("rows", 4)))
    when "select"
      tag.select(name: name, id: id, required: field.required?, class: "public-form-modal__control") do
        safe_join([
          tag.option(field.placeholder.presence || "Selecione", value: ""),
          *field.normalized_options.map { |option| tag.option(option["label"], value: option["value"]) }
        ])
      end
    when "radio"
      safe_join(field.normalized_options.map do |option|
        tag.label(class: "public-form-modal__choice") do
          safe_join([
            tag.input(type: "radio", name: name, value: option["value"], required: field.required?),
            tag.span(option["label"])
          ])
        end
      end)
    when "checkbox"
      safe_join(field.normalized_options.map do |option|
        tag.label(class: "public-form-modal__choice") do
          safe_join([
            tag.input(type: "checkbox", name: "#{name}[]", value: option["value"]),
            tag.span(option["label"])
          ])
        end
      end)
    when "file"
      public_form_file_dropzone(field, id: id, name: field.file_multiple? ? "#{name}[]" : name)
    when "hidden"
      tag.input(type: "hidden", name: name, id: id, value: field.config.to_h["value"])
    else
      if field.mask?
        # Com máscara o campo vira texto (um <input type="number"> não aceita parênteses, traços, R$…).
        # `pattern` exige o formato completo e o input-mask formata enquanto digita.
        tag.input(**common.merge(
          type: "text",
          placeholder: field.placeholder.presence || field.mask_hint,
          inputmode: (field.mask_digits_only? ? "numeric" : "text"),
          pattern: field.mask_pattern_source,
          title: "Formato: #{field.mask_hint}",
          maxlength: (field.mask_value == "money" ? nil : field.mask_value.length),
          autocomplete: "off",
          data: { controller: "input-mask", input_mask_pattern_value: field.mask_value, action: "input->input-mask#format" }
        ))
      else
        input_type = field.field_type == "currency" ? "text" : field.field_type
        tag.input(**common.merge(type: input_type, data: field.field_type == "tel" ? { controller: "phone-input" } : nil))
      end
    end
  end
end
