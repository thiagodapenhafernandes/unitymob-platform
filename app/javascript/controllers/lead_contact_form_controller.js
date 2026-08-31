import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["kind", "result", "resultField"]

  connect() {
    this.sync()
  }

  sync() {
    const operational = ["ligacao", "whatsapp", "email", "visita"].includes(this.kindTarget.value)
    this.resultTarget.required = operational
    this.resultTarget.disabled = !operational
    this.resultFieldTarget.hidden = !operational
    if (!operational) this.resultTarget.value = ""
  }
}
