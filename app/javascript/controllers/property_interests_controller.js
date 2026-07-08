import { Controller } from "@hotwired/stimulus"

// Imóveis de interesse do lead (painel de contexto do WhatsApp).
// O autocomplete em si é o tom-select (data-controller="tom-select" no select,
// com URL remota); aqui só orquestramos create/destroy via fetch e trocamos os
// chips renderizados pelo servidor — mesmo padrão do lead_labels_controller.
//
//   <div data-controller="property-interests"
//        data-property-interests-create-url-value="/admin/leads/1/property_interests">
//     <div data-property-interests-target="list">…chips…</div>
//     <select data-property-interests-target="select"
//             data-action="change->property-interests#add">…</select>
//   </div>
export default class extends Controller {
  static targets = ["list", "select", "error"]
  static values = { createUrl: String }

  connect() {
    this.busy = false
  }

  add(event) {
    const habitationId = event.target.value
    if (!habitationId) return

    const body = new FormData()
    body.append("property_interest[habitation_id]", habitationId)
    this.request(this.createUrlValue, "POST", body).then((ok) => {
      if (ok) this.clearSelect()
    })
  }

  remove(event) {
    const url = event.currentTarget.dataset.url
    if (url) this.request(url, "DELETE")
  }

  clearSelect() {
    if (!this.hasSelectTarget) return
    const ts = this.selectTarget.tomselect
    if (ts) {
      ts.clear(true)
      ts.blur()
    } else {
      this.selectTarget.value = ""
    }
  }

  async request(url, method, body = null) {
    if (this.busy) return false
    this.busy = true
    try {
      const response = await fetch(url, {
        method,
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken(),
          "X-Requested-With": "XMLHttpRequest"
        },
        body
      })
      const data = await response.json().catch(() => ({}))

      if (!response.ok) {
        this.showError(data.error || "Não foi possível concluir a ação.")
        return false
      }

      if (typeof data.chips_html === "string" && this.hasListTarget) {
        this.listTarget.innerHTML = data.chips_html
      }
      if (this.hasErrorTarget) this.errorTarget.hidden = true
      return true
    } catch (_error) {
      this.showError("Falha de conexão. Tente novamente.")
      return false
    } finally {
      this.busy = false
    }
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
