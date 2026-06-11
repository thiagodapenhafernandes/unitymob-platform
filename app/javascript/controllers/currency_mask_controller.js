import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.format()
  }

  format(event) {
    let value = this.element.value.replace(/\D/g, '')

    if (value === '') {
      this.element.value = ''
      return
    }

    // Convert to number and format
    const numberValue = parseInt(value)

    // Format as Brazilian currency
    this.element.value = new Intl.NumberFormat('pt-BR', {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0
    }).format(numberValue)
  }

  // Get raw numeric value (for form submission)
  get numericValue() {
    return this.element.value.replace(/\D/g, '')
  }
}
