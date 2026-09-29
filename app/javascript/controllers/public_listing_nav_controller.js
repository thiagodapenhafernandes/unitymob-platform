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
    if (window.Turbo) window.Turbo.visit(url, { frame: this.frameValue, action: "advance" })
    else window.location.href = url
  }
}
