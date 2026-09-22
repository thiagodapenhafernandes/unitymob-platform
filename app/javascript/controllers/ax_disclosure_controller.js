import { Controller } from "@hotwired/stimulus"
import { slide } from "lib/slide"

// Collapse / accordion (substitui bootstrap.Collapse).
// Uso:
//   <div data-controller="ax-disclosure">
//     <button data-action="ax-disclosure#toggle" aria-expanded="false">Mais</button>
//     <div data-ax-disclosure-target="content" hidden>…</div>
//   </div>
export default class extends Controller {
  static targets = ["content", "trigger"]
  static values = { open: { type: Boolean, default: false } }

  connect() {
    this.closeTimer = null
    this.assignRelationships()
    this.apply(this.openValue, { animate: false })
  }

  disconnect() {
    if (this.closeTimer) window.clearTimeout(this.closeTimer)
  }

  toggle(event) {
    if (event) event.preventDefault()

    this.apply(!this.element.classList.contains("is-open"))
  }

  apply(open, options = {}) {
    const animate = options.animate !== false && !this.prefersReducedMotion

    if (this.closeTimer) window.clearTimeout(this.closeTimer)
    this.element.classList.toggle("is-open", open)
    this.disclosureTriggers.forEach((trigger) => trigger.setAttribute("aria-expanded", open ? "true" : "false"))
    this.contentTarget.setAttribute("aria-hidden", open ? "false" : "true")

    if (open) {
      this.openContent(animate)
    } else {
      this.closeContent(animate)
    }
  }

  openContent(animate) {
    if (!animate) {
      this.contentTarget.hidden = false
      this.clearInlineMotion()
      return
    }

    slide(this.contentTarget, true)
  }

  closeContent(animate) {
    if (!animate) {
      this.contentTarget.hidden = true
      this.clearInlineMotion()
      return
    }

    slide(this.contentTarget, false)
  }

  clearInlineMotion() {
    this.contentTarget.style.maxHeight = ""
    this.contentTarget.style.opacity = ""
    this.contentTarget.style.overflow = ""
  }

  assignRelationships() {
    if (!this.contentTarget.id) this.contentTarget.id = `ax-disclosure-content-${this.uniqueId()}`

    this.disclosureTriggers.forEach((trigger) => {
      trigger.setAttribute("aria-controls", this.contentTarget.id)
    })
  }

  get disclosureTriggers() {
    const selector = [
      '[data-ax-disclosure-target~="trigger"]',
      '[data-action~="ax-disclosure#toggle"]',
      '[data-action~="click->ax-disclosure#toggle"]'
    ].join(",")

    return Array.from(this.element.querySelectorAll(selector)).filter((trigger) => {
      return trigger.closest('[data-controller~="ax-disclosure"]') === this.element
    })
  }

  get prefersReducedMotion() {
    return window.matchMedia?.("(prefers-reduced-motion: reduce)").matches === true
  }

  uniqueId() {
    return Math.random().toString(36).slice(2, 10)
  }
}
