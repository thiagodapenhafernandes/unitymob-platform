import { Controller } from "@hotwired/stimulus"

// Atualiza somente o frame de leitura, preservando filtros e formulários da página.
export default class extends Controller {
  static values = { interval: { type: Number, default: 60000 } }

  connect() {
    this.refresh = this.refresh.bind(this)
    this.timer = window.setInterval(this.refresh, Math.max(60000, this.intervalValue))
    document.addEventListener("visibilitychange", this.refresh)
  }

  disconnect() {
    window.clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.refresh)
  }

  refresh() {
    if (document.hidden || this.element.hasAttribute("busy") || !this.element.src) return
    this.element.reload()
  }
}
