import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "submit", "result", "payload", "details"]

  refresh() {
    const id = crypto.randomUUID()
    this.formTarget.elements.namedItem("webhook_test[event_id]").value = id
    this.formTarget.elements.namedItem("webhook_test[transaction_id]").value = id
    this.formTarget.elements.namedItem("webhook_test[event_timestamp]").value = Math.floor(Date.now() / 1000)
    this.resultTarget.textContent = ""
    this.detailsTarget.hidden = true
  }

  async send(event) {
    event.preventDefault()
    if (this.submitTarget.disabled || !this.formTarget.reportValidity()) return
    this.submitTarget.disabled = true
    this.resultTarget.textContent = "Enviando teste…"
    try {
      const response = await fetch(this.formTarget.action, {
        method: "POST", body: new FormData(this.formTarget),
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content }
      })
      const result = await response.json()
      this.resultTarget.textContent = result.errors?.join(" ") || result.message || "Não foi possível enviar o teste."
      if (result.payload) {
        this.payloadTarget.textContent = JSON.stringify(result.payload, null, 2)
        this.detailsTarget.hidden = false
      }
    } catch {
      this.resultTarget.textContent = "Não foi possível confirmar o envio. Verifique a conexão antes de tentar novamente."
    } finally {
      this.submitTarget.disabled = false
    }
  }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.payloadTarget.textContent)
      this.resultTarget.textContent = "Payload copiado."
    } catch {
      this.resultTarget.textContent = "Não foi possível copiar. Selecione o payload para copiar manualmente."
    }
  }
}
