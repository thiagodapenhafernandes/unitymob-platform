import { Controller } from "@hotwired/stimulus"

// Botões "Simular financiamento" (card de preço, atalhos da galeria): pedem a
// abertura do modal do simulador da página (financing-modal).
export default class extends Controller {
  open(event) {
    event.preventDefault()
    window.dispatchEvent(new CustomEvent("public-financing:open"))
  }
}
