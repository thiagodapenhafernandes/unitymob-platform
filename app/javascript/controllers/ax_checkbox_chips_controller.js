import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.syncAll()
    requestAnimationFrame(() => this.syncAll())
  }

  sync(event) {
    const input = event.target.closest(".custom-checkbox-card input[type='checkbox'], .ax-toggle-chip__input")
    if (input) this.syncInput(input)
  }

  syncAll() {
    this.element
      .querySelectorAll(".custom-checkbox-card input[type='checkbox'], .ax-toggle-chip__input")
      .forEach((input) => this.syncInput(input))
  }

  syncInput(input) {
    const chip = input.closest(".custom-checkbox-card, .ax-toggle-chip")
    if (!chip) return

    chip.classList.toggle("is-checked", input.checked)
  }
}
