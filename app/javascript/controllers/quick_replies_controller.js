import { Controller } from "@hotwired/stimulus"

// "⚡ Respostas rápidas" do composer: cartões de apresentação (preenchem o
// campo, editáveis) e modelos aprovados da Meta (definem o modo template).
// Reusa a fiação existente: evento wa-presentation:fill e o select escondido
// do wa-composer — nenhum fluxo novo de envio.
export default class extends Controller {
  static targets = ["popover"]

  connect() {
    this.onDocClick = this.closeOnOutside.bind(this)
    this.onKey = this.closeOnEsc.bind(this)
  }

  disconnect() {
    this.close()
  }

  toggle(event) {
    event.preventDefault()
    if (this.hasPopoverTarget && !this.popoverTarget.hidden) {
      this.close()
    } else {
      this.popoverTarget.hidden = false
      document.addEventListener("click", this.onDocClick)
      document.addEventListener("keydown", this.onKey)
    }
  }

  close() {
    if (this.hasPopoverTarget) this.popoverTarget.hidden = true
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKey)
  }

  useCard(event) {
    const item = event.currentTarget
    window.dispatchEvent(new CustomEvent("wa-presentation:fill", {
      detail: { cardId: item.dataset.cardId, body: item.dataset.body || "" }
    }))
    this.close()
  }

  openCards() {
    this.close()
    document.querySelector("[data-pc-manager-trigger]")?.click()
  }

  useTemplate(event) {
    const select = this.element.closest("form")?.querySelector('[data-wa-composer-target="template"]')
    if (!select) return

    select.value = event.currentTarget.dataset.templateName || ""
    select.dispatchEvent(new Event("change", { bubbles: true }))
    this.close()
  }

  closeOnOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  closeOnEsc(event) {
    if (event.key === "Escape") this.close()
  }
}
