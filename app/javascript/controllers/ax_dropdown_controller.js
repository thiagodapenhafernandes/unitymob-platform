import { Controller } from "@hotwired/stimulus"

// Dropdown genérico do novo CRM (substitui bootstrap.Dropdown).
// Uso:
//   <div data-controller="ax-dropdown">
//     <button data-action="ax-dropdown#toggle" data-ax-dropdown-target="trigger">…</button>
//     <div data-ax-dropdown-target="menu" class="ax-menu" hidden>…</div>
//   </div>
export default class extends Controller {
  static targets = ["menu", "trigger"]

  connect() {
    this.onDocClick = this.closeOnOutside.bind(this)
    this.onKey = this.closeOnEsc.bind(this)
    this.closeTimer = null
  }

  disconnect() {
    if (this.closeTimer) window.clearTimeout(this.closeTimer)
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKey)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    this.isOpen ? this.close() : this.open()
  }

  open() {
    if (this.closeTimer) window.clearTimeout(this.closeTimer)
    this.closePeers()
    this.menuTarget.hidden = false
    // Force the initial hidden=false styles to apply before the open state.
    this.menuTarget.getBoundingClientRect()
    this.element.classList.add("is-open")
    this.elevatedContainer = this.element.closest(".ax-property-card")
    if (this.elevatedContainer) this.elevatedContainer.classList.add("has-open-dropdown")
    if (this.hasTriggerTarget) this.triggerTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.onDocClick)
    document.addEventListener("keydown", this.onKey)
  }

  close() {
    this.element.classList.remove("is-open")
    if (this.elevatedContainer) {
      this.elevatedContainer.classList.remove("has-open-dropdown")
      this.elevatedContainer = null
    }
    if (this.hasTriggerTarget) this.triggerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKey)

    if (this.closeTimer) window.clearTimeout(this.closeTimer)
    this.closeTimer = window.setTimeout(() => {
      if (!this.element.classList.contains("is-open")) this.menuTarget.hidden = true
    }, 140)
  }

  get isOpen() {
    return this.element.classList.contains("is-open")
  }

  closePeers() {
    document.querySelectorAll('[data-controller~="ax-dropdown"].is-open').forEach((element) => {
      if (element === this.element) return

      const controller = this.application.getControllerForElementAndIdentifier(element, "ax-dropdown")
      if (controller) controller.close()
    })
  }

  closeOnOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  closeOnEsc(event) {
    if (event.key === "Escape") this.close()
  }
}
