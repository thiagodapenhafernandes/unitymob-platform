import { Controller } from "@hotwired/stimulus"
import { formatCurrencyFilter, currencyFilterDigits } from "lib/currency_filter"

export default class extends Controller {
  connect() {
    this.format()
  }

  format(event) {
    this.element.value = formatCurrencyFilter(this.element.value)
  }

  // Get raw numeric value (for form submission)
  get numericValue() {
    return currencyFilterDigits(this.element.value)
  }
}
