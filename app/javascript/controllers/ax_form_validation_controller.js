import { Controller } from "@hotwired/stimulus"

// Reveal the first invalid field before asking the browser to display its message.
export default class extends Controller {
  connect() {
    this.handleInvalidBound = this.handleInvalid.bind(this)
    this.element.addEventListener("invalid", this.handleInvalidBound, true)
  }

  disconnect() {
    this.element.removeEventListener("invalid", this.handleInvalidBound, true)
    if (this.validationFrame != null) cancelAnimationFrame(this.validationFrame)
    this.validationFrame = null
    this.pendingField = null
  }

  handleInvalid(event) {
    if (this.reportingValidity) return

    event.preventDefault()
    if (this.pendingField) return

    this.pendingField = event.target
    this.validationFrame = requestAnimationFrame(() => {
      this.validationFrame = null
      const field = this.pendingField
      this.pendingField = null
      if (!this.element.contains(field)) return

      this.revealAncestors(field)
      field.focus()
      this.reportingValidity = true
      try {
        field.reportValidity()
      } finally {
        this.reportingValidity = false
      }
    })
  }

  revealAncestors(field) {
    const ancestors = []
    for (let parent = field.parentElement; parent && parent !== this.element; parent = parent.parentElement) {
      ancestors.unshift(parent)
    }

    ancestors.forEach((container) => {
      if (container.matches("details")) container.open = true
      if (!container.hidden || !container.id) return
      if (!container.matches('[role="tabpanel"], [data-ax-disclosure-target~="content"]')) return

      const trigger = Array.from(this.element.querySelectorAll("button[aria-controls]"))
        .find((button) => button.getAttribute("aria-controls") === container.id && !button.disabled)
      trigger?.click()
    })
  }
}
