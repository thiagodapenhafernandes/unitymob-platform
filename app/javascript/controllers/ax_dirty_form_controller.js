import { Controller } from "@hotwired/stimulus"

// Marca o formulário como alterado e avisa antes de sair da página com mudanças
// não salvas. O indicador visual é CSS puro sobre form[data-dirty="true"].
// Uso: <form data-controller="ax-dirty-form" data-action="input->ax-dirty-form#mark change->ax-dirty-form#mark">
export default class extends Controller {
  connect() {
    this.dirty = false
    this.warn = (event) => {
      if (!this.dirty) return
      event.preventDefault()
      event.returnValue = ""
    }
    this.clear = () => { this.dirty = false }
    window.addEventListener("beforeunload", this.warn)
    this.element.addEventListener("submit", this.clear)
  }

  disconnect() {
    window.removeEventListener("beforeunload", this.warn)
    this.element.removeEventListener("submit", this.clear)
  }

  mark() {
    if (this.dirty) return
    this.dirty = true
    this.element.dataset.dirty = "true"
  }
}
