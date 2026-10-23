import { Controller } from "@hotwired/stimulus"

// Turbo lazy observa a posição; um frame vazio pode intersectar mesmo com seu conteúdo oculto por CSS.
export default class extends Controller {
  static values = { media: String, src: String }

  connect() {
    this.media = window.matchMedia(this.mediaValue)
    this.loadWhenMatching = () => {
      if (this.media.matches && !this.element.hasAttribute("src")) {
        this.element.setAttribute("loading", "eager")
        this.element.setAttribute("src", this.srcValue)
      }
    }
    this.media.addEventListener("change", this.loadWhenMatching)
    this.loadWhenMatching()
  }

  disconnect() {
    this.media.removeEventListener("change", this.loadWhenMatching)
  }
}
