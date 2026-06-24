import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "filename"]
  static values = {
    emptyLabel: { type: String, default: "Nenhum arquivo escolhido" }
  }

  connect() {
    this.sync()
  }

  sync() {
    if (!this.hasInputTarget || !this.hasFilenameTarget) return

    const names = Array.from(this.inputTarget.files || []).map((file) => file.name)
    this.filenameTarget.textContent = names.length ? names.join(", ") : this.emptyLabelValue
  }
}
