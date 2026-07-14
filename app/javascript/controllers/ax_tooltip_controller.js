import { Controller } from "@hotwired/stimulus"

// Tooltip leve (substitui bootstrap.Tooltip).
// Uso: <button data-controller="ax-tooltip" data-ax-tooltip-text-value="Editar">…</button>
export default class extends Controller {
  static values = { text: String, placement: { type: String, default: "top" } }

  connect() {
    this.prepareHost()
    this.show = this.show.bind(this)
    this.hide = this.hide.bind(this)
    this.position = this.position.bind(this)
    this.hideOnEscape = this.hideOnEscape.bind(this)
    this.element.addEventListener("mouseenter", this.show)
    this.element.addEventListener("mouseleave", this.hide)
    this.element.addEventListener("focus", this.show)
    this.element.addEventListener("blur", this.hide)
    this.element.addEventListener("keydown", this.hideOnEscape)
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this.show)
    this.element.removeEventListener("mouseleave", this.hide)
    this.element.removeEventListener("focus", this.show)
    this.element.removeEventListener("blur", this.hide)
    this.element.removeEventListener("keydown", this.hideOnEscape)
    this.hide()
    if (this.addedTabIndex) this.element.removeAttribute("tabindex")
    if (this.nativeTitle) this.element.setAttribute("title", this.nativeTitle)
  }

  show() {
    if (!this.tooltipText || this.tip) return
    const tip = document.createElement("div")
    tip.className = "ax-tooltip"
    tip.id = `ax-tooltip-${this.uniqueId()}`
    tip.setAttribute("role", "tooltip")
    tip.textContent = this.tooltipText
    document.body.appendChild(tip)
    this.tip = tip
    this.previousDescribedBy = this.element.getAttribute("aria-describedby")
    const describedBy = [this.previousDescribedBy, tip.id].filter(Boolean).join(" ")
    this.element.setAttribute("aria-describedby", describedBy)
    window.addEventListener("resize", this.position)
    window.addEventListener("scroll", this.position, true)
    this.position()
  }

  hide() {
    if (!this.tip) return

    this.tip.remove()
    this.tip = null
    window.removeEventListener("resize", this.position)
    window.removeEventListener("scroll", this.position, true)
    if (this.previousDescribedBy) this.element.setAttribute("aria-describedby", this.previousDescribedBy)
    else this.element.removeAttribute("aria-describedby")
    this.previousDescribedBy = null
  }

  position() {
    if (!this.tip) return

    const anchor = this.element.getBoundingClientRect()
    const tip = this.tip.getBoundingClientRect()
    const gap = 8
    const margin = 8
    let placement = this.normalizedPlacement
    let coordinates = this.coordinatesFor(placement, anchor, tip, gap)

    if (placement === "top" && coordinates.top < margin) placement = "bottom"
    else if (placement === "bottom" && coordinates.top + tip.height > window.innerHeight - margin) placement = "top"
    else if (placement === "left" && coordinates.left < margin) placement = "right"
    else if (placement === "right" && coordinates.left + tip.width > window.innerWidth - margin) placement = "left"

    coordinates = this.coordinatesFor(placement, anchor, tip, gap)
    this.tip.dataset.placement = placement
    this.tip.style.top = `${Math.min(Math.max(coordinates.top, margin), window.innerHeight - tip.height - margin)}px`
    this.tip.style.left = `${Math.min(Math.max(coordinates.left, margin), window.innerWidth - tip.width - margin)}px`
  }

  coordinatesFor(placement, anchor, tip, gap) {
    if (placement === "bottom") return { top: anchor.bottom + gap, left: anchor.left + (anchor.width - tip.width) / 2 }
    if (placement === "left") return { top: anchor.top + (anchor.height - tip.height) / 2, left: anchor.left - tip.width - gap }
    if (placement === "right") return { top: anchor.top + (anchor.height - tip.height) / 2, left: anchor.right + gap }

    return { top: anchor.top - tip.height - gap, left: anchor.left + (anchor.width - tip.width) / 2 }
  }

  get normalizedPlacement() {
    return ["top", "bottom", "left", "right"].includes(this.placementValue) ? this.placementValue : "top"
  }

  prepareHost() {
    this.nativeTitle = this.element.getAttribute("title")
    if (this.nativeTitle) this.element.removeAttribute("title")

    const naturallyFocusable = this.element.matches('a[href], button, input, select, textarea, [contenteditable="true"]')
    if (!naturallyFocusable && !this.element.hasAttribute("tabindex")) {
      this.element.setAttribute("tabindex", "0")
      this.addedTabIndex = true
    }
  }

  hideOnEscape(event) {
    if (event.key === "Escape") this.hide()
  }

  textValueChanged() {
    if (!this.tip) return

    if (!this.tooltipText) {
      this.hide()
      return
    }

    this.tip.textContent = this.tooltipText
    this.position()
  }

  get tooltipText() {
    return (this.hasTextValue ? this.textValue : this.nativeTitle) || ""
  }

  uniqueId() {
    return Math.random().toString(36).slice(2, 10)
  }
}
