import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { allowedFields: Array }

  connect() {
    this.allowed = new Set(this.allowedFieldsValue)
    this.lockForbiddenFields()
    this.lockAttributeManagers()
  }

  lockForbiddenFields() {
    this.element.querySelectorAll("input[name^='habitation['], select[name^='habitation['], textarea[name^='habitation['], trix-editor[input]").forEach((control) => {
      const name = control.getAttribute("name") || this.trixInputName(control)
      const field = name?.match(/^habitation\[([^\]]+)\]/)?.[1]
      if (!field || this.allowed.has(field)) return

      control.disabled = true
      control.setAttribute("aria-disabled", "true")
      control.closest(".ax-field, .ax-field-group, .ax-toggle-chip, .ax-input-group")?.classList.add("is-policy-locked")
    })
  }

  lockAttributeManagers() {
    this.element.querySelectorAll("[data-action*='attribute-manager#open']").forEach((button) => {
      button.disabled = true
      button.setAttribute("aria-disabled", "true")
      button.title = "Gerenciamento restrito ao administrador"
    })
  }

  trixInputName(editor) {
    const input = document.getElementById(editor.getAttribute("input"))
    return input?.name
  }
}
