module PublicFormsHelper
  def public_form_modal(form, trigger_label: nil, trigger_class: nil)
    return unless form&.active? && form.modal_enabled?

    render(
      "shared/public_form_modal",
      form: form,
      trigger_label: trigger_label.presence || form.name,
      trigger_class: trigger_class.presence || "inline-flex items-center justify-center gap-2 rounded-lg bg-golden-one px-6 py-3 font-bold text-blue-three hover:bg-golden-two transition-colors"
    )
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
    when "hidden"
      tag.input(type: "hidden", name: name, id: id, value: field.config.to_h["value"])
    else
      input_type = field.field_type == "currency" ? "text" : field.field_type
      tag.input(**common.merge(type: input_type, data: field.field_type == "tel" ? { controller: "phone-input" } : nil))
    end
  end
end
