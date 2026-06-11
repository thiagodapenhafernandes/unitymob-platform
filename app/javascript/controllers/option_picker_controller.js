import { Controller } from "@hotwired/stimulus"

// Sincroniza a classe .selected nos .wizard-option-card conforme o radio
// selecionado muda. Cada grupo fica em um <div data-controller="option-picker">.
export default class extends Controller {
  connect() {
    this.sync()
  }

  pick() {
    this.sync()
  }

  sync() {
    const cards = this.element.querySelectorAll(".wizard-option-card")
    cards.forEach((card) => {
      const input = card.querySelector("input[type='radio']")
      if (!input) return
      card.classList.toggle("selected", input.checked)
    })
  }
}
