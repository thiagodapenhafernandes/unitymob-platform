import { Controller } from "@hotwired/stimulus"

// Modal genérico do novo CRM (substitui bootstrap.Modal).
// Uso:
//   <div data-controller="ax-modal">
//     <button data-action="ax-modal#open">Abrir</button>
//     <div data-ax-modal-target="overlay" class="ax-modal-overlay" hidden
//          data-action="click->ax-modal#backdropClose">
//       <div class="ax-modal-panel" role="dialog" aria-modal="true">
//         <button data-action="ax-modal#close">×</button> …
//       </div>
//     </div>
//   </div>
// Abrir de fora: dispare o evento ou use um trigger com data-action.
export default class extends Controller {
  static targets = ["overlay"]
  static values = { open: { type: Boolean, default: false } }

  connect() {
    this.onKey = this.closeOnEsc.bind(this)
    this.onDocumentClick = this.openFromTrigger.bind(this)
    this.onRequestedOpen = this.open.bind(this)
    this.onRequestedClose = this.close.bind(this)
    document.addEventListener("click", this.onDocumentClick)
    this.element.addEventListener("ax-modal:open", this.onRequestedOpen)
    this.element.addEventListener("ax-modal:close", this.onRequestedClose)
    if (this.openValue) this.open()
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
    this.element.removeEventListener("ax-modal:open", this.onRequestedOpen)
    this.element.removeEventListener("ax-modal:close", this.onRequestedClose)
    document.removeEventListener("keydown", this.onKey)
    this.unlockScroll()
  }

  open(event) {
    if (event) event.preventDefault()
    this.overlayTarget.hidden = false
    this.overlayTarget.setAttribute("aria-hidden", "false")
    this.lockScroll()
    document.addEventListener("keydown", this.onKey)
    const focusable = this.overlayTarget.querySelector("[autofocus], input, button, [tabindex]")
    if (focusable) focusable.focus()
    this.dispatchModalEvent("opened")
  }

  close(event) {
    if (event) event.preventDefault()
    this.overlayTarget.hidden = true
    this.overlayTarget.setAttribute("aria-hidden", "true")
    this.unlockScroll()
    document.removeEventListener("keydown", this.onKey)
    this.dispatchModalEvent("closed")
  }

  backdropClose(event) {
    if (event.target === this.overlayTarget) this.close()
  }

  closeOnEsc(event) {
    if (event.key === "Escape") this.close()
  }

  openFromTrigger(event) {
    const trigger = event.target.closest("[data-ax-modal-open]")
    if (!trigger || !this.matchesTrigger(trigger.dataset.axModalOpen)) return

    event.preventDefault()
    this.open()
  }

  lockScroll() {
    document.documentElement.style.overflow = "hidden"
  }

  unlockScroll() {
    document.documentElement.style.overflow = ""
  }

  matchesTrigger(target) {
    if (!target) return false

    return target === `#${this.element.id}` || target === this.element.id
  }

  dispatchModalEvent(name) {
    this.element.dispatchEvent(new CustomEvent(`ax-modal:${name}`, { bubbles: true }))
  }
}
