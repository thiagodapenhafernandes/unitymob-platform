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
    this.onTriggerKeydown = this.handleTriggerKeydown.bind(this)
    this.onMenuKeydown = this.handleMenuKeydown.bind(this)
    this.closeTimer = null

    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-haspopup", "menu")
      this.triggerTarget.setAttribute("aria-expanded", "false")
      this.triggerTarget.addEventListener("keydown", this.onTriggerKeydown)
    }

    this.menuTarget.setAttribute("role", "menu")
    if (!this.menuTarget.id) this.menuTarget.id = `ax-dropdown-menu-${this.uniqueId()}`
    if (this.hasTriggerTarget) this.triggerTarget.setAttribute("aria-controls", this.menuTarget.id)
    this.menuTarget.addEventListener("keydown", this.onMenuKeydown)
    this.menuItems.forEach((item) => item.setAttribute("role", "menuitem"))
  }

  disconnect() {
    if (this.closeTimer) window.clearTimeout(this.closeTimer)
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKey)
    if (this.hasTriggerTarget) this.triggerTarget.removeEventListener("keydown", this.onTriggerKeydown)
    this.menuTarget.removeEventListener("keydown", this.onMenuKeydown)
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

  close(options = {}) {
    this.element.classList.remove("is-open")
    if (this.elevatedContainer) {
      this.elevatedContainer.classList.remove("has-open-dropdown")
      this.elevatedContainer = null
    }
    if (this.hasTriggerTarget) this.triggerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKey)
    if (options.restoreFocus && this.hasTriggerTarget) this.triggerTarget.focus()

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
    if (event.key !== "Escape" || !this.isOpen) return

    event.preventDefault()
    this.close({ restoreFocus: true })
  }

  handleTriggerKeydown(event) {
    if (!["ArrowDown", "ArrowUp"].includes(event.key)) return

    event.preventDefault()
    if (!this.isOpen) this.open()
    const items = this.menuItems
    const item = event.key === "ArrowUp" ? items[items.length - 1] : items[0]
    if (item) item.focus()
  }

  handleMenuKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close({ restoreFocus: true })
      return
    }

    if (event.key === "Tab") {
      this.close()
      return
    }

    const items = this.menuItems
    if (items.length === 0) return
    const currentIndex = items.indexOf(document.activeElement)
    let nextIndex

    if (event.key === "Home") nextIndex = 0
    else if (event.key === "End") nextIndex = items.length - 1
    else if (event.key === "ArrowDown") nextIndex = currentIndex < 0 ? 0 : (currentIndex + 1) % items.length
    else if (event.key === "ArrowUp") nextIndex = currentIndex < 0 ? items.length - 1 : (currentIndex - 1 + items.length) % items.length
    else return

    event.preventDefault()
    items[nextIndex].focus()
  }

  get menuItems() {
    return Array.from(this.menuTarget.querySelectorAll('.ax-menu__item, .dropdown-item, [role="menuitem"]')).filter((item) => {
      return !item.hidden && !item.closest("[hidden]") && item.getAttribute("aria-disabled") !== "true" && !item.disabled
    })
  }

  uniqueId() {
    return Math.random().toString(36).slice(2, 10)
  }
}
