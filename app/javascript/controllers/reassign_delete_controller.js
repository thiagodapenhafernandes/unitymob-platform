import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "name", "select"]

  prepare(event) {
    const trigger = event.currentTarget
    const userId = trigger.dataset.userId
    const userName = trigger.dataset.userName || "este usuário"
    const url = trigger.dataset.url

    if (this.formElement && url) this.formElement.action = url
    if (this.nameElement) this.nameElement.textContent = userName
    if (this.selectElement) this.updateSelectOptions(userId)
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

  get formElement() {
    return this.hasFormTarget ? this.formTarget : document.querySelector("[data-reassign-delete-target~='form']")
  }

  get nameElement() {
    return this.hasNameTarget ? this.nameTarget : document.querySelector("[data-reassign-delete-target~='name']")
  }

  get selectElement() {
    return this.hasSelectTarget ? this.selectTarget : document.querySelector("[data-reassign-delete-target~='select']")
  }
}
