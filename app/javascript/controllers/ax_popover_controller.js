import { Controller } from "@hotwired/stimulus"

// Ciclo compartilhado de popovers. Os consumidores mantêm conteúdo e ações.
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
    if (this.hasPopoverTarget && !this.popoverTarget.hidden) this.close()
    else this.open()
  }

  open() {
    this.popoverTarget.hidden = false
    this.listen()
  }

  close() {
    if (this.hasPopoverTarget) this.popoverTarget.hidden = true
    this.stopListening()
  }

  listen() {
    document.addEventListener("click", this.onDocClick)
    document.addEventListener("keydown", this.onKey)
  }

  stopListening() {
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKey)
  }

  closeOnOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  closeOnEsc(event) {
    if (event.key === "Escape") this.close()
  }
}
