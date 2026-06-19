import { Controller } from "@hotwired/stimulus"

// Tooltip leve (substitui bootstrap.Tooltip).
// Uso: <button data-controller="ax-tooltip" data-ax-tooltip-text-value="Editar">…</button>
export default class extends Controller {
  static values = { text: String, placement: { type: String, default: "top" } }

  connect() {
    this.show = this.show.bind(this)
    this.hide = this.hide.bind(this)
    this.element.addEventListener("mouseenter", this.show)
    this.element.addEventListener("mouseleave", this.hide)
    this.element.addEventListener("focus", this.show)
    this.element.addEventListener("blur", this.hide)
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this.show)
    this.element.removeEventListener("mouseleave", this.hide)
    this.element.removeEventListener("focus", this.show)
    this.element.removeEventListener("blur", this.hide)
    this.hide()
  }

  show() {
    if (!this.textValue || this.tip) return
    const tip = document.createElement("div")
    tip.className = "ax-tooltip"
    tip.textContent = this.textValue
    document.body.appendChild(tip)
    const r = this.element.getBoundingClientRect()
    tip.style.top = `${window.scrollY + r.top - tip.offsetHeight - 6}px`
    tip.style.left = `${window.scrollX + r.left + r.width / 2 - tip.offsetWidth / 2}px`
    this.tip = tip
  }

  hide() {
    if (this.tip) { this.tip.remove(); this.tip = null }
  }
}
