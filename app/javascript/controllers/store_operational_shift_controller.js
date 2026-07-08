import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["active", "field"]

  connect() {
    this.sync()
  }

  sync() {
    const enabled = this.activeTarget.checked

    this.fieldTargets.forEach((field) => {
      field.disabled = !enabled
    })

    this.element.classList.toggle("is-disabled", !enabled)
    this.element.setAttribute("aria-disabled", enabled ? "false" : "true")
  }
}
