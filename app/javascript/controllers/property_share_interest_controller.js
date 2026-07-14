import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "notice"]
  static values = { url: String, errorMessage: String }

  interest(event) { this.habitationId = event.currentTarget.dataset.habitationId; this.send({}) }
  identify(event) { event.preventDefault(); const data = new FormData(event.currentTarget); this.send({ name: data.get("name"), phone: data.get("phone") }) }
  close() { this.dialogTarget.close() }

  async send(identity) {
    const body = new FormData(); body.append("habitation_id", this.habitationId)
    Object.entries(identity).forEach(([key, value]) => body.append(key, value))
    const response = await fetch(this.urlValue, { method: "POST", headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "", Accept: "application/json" }, body })
    const payload = await response.json()
    if (payload.requires_identity) return this.dialogTarget.showModal()
    if (!response.ok) return this.show(payload.error || this.errorMessageValue)
    this.dialogTarget.close(); this.show(payload.message)
  }

  show(message) { this.noticeTarget.textContent = message; this.noticeTarget.hidden = false }
}
