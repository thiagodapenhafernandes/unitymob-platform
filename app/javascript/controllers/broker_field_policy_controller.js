import { Controller } from "@hotwired/stimulus"

// Trava visualmente, para o corretor restrito, tudo que a matriz
// Habitations::BrokerEditPolicy não libera. Só é conectado quando
// broker_restricted_habitation_edit? é true (ver _form.html.erb).
export default class extends Controller {
  static values = { allowedFields: Array }

  connect() {
    this.allowed = new Set(this.allowedFieldsValue)
    this.lockForbiddenFields()
    this.lockAttributeManagers()
    this.lockMarkedControls()
  }

  lockForbiddenFields() {
    this.element.querySelectorAll(
      "input[name^='habitation['], select[name^='habitation['], textarea[name^='habitation['], trix-editor[input]"
    ).forEach((control) => {
      const name = control.getAttribute("name") || this.trixInputName(control)
      if (this.fieldAllowed(name)) return

      this.disableControl(control)
    })
  }

  // Reconhece paths aninhados (ex.: habitation[address_attributes][imediacoes]) e
  // compara tanto o topo ("address_attributes") quanto o path pontilhado
  // ("address_attributes.imediacoes") com a lista liberada.
  fieldAllowed(name) {
    if (!name) return false

    const segments = Array.from(name.matchAll(/\[([^\]]+)\]/g)).map((match) => match[1])
    if (segments.length === 0) return false

    return this.allowed.has(segments[0]) || this.allowed.has(segments.join("."))
  }

  disableControl(control) {
    if (control.tagName === "TRIX-EDITOR") {
      control.setAttribute("contenteditable", "false")
      control.setAttribute("disabled", "disabled")
      const toolbarId = control.getAttribute("toolbar")
      if (toolbarId) document.getElementById(toolbarId)?.setAttribute("hidden", "hidden")
      const inputId = control.getAttribute("input")
      if (inputId) document.getElementById(inputId)?.setAttribute("disabled", "disabled")
    } else {
      control.disabled = true
      control.setAttribute("aria-disabled", "true")
    }

    control.closest(".ax-field, .ax-field-group, .ax-toggle-chip, .ax-input-group, .ax-rich-text-control")
      ?.classList.add("is-policy-locked")
  }

  lockAttributeManagers() {
    this.element.querySelectorAll("[data-action*='attribute-manager#open']").forEach((button) => {
      button.disabled = true
      button.setAttribute("aria-disabled", "true")
      button.title = "Gerenciamento restrito ao administrador"
    })
  }

  // Widgets auxiliares sem name="habitation[...]" que dirigem um campo bloqueado
  // (ex.: seletor "Tipo de cadastro" ui_cadastro_type) e botões de criar/adicionar.
  // Marcados na view com data-broker-field-policy-lock.
  lockMarkedControls() {
    this.element.querySelectorAll("[data-broker-field-policy-lock]").forEach((control) => {
      control.disabled = true
      control.setAttribute("aria-disabled", "true")
      control.classList.add("is-policy-locked")
    })
  }

  trixInputName(editor) {
    const input = document.getElementById(editor.getAttribute("input"))
    return input?.name
  }
}
