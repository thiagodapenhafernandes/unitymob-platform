import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rent", "condo", "iptu", "total"]

  connect() {
    this.calculate()
  }

  calculate() {
    const rent = this.parseCurrency(this.rentTarget.value)
    const condo = this.parseCurrency(this.condoTarget.value)
    const iptu = this.parseCurrency(this.iptuTarget.value)

    if (rent <= 0) {
      this.totalTarget.value = this.formatCurrency(0)
      return
    }

    const total = rent + condo + iptu

    this.totalTarget.value = this.formatCurrency(total)
  }

  parseCurrency(value) {
    if (!value) return 0
    // Remove non-numeric characters except comma
    // Example: "R$ 1.200,50" -> "1200,50" -> 1200.50
    return parseFloat(value.replace(/[^\d,]/g, '').replace(',', '.')) || 0
  }

  formatCurrency(value) {
    return value.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }
}
