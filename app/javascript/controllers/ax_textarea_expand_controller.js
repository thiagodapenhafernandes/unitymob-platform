import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["field", "button"]
  static values = { compactRows: { type: Number, default: 8 }, expandedRows: { type: Number, default: 20 } }

  toggle() {
    const expanded = this.buttonTarget.getAttribute("aria-expanded") !== "true"
    this.fieldTarget.rows = expanded ? this.expandedRowsValue : this.compactRowsValue
    this.buttonTarget.setAttribute("aria-expanded", String(expanded))
    this.buttonTarget.textContent = expanded ? "Recolher editor" : "Expandir editor"
  }
}
