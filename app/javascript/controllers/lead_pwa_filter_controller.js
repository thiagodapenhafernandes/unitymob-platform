import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "trigger"]

  connect() {
    this.close()
  }

  open(event) {
    if (event) event.preventDefault()
    this.panelTarget.hidden = false
    document.documentElement.classList.add("lead-pwa-filter-lock")
    this.syncExpanded(true)
  }

  close(event) {
    if (event) event.preventDefault()
    if (this.hasPanelTarget) this.panelTarget.hidden = true
    document.documentElement.classList.remove("lead-pwa-filter-lock")
    this.syncExpanded(false)
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close(event)
  }

  syncExpanded(expanded) {
    if (!this.hasTriggerTarget) return

    this.triggerTargets.forEach((trigger) => {
      trigger.setAttribute("aria-expanded", expanded ? "true" : "false")
    })
  }
}
