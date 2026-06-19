import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Configuração das colunas do funil de leads (modal da engrenagem):
// reordenar (drag), renomear, subtítulo, adicionar e remover. Persiste em lote
// via Admin::LeadStatusesController#bulk_update e recarrega a página.
export default class extends Controller {
  static targets = ["list", "template", "error", "submit"]
  static values = { url: String }

  connect() {
    console.log("[lead-status-board] connect", { url: this.urlValue, rows: this.listTarget.querySelectorAll(".lead-status-row").length })
    this.sortable = new Sortable(this.listTarget, {
      animation: 150,
      handle: ".lead-status-row__handle",
      draggable: ".lead-status-row"
    })
  }

  disconnect() {
    this.sortable?.destroy()
  }

  addRow(event) {
    event.preventDefault()
    console.log("[lead-status-board] addRow")
    const fragment = this.templateTarget.content.cloneNode(true)
    this.listTarget.appendChild(fragment)
    const row = this.listTarget.lastElementChild
    row?.querySelector('[data-lead-status-field="name"]')?.focus()
  }

  removeRow(event) {
    event.preventDefault()
    const row = event.target.closest(".lead-status-row")
    if (!row) return
    console.log("[lead-status-board] removeRow", { id: row.dataset.id || "(novo)" })

    if (row.dataset.id) {
      row.dataset.destroy = "true"
      row.hidden = true
    } else {
      row.remove()
    }
  }

  save(event) {
    event.preventDefault()
    console.log("[lead-status-board] save: click recebido")
    this.hideError()

    const statuses = Array.from(this.listTarget.querySelectorAll(".lead-status-row"))
      .map((row) => ({
        id: row.dataset.id || null,
        name: row.querySelector('[data-lead-status-field="name"]')?.value.trim() || "",
        description: row.querySelector('[data-lead-status-field="description"]')?.value.trim() || "",
        _destroy: row.dataset.destroy === "true"
      }))
      .filter((status) => status.id || status.name || status._destroy)

    const active = statuses.filter((status) => !status._destroy)
    if (active.length === 0) {
      this.showError("Mantenha pelo menos um status no funil.")
      return
    }
    if (active.some((status) => !status.name)) {
      this.showError("Todos os status precisam de um nome.")
      return
    }

    console.log("[lead-status-board] save: enviando", statuses)
    this.setLoading(true)

    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({ statuses })
    })
      .then((response) => response.json().then((data) => ({ ok: response.ok, data })))
      .then(({ ok, data }) => {
        console.log("[lead-status-board] save: resposta", { ok, data })
        if (!ok || !data.ok) throw new Error(data.error || "Não foi possível salvar as colunas.")
        // Mantém o loading: a página recarrega e o toast (flash) aparece.
        window.location.reload()
      })
      .catch((error) => {
        console.error("[lead-status-board] save: erro", error)
        this.setLoading(false)
        this.showError(error.message)
      })
  }

  setLoading(loading) {
    if (loading) {
      this.submitOriginalHtml = this.submitTarget.innerHTML
      this.submitTarget.disabled = true
      this.submitTarget.innerHTML = '<span class="ax-spinner"></span> Salvando...'
    } else {
      this.submitTarget.disabled = false
      if (this.submitOriginalHtml != null) this.submitTarget.innerHTML = this.submitOriginalHtml
    }
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  hideError() {
    this.errorTarget.hidden = true
    this.errorTarget.textContent = ""
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
