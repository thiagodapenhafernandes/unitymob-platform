import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "toggle"]
  static values = {
    collapsedHeight: { type: Number, default: 190 },
    moreLabel: { type: String, default: "Exibir mais +" },
    lessLabel: { type: String, default: "Exibir menos -" }
  }

  connect() {
    this.expanded = false
    this.toggleTarget.setAttribute("aria-expanded", "false")

    this.resizeObserver = new ResizeObserver(() => this.refresh())
    this.resizeObserver.observe(this.contentTarget)

    requestAnimationFrame(() => this.refresh())
  }

  disconnect() {
    this.resizeObserver?.disconnect()
  }

  toggle() {
    this.expanded = !this.expanded
    this.applyState()
  }

  refresh() {
    const needsToggle = this.contentTarget.scrollHeight > this.collapsedHeightValue + 8

    this.element.classList.toggle("is-collapsible", needsToggle)
    this.toggleTarget.hidden = !needsToggle

    if (!needsToggle) {
      this.expanded = true
      this.contentTarget.style.maxHeight = ""
      this.element.classList.add("is-expanded")
      this.toggleTarget.setAttribute("aria-expanded", "true")
      return
    }

    this.applyState()
  }

  applyState() {
    this.element.classList.toggle("is-expanded", this.expanded)
    this.toggleTarget.textContent = this.expanded ? this.lessLabelValue : this.moreLabelValue
    this.toggleTarget.setAttribute("aria-expanded", this.expanded ? "true" : "false")
    this.contentTarget.style.maxHeight = this.expanded ? "" : `${this.collapsedHeightValue}px`
  }
}
