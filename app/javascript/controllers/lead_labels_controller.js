import { Controller } from "@hotwired/stimulus"

// Gerenciador de etiquetas do lead. Carrega o corpo do modal sob demanda e
// aplica mutações (marcar/desmarcar, criar/editar/excluir) via fetch,
// re-renderizando o modal e as tiras de chips na página.
//
//   <div data-controller="lead-labels ax-modal"
//        data-lead-labels-index-url-value="/admin/leads/1/lead_labels"
//        data-lead-labels-lead-id-value="1">
//     <button data-action="lead-labels#open ax-modal#open">Etiquetas</button>
//     <div data-lead-labels-target="body"></div>
//   </div>
export default class extends Controller {
  static targets = ["body", "error"]
  static values = { indexUrl: String, leadId: Number }

  connect() {
    this.loaded = false
    this.busy = false
  }

  // Lazy-load do corpo na primeira abertura (refaz se a carga falhou).
  async open() {
    if (this.loaded) return
    this.loaded = Boolean(await this.request(this.indexUrlValue, "GET"))
  }

  toggle(event) {
    const url = event.currentTarget.dataset.url
    this.request(url, "POST")
  }

  deleteLabel(event) {
    const el = event.currentTarget
    const confirmMsg = el.dataset.confirm
    if (confirmMsg && !window.confirm(confirmMsg)) return
    this.request(el.dataset.url, "DELETE")
  }

  submitForm(event) {
    event.preventDefault()
    const form = event.currentTarget
    const method = (form.dataset.method || "post").toUpperCase()
    this.request(form.action, method, new FormData(form))
  }

  // Sincroniza o color picker com o radio "cor personalizada" da mesma linha:
  // escolher uma cor livre marca o radio e usa o hex como valor submetido.
  pickCustomColor(event) {
    const wrapper = event.currentTarget.closest(".lead-labels__color--custom")
    const radio = wrapper?.querySelector('input[type="radio"]')
    if (!radio) return
    radio.value = event.currentTarget.value
    radio.checked = true
  }

  async request(url, method, body = null) {
    if (this.busy) return
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

      this.render(data)
      return true
    } catch (_error) {
      this.showError("Falha de conexão. Tente novamente.")
      return false
    } finally {
      this.busy = false
    }
  }

  render(data) {
    if (typeof data.manager_html === "string" && this.hasBodyTarget) {
      this.bodyTarget.innerHTML = data.manager_html
    }
    if (typeof data.chips_html === "string") {
      document
        .querySelectorAll(`[data-lead-labels-chips="${this.leadIdValue}"]`)
        .forEach((strip) => { strip.outerHTML = data.chips_html })
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
