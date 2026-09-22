import { Controller } from "@hotwired/stimulus"

// Tela de gestão de atendimentos: recarrega a tabela quando um atendimento muda (tempo real).
export default class extends Controller {
  static targets = ["frame"]

  connect() {
    this.onChange = () => {
      clearTimeout(this.timer)
      this.timer = setTimeout(() => this.frameTarget.reload?.(), 400)
    }
    window.addEventListener("wa:attendance-changed", this.onChange)
  }

  disconnect() {
    clearTimeout(this.timer)
    window.removeEventListener("wa:attendance-changed", this.onChange)
  }
}
