import { Controller } from "@hotwired/stimulus"

// Reemite a mudança de um campo como evento global — liga selects distantes
// (ex.: business_type da regra → filtro de gestores por área).
export default class extends Controller {
  static values = { event: String }

  change() {
    if (!this.eventValue) return

    window.dispatchEvent(new CustomEvent(this.eventValue, { detail: { value: this.element.value } }))
  }
}
