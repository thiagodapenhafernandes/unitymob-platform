import { Controller } from "@hotwired/stimulus"

// Paginação e ordenação da listagem pública navegam só a grade
// (turbo-frame #public-listing-grid), com advance para manter a URL
// canônica na barra de endereços.
export default class extends Controller {
  static values = { frame: String }

  follow(event) {
    const link = event.target.closest("a[href]")
    if (!link || link.hasAttribute("data-public-listing-more")) return
    if (link.getAttribute("data-turbo-frame") === "_top") return

    event.preventDefault()
    this.go(link.href)
  }

  async loadMore(event) {
    event.preventDefault()
    event.stopPropagation()
    const link = event.currentTarget
    if (this.loadingMore) return
    this.loadingMore = true
    const footer = link.closest("[data-public-listing-footer]")
    const status = footer.querySelector("[role=status]")
    link.setAttribute("aria-disabled", "true")
    status.textContent = "Carregando imóveis…"
    try {
      const response = await fetch(link.href, { headers: { Accept: "text/html", "Turbo-Frame": this.frameValue } })
      if (!response.ok) throw new Error("Falha ao carregar")
      const document = new DOMParser().parseFromString(await response.text(), "text/html")
      const incoming = document.querySelector(`#${this.frameValue}`)
      const grid = this.element.querySelector(".public-theme-property-grid")
      const nextGrid = incoming?.querySelector(".public-theme-property-grid")
      const nextFooter = incoming?.querySelector("[data-public-listing-footer]")
      if (!grid || !nextGrid || !nextFooter) throw new Error("Resposta inválida")
      if (!footer.isConnected) return
      const existingIds = new Set([...grid.children].map(card => card.dataset.propertyId))
      const cards = [...nextGrid.children].filter(card => !existingIds.has(card.dataset.propertyId))
      const first = cards[0]
      grid.append(...cards)
      footer.replaceWith(nextFooter)
      // O foco acompanha o primeiro resultado novo, sem levar o visitante ao topo.
      first?.setAttribute("tabindex", "-1")
      first?.focus({ preventScroll: true })
      nextFooter.querySelector("[role=status]").textContent = "Mais imóveis carregados."
    } catch {
      status.textContent = "Não foi possível carregar. Tente novamente."
      link.removeAttribute("aria-disabled")
    } finally {
      this.loadingMore = false
    }
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
