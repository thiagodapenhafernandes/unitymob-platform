import { Controller } from "@hotwired/stimulus"

// Lista PWA de leads (mobile): carrega mais 15 leads da aba atual ao chegar
// perto do fim da lista, no mesmo padrão de lead_kanban_controller.js
// (IntersectionObserver + fetch JSON + append de HTML), mas com scroll de
// página inteira (root: null) em vez de coluna própria.
export default class extends Controller {
  static targets = ["loader"]
  static values = { url: String }

  connect() {
    this.loading = false
    this.observeLoader()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  loaderTargetConnected(loader) {
    if (loader === this.loaderTarget) this.observeLoader()
  }

  observeLoader() {
    if (!this.hasLoaderTarget) return
    const loader = this.loaderTarget
    if (loader.hidden || loader.dataset.hasMore !== "true") return

    if (!("IntersectionObserver" in window)) {
      this.loadMore()
      return
    }

    this.observer?.disconnect()
    this.observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) this.loadMore()
    }, { root: null, rootMargin: "300px 0px", threshold: 0.01 })
    this.observer.observe(loader)
  }

  async loadMore() {
    if (this.loading || !this.hasLoaderTarget) return
    const loader = this.loaderTarget
    if (loader.hidden || loader.dataset.hasMore !== "true") return

    this.loading = true
    loader.setAttribute("aria-busy", "true")

    try {
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("offset", loader.dataset.offset || "0")

      const response = await fetch(url.toString(), {
        headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" }
      })
      const data = await this.parseResponse(response)
      if (!response.ok) throw new Error(data.message || "Não foi possível carregar mais leads.")

      if (data.html) {
        const template = document.createElement("template")
        template.innerHTML = data.html.trim()
        loader.before(template.content)
      }

      const nextOffset = Number.parseInt(data.next_offset, 10)
      const fallbackOffset = (Number.parseInt(loader.dataset.offset, 10) || 0) + (Number.parseInt(data.loaded_count, 10) || 0)
      loader.dataset.offset = String(Number.isFinite(nextOffset) ? nextOffset : fallbackOffset)
      loader.dataset.hasMore = data.has_more ? "true" : "false"

      if (!data.has_more || Number.parseInt(data.loaded_count, 10) === 0) {
        loader.hidden = true
        this.observer?.disconnect()
      }
    } catch (error) {
      this.notify(error.message || "Não foi possível carregar mais leads.")
    } finally {
      loader.removeAttribute("aria-busy")
      this.loading = false
    }
  }

  async parseResponse(response) {
    const contentType = response.headers.get("content-type") || ""
    if (contentType.includes("application/json")) return response.json()

    const text = await response.text()
    return { message: text ? "Não foi possível carregar mais leads." : null }
  }

  notify(message) {
    if (window.axToast) {
      window.axToast({ message, type: "danger" })
    } else {
      window.alert(message)
    }
  }
}
