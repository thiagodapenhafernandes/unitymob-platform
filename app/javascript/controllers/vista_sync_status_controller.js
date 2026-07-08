import { Controller } from "@hotwired/stimulus"

// Polling do painel de progresso da sincronização Vista.
// Enquanto status == "processing", busca a cada 2s.
// Pausa em aba oculta (document.hidden) e retoma com refresh imediato ao voltar.
// Quando finaliza (completed/failed), para e faz 1 refresh final.
export default class extends Controller {
  static values = {
    url: String,
    status: String,
    interval: { type: Number, default: 2000 }
  }

  connect() {
    this.boundVisibilityChange = this.handleVisibilityChange.bind(this)
    document.addEventListener("visibilitychange", this.boundVisibilityChange)

    if (this.statusValue === "processing") {
      this.startPolling()
    }
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.boundVisibilityChange)
    this.stopPolling()
  }

  handleVisibilityChange() {
    if (document.hidden) return
    if (this.pollId) this.refresh() // refresh imediato ao voltar para a aba
  }

  startPolling() {
    if (this.pollId) return
    this.pollId = setInterval(() => this.refresh(), this.intervalValue)
  }

  stopPolling() {
    if (this.pollId) {
      clearInterval(this.pollId)
      this.pollId = null
    }
  }

  async refresh() {
    if (document.hidden) return // pausa o polling em aba oculta

    try {
      const res = await fetch(this.urlValue, {
        headers: { "Accept": "text/html", "X-Requested-With": "XMLHttpRequest" },
        credentials: "same-origin"
      })
      if (!res.ok) return
      const html = await res.text()
      // Substitui o próprio elemento pelo novo HTML
      const wrapper = document.createElement("div")
      wrapper.innerHTML = html.trim()
      const fresh = wrapper.firstElementChild
      if (!fresh) return
      this.element.replaceWith(fresh)
    } catch (e) {
      // network glitch — tenta na próxima iteração
    }
  }
}
