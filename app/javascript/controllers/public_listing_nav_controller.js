import { Controller } from "@hotwired/stimulus"

// Paginação e ordenação da listagem pública navegam só a grade
// (turbo-frame #public-listing-grid), com advance para manter a URL
// canônica na barra de endereços.
export default class extends Controller {
  static values = { frame: String }

  follow(event) {
    const link = event.target.closest("a[href]")
    if (!link) return

    event.preventDefault()
    this.go(link.href)
  }

  sort(event) {
    if (event.target.value) this.go(event.target.value)
  }

  go(url) {
    this.setFrameBusy(true)
    if (window.Turbo) window.Turbo.visit(url, { frame: this.frameValue, action: "advance" })
    else window.location.href = url
  }

  // Turbo não mostra progresso em navegação de frame: sinaliza na grade
  // (classe + aria-busy) e limpa ao carregar ou falhar a requisição.
  setFrameBusy(busy) {
    const frame = document.getElementById(this.frameValue)
    if (!frame) return

    frame.classList.toggle("is-loading", busy)
    if (!busy) {
      frame.removeAttribute("aria-busy")
      return
    }

    frame.setAttribute("aria-busy", "true")
    const done = () => {
      frame.removeEventListener("turbo:frame-load", done)
      document.removeEventListener("turbo:fetch-request-error", done)
      this.setFrameBusy(false)
    }
    frame.addEventListener("turbo:frame-load", done)
    document.addEventListener("turbo:fetch-request-error", done)
  }
}
