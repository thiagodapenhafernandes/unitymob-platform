import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["control", "description"]
  static values = { options: Object }

  connect() { this.update() }

  update() {
    this.descriptionTarget.textContent = this.optionsValue[this.controlTarget.value] || ""
  }
}
