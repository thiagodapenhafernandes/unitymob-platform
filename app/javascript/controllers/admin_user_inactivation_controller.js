import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "name", "select", "reassignFields"]

  connect() {
    this.modeChanged()
  }

  prepare(event) {
    const trigger = event.currentTarget
    const userId = trigger.dataset.userId
    const userName = trigger.dataset.userName || "este usuário"
    const url = trigger.dataset.url

    if (this.formElement && url) this.formElement.action = url
    if (this.nameElement) this.nameElement.textContent = userName
    if (this.selectElement) this.updateSelectOptions(userId)
    this.modeChanged()
  }

  modeChanged() {
    const mode = this.selectedMode
    const reassign = mode !== "detach"

    if (this.reassignFieldsElement) this.reassignFieldsElement.hidden = !reassign
    if (this.selectElement) this.selectElement.required = reassign
  }

  updateSelectOptions(userId) {
    const options = Array.from(this.selectElement.options)

    options.forEach((option) => {
      const currentUser = option.value === userId
      option.disabled = currentUser
      option.hidden = currentUser
    })

    if (this.selectElement.value === userId) {
      const replacement = options.find((option) => !option.disabled && option.value)
      this.selectElement.value = replacement?.value || ""
    }
  }

  get selectedMode() {
    return this.radioButtons.find((radio) => radio.checked)?.value || "reassign"
  }

  get radioButtons() {
    return Array.from((this.formElement || this.element).querySelectorAll("input[name='portfolio_action']"))
  }

  get formElement() {
    return this.hasFormTarget ? this.formTarget : document.querySelector("[data-admin-user-inactivation-target~='form']")
  }

  get nameElement() {
    return this.hasNameTarget ? this.nameTarget : document.querySelector("[data-admin-user-inactivation-target~='name']")
  }

  get selectElement() {
    return this.hasSelectTarget ? this.selectTarget : document.querySelector("[data-admin-user-inactivation-target~='select']")
  }

  get reassignFieldsElement() {
    return this.hasReassignFieldsTarget ? this.reassignFieldsTarget : document.querySelector("[data-admin-user-inactivation-target~='reassignFields']")
  }
}
