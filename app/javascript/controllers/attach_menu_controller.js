import { Controller } from "@hotwired/stimulus"

// Menu "+" do composer (estilo WhatsApp): Documento / Fotos e vídeos / Câmera /
// Áudio. Todos reusam o MESMO input de arquivo do wa-composer — só ajustamos
// accept/capture antes de abrir o seletor. Validação/pipeline continuam iguais.
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

  pick(event) {
    const item = event.currentTarget
    const input = this.fileInput
    if (!input) return

    input.setAttribute("accept", item.dataset.accept || "")
    if (item.dataset.capture) {
      input.setAttribute("capture", item.dataset.capture)
    } else {
      input.removeAttribute("capture")
    }
    this.close()
    input.click()
  }

  get fileInput() {
    return this.element.closest("form")?.querySelector('[data-wa-composer-target="fileInput"]')
  }

  closeOnOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  closeOnEsc(event) {
    if (event.key === "Escape") this.close()
  }
}
