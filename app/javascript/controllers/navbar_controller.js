import { Controller } from "@hotwired/stimulus"

// Header dos temas padrão: o botão de menu abre o navigation-overlay.
export default class extends Controller {
  openMenu() {
    window.dispatchEvent(new CustomEvent("public-navigation:open"))
  }
}
