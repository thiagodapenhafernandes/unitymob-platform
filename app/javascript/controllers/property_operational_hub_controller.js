import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "tab"]
  static values = { url: String }

  connect() {
    this.cache = new Map()
    this.activeTab = "overview"
    this.abortController = null
  }

  disconnect() {
    this.abortController?.abort()
  }

  open() {
    this.load(this.activeTab)
  }

  select(event) {
    event.preventDefault()
    const tab = event.params.tab
    if (!tab) return

    this.activeTab = tab
    this.tabTargets.forEach((button) => {
      const active = button.dataset.propertyOperationalHubTabParam === tab
      button.classList.toggle("active", active)
      button.setAttribute("aria-selected", active ? "true" : "false")
    })
    this.load(tab)
  }

  async load(tab, force = false) {
    if (!force && this.cache.has(tab)) {
      this.contentTarget.innerHTML = this.cache.get(tab)
      return
    }

    this.abortController?.abort()
    this.abortController = new AbortController()
    this.contentTarget.innerHTML = '<div class="habitation-hub-loading"><i class="bi bi-arrow-repeat"></i> Carregando informações…</div>'

    try {
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("tab", tab)
      const response = await fetch(url, {
        headers: { Accept: "text/html", "X-Requested-With": "XMLHttpRequest" },
        signal: this.abortController.signal
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const html = await response.text()
      this.cache.set(tab, html)
      if (this.activeTab === tab) this.contentTarget.innerHTML = html
    } catch (error) {
      if (error.name === "AbortError") return
      this.contentTarget.innerHTML = '<div class="habitation-hub-error"><span>Não foi possível carregar esta aba.</span><button type="button" class="ax-btn ax-btn--sm" data-action="property-operational-hub#retry">Tentar novamente</button></div>'
    }
  }

  retry() {
    this.load(this.activeTab, true)
  }
}
