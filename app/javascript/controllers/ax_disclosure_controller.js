import { Controller } from "@hotwired/stimulus"

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
    this.apply(this.openValue, { animate: false })
  }

  disconnect() {
    if (this.closeTimer) window.clearTimeout(this.closeTimer)
  }

  toggle(event) {
    if (event) event.preventDefault()
    if (this.element.closest(".ax-sidebar") && document.body.classList.contains("is-compact")) return

    this.apply(!this.element.classList.contains("is-open"))
  }

  apply(open, options = {}) {
    const animate = options.animate !== false

    if (this.closeTimer) window.clearTimeout(this.closeTimer)
    this.element.classList.toggle("is-open", open)
    this.triggerTargets.forEach((t) => t.setAttribute("aria-expanded", open ? "true" : "false"))

    if (open) {
      this.openContent(animate)
    } else {
      this.closeContent(animate)
    }
  }

  openContent(animate) {
    this.contentTarget.hidden = false

    if (!animate) {
      this.clearInlineMotion()
      return
    }

    this.contentTarget.style.overflow = "hidden"
    this.contentTarget.style.maxHeight = "0px"
    this.contentTarget.style.opacity = "0"

    window.requestAnimationFrame(() => {
      this.contentTarget.style.maxHeight = `${this.contentTarget.scrollHeight}px`
      this.contentTarget.style.opacity = "1"
    })

    this.closeTimer = window.setTimeout(() => {
      if (this.element.classList.contains("is-open")) {
        this.contentTarget.style.maxHeight = ""
        this.contentTarget.style.overflow = ""
      }
    }, 200)
  }

  closeContent(animate) {
    if (!animate) {
      this.contentTarget.hidden = true
      this.clearInlineMotion()
      return
    }

    this.contentTarget.style.overflow = "hidden"
    this.contentTarget.style.maxHeight = `${this.contentTarget.scrollHeight}px`
    this.contentTarget.style.opacity = "1"

    window.requestAnimationFrame(() => {
      this.contentTarget.style.maxHeight = "0px"
      this.contentTarget.style.opacity = "0"
    })

    this.closeTimer = window.setTimeout(() => {
      if (!this.element.classList.contains("is-open")) {
        this.contentTarget.hidden = true
        this.clearInlineMotion()
      }
    }, 200)
  }

  clearInlineMotion() {
    this.contentTarget.style.maxHeight = ""
    this.contentTarget.style.opacity = ""
    this.contentTarget.style.overflow = ""
  }
}
