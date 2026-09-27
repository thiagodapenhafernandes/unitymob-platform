import { Controller } from "@hotwired/stimulus"

// Texto longo recolhido com "Ler mais / Ler menos" e transição suave de altura.
// A altura anima entre o recorte e a altura real do conteúdo; aberto, o
// max-height é liberado para acompanhar mudanças de largura.
export default class extends Controller {
  static targets = ["content", "toggle"]
  static values = {
    collapsedHeight: { type: Number, default: 190 },
    moreLabel: { type: String, default: "Ler mais" },
    lessLabel: { type: String, default: "Ler menos" }
  }

  connect() {
    this.expanded = false
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.onTransitionEnd = this.onTransitionEnd.bind(this)
    this.contentTarget.addEventListener("transitionend", this.onTransitionEnd)

    this.resizeObserver = new ResizeObserver(() => this.refresh())
    this.resizeObserver.observe(this.contentTarget)

    requestAnimationFrame(() => this.refresh())
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    this.contentTarget.removeEventListener("transitionend", this.onTransitionEnd)
  }

  toggle() {
    this.expanded = !this.expanded
    this.updateLabels()

    if (this.reducedMotion) {
      this.contentTarget.style.maxHeight = this.expanded ? "" : `${this.collapsedHeightValue}px`
      return
    }

    const content = this.contentTarget
    if (this.expanded) {
      // De recortado até a altura real; o transitionend libera o max-height.
      content.style.maxHeight = `${this.collapsedHeightValue}px`
      requestAnimationFrame(() => { content.style.maxHeight = `${content.scrollHeight}px` })
    } else {
      // Fixa a altura atual antes de recolher, senão "none → 190px" não anima.
      content.style.maxHeight = `${content.scrollHeight}px`
      requestAnimationFrame(() => {
        requestAnimationFrame(() => { content.style.maxHeight = `${this.collapsedHeightValue}px` })
      })
      this.keepTopInView()
    }
  }

  refresh() {
    // Durante a animação o conteúdo muda de altura; não recalcula no meio dela.
    if (this.animating) return

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

    this.updateLabels()
    if (!this.expanded) this.contentTarget.style.maxHeight = `${this.collapsedHeightValue}px`
  }

  onTransitionEnd(event) {
    if (event.target !== this.contentTarget || event.propertyName !== "max-height") return

    if (this.expanded) this.contentTarget.style.maxHeight = ""
  }

  updateLabels() {
    this.element.classList.toggle("is-expanded", this.expanded)
    this.toggleTarget.setAttribute("aria-expanded", this.expanded ? "true" : "false")
    const label = this.toggleTarget.querySelector("[data-collapsible-text-label]") || this.toggleTarget
    label.textContent = this.expanded ? this.lessLabelValue : this.moreLabelValue
  }

  // Ao recolher um texto longo, o topo pode ter saído da tela: traz de volta.
  keepTopInView() {
    const top = this.element.getBoundingClientRect().top
    if (top < 0) window.scrollBy({ top: top - 96, behavior: this.reducedMotion ? "auto" : "smooth" })
  }

  get reducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }

  get animating() {
    return this.contentTarget.style.maxHeight !== "" && this.expanded &&
      parseFloat(this.contentTarget.style.maxHeight) > this.collapsedHeightValue
  }
}
