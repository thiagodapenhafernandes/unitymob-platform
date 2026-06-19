import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "error", "submit"]
  static values = {
    selectId: String,
    focusSelector: String,
    valueKey: String,
    labelKey: String
  }

  connect() {
    this.shownHandler = () => this.shown()
    this.hiddenHandler = () => this.hidden()
    this.element.addEventListener("ax-modal:opened", this.shownHandler)
    this.element.addEventListener("ax-modal:closed", this.hiddenHandler)
  }

  disconnect() {
    this.element.removeEventListener("ax-modal:opened", this.shownHandler)
    this.element.removeEventListener("ax-modal:closed", this.hiddenHandler)
  }

  shown() {
    this.clearError()
    this.element.classList.add("ax-quick-modal--active")
    this.focusInitialField()
  }

  hidden() {
    this.element.classList.remove("ax-quick-modal--active")
  }

  async submit(event) {
    event.preventDefault()
    this.clearError()
    this.setSubmitting(true)

    try {
      const response = await fetch(this.formTarget.action, {
        method: this.formTarget.method || "POST",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: new FormData(this.formTarget)
      })
      const payload = await this.parseJson(response)

      if (!response.ok) {
        this.showError(this.errorMessage(payload))
        return
      }

      this.selectRecord(payload)
      this.formTarget.reset()
      this.hideModal()
    } catch (_error) {
      this.showError("Erro de comunicação ao salvar o registro.")
    } finally {
      this.setSubmitting(false)
    }
  }

  selectRecord(payload) {
    const select = document.getElementById(this.selectIdValue)
    if (!select) return

    const value = String(payload[this.valueKey] ?? "")
    const label = String(payload[this.labelKey] ?? "")
    if (!value) return

    if (!Array.from(select.options).some((option) => option.value === value)) {
      select.add(new Option(label || value, value, true, true))
    }
    select.value = value

    if (select.tomselect) {
      select.tomselect.addOption({ value, text: label || value })
      select.tomselect.setValue(value, true)
    }

    select.dispatchEvent(new Event("change", { bubbles: true }))
  }

  focusInitialField() {
    if (!this.hasFocusSelectorValue) return
    this.element.querySelector(this.focusSelectorValue)?.focus()
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.hidden = true
  }

  setSubmitting(submitting) {
    if (!this.hasSubmitTarget) return
    this.submitTargets.forEach((button) => {
      if (submitting) {
        button.setAttribute("disabled", "disabled")
      } else {
        button.removeAttribute("disabled")
      }
    })
  }

  hideModal() {
    this.element.dispatchEvent(new CustomEvent("ax-modal:close", { bubbles: true }))
  }

  async parseJson(response) {
    try {
      return await response.json()
    } catch (_error) {
      return {}
    }
  }

  errorMessage(payload) {
    const errors = Array.isArray(payload.errors) ? payload.errors : ["Não foi possível salvar o registro."]
    return errors.join(" ")
  }

  get valueKey() {
    return this.hasValueKeyValue ? this.valueKeyValue : "id"
  }

  get labelKey() {
    return this.hasLabelKeyValue ? this.labelKeyValue : "name"
  }
}
