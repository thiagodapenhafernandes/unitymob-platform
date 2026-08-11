import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "drawer", "advanced", "advancedToggle", "advancedPanel", "advancedIcon"]
  static classes = ["open", "closing"]

  connect() {
    this.boundCloseOnEscape = this.closeOnEscape.bind(this)
    this.transitionDuration = 320
    this.closeTimer = null
    this.advancedOpen = false
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundCloseOnEscape)
    this.unlockScroll()
    window.clearTimeout(this.closeTimer)
  }

  open(event) {
    if (event) event.preventDefault()

    window.clearTimeout(this.closeTimer)
    this.element.classList.remove(this.closingClass)
    this.element.classList.add(this.openClass)
    this.drawerTarget.setAttribute("aria-hidden", "false")
    this.buttonTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("keydown", this.boundCloseOnEscape)
    this.lockScroll()

    window.requestAnimationFrame(() => {
      const focusable = this.drawerTarget.querySelector("input, select, button, a[href]")
      if (focusable) focusable.focus({ preventScroll: true })
    })
  }

  close(event) {
    if (event) event.preventDefault()
    if (!this.element.classList.contains(this.openClass)) return

    this.element.classList.add(this.closingClass)
    this.element.classList.remove(this.openClass)
    this.drawerTarget.setAttribute("aria-hidden", "true")
    this.buttonTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("keydown", this.boundCloseOnEscape)

    window.clearTimeout(this.closeTimer)
    this.closeTimer = window.setTimeout(() => {
      this.element.classList.remove(this.closingClass)
      this.unlockScroll()
      this.buttonTarget.focus({ preventScroll: true })
    }, this.transitionDuration)
  }

  toggleAdvanced(event) {
    if (event) event.preventDefault()
    if (!this.hasAdvancedTarget || !this.hasAdvancedPanelTarget) return

    this.advancedOpen = !this.advancedOpen
    this.advancedTarget.classList.toggle("is-open", this.advancedOpen)
    this.advancedToggleTarget.setAttribute("aria-expanded", this.advancedOpen ? "true" : "false")

    if (this.advancedOpen) {
      this.advancedPanelTarget.style.maxHeight = `${this.advancedPanelTarget.scrollHeight}px`
      this.advancedIconTarget.classList.remove("bi-chevron-down")
      this.advancedIconTarget.classList.add("bi-chevron-up")
    } else {
      this.advancedPanelTarget.style.maxHeight = "0px"
      this.advancedIconTarget.classList.add("bi-chevron-down")
      this.advancedIconTarget.classList.remove("bi-chevron-up")
    }
  }

  closeOnEscape(event) {
    if (event.key === "Escape") {
      this.close(event)
    }
  }

  lockScroll() {
    document.documentElement.classList.add("public-global-search-lock")
    document.body.classList.add("public-global-search-lock")
  }

  unlockScroll() {
    document.documentElement.classList.remove("public-global-search-lock")
    document.body.classList.remove("public-global-search-lock")
  }
}
