import { Controller } from "@hotwired/stimulus"

// Desktop e mobile podem renderizar o mesmo registro; só o painel visível recebe foco.
export default class extends Controller {
  connect() {
    this.frame = requestAnimationFrame(() => {
      if (!this.element.getClientRects().length) return
      this.element.scrollIntoView({ behavior: "auto", block: "center" })
      this.element.focus({ preventScroll: true })
    })
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
  }
}
