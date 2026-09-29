import { Controller } from "@hotwired/stimulus"

// Scroll infinito sem requisição nova: os itens além do lote inicial já vêm
// no HTML (o servidor já carregou tudo, por exemplo para as estatísticas do
// topo da página), só ficam com `hidden`. Ao chegar perto do fim da lista,
// revela mais um lote por vez. Genérico: qualquer grid de cards pode usar,
// bastando marcar os itens e o sentinela.
export default class extends Controller {
  static targets = ["item", "sentinel"]
  static values = { batchSize: { type: Number, default: 6 } }

  connect() {
    this.observeSentinel()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  observeSentinel() {
    if (!this.hasSentinelTarget || !("IntersectionObserver" in window)) return

    this.observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) this.revealNextBatch()
    }, { root: null, rootMargin: "400px 0px", threshold: 0.01 })
    this.observer.observe(this.sentinelTarget)
  }

  revealNextBatch() {
    const hiddenItems = this.itemTargets.filter((item) => item.hidden)
    hiddenItems.slice(0, this.batchSizeValue).forEach((item) => { item.hidden = false })

    if (this.itemTargets.every((item) => !item.hidden)) this.finish()
  }

  finish() {
    if (this.hasSentinelTarget) this.sentinelTarget.hidden = true
    this.observer?.disconnect()
  }
}
