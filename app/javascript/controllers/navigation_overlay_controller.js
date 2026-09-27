import { Controller } from "@hotwired/stimulus"

// Menu de navegação em tela cheia (public_theme/components/navigation_overlay).
// Os botões do header disparam `public-navigation:open` na window; fecha no X,
// no Esc ou ao seguir um link. A foto lateral só carrega na primeira abertura.
export default class extends Controller {
  static targets = ["media"]

  open() {
    if (this.element.classList.contains("open")) return

    this.loadMedia()
    this.returnFocus = document.activeElement
    this.element.classList.add("open")
    this.element.setAttribute("aria-hidden", "false")
    document.body.classList.add("no-scroll")
    this.element.querySelector(".public-theme-navigation-overlay__close")?.focus({ preventScroll: true })
  }

  close() {
    if (!this.element.classList.contains("open")) return

    this.element.classList.remove("open")
    this.element.setAttribute("aria-hidden", "true")
    document.body.classList.remove("no-scroll")
    this.returnFocus?.focus?.({ preventScroll: true })
    this.returnFocus = null
  }

  disconnect() {
    // Turbo pode trocar a página com o menu aberto (link clicado).
    document.body.classList.remove("no-scroll")
  }

  loadMedia() {
    if (!this.hasMediaTarget) return

    const image = this.mediaTarget
    if (image.src || !image.dataset.src) return

    image.src = image.dataset.src
    delete image.dataset.src
  }
}
