import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  select(event) {
    const selectedValue = event.target.value
    const form = this.element.closest('.hero-container').querySelector('form')
    const hiddenInput = form.querySelector('input[name="transaction_type"]')

    if (hiddenInput) {
      hiddenInput.value = selectedValue
    }
  }
}
