import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.syncAll()
    this.syncFrame = requestAnimationFrame(() => this.syncAll())
  }

  disconnect() {
    cancelAnimationFrame(this.syncFrame)
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
    chip.classList.toggle("is-disabled", input.disabled)
    if (input.disabled) {
      chip.setAttribute("aria-disabled", "true")
    } else {
      chip.removeAttribute("aria-disabled")
    }
    chip.dataset.checked = input.checked ? "true" : "false"
  }
}
