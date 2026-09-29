import { Controller } from "@hotwired/stimulus"

// A gramática nova (/imoveis/venda/...) é montada no servidor (fonte única:
// PublicSearch::ListingUrl). Este controller só garante o marcador de
// versão e deixa o submit nativo (GET /imoveis) seguir — o controller
// responde 301 para a URL canônica. URLs antigas seguem servindo 200.
export default class extends Controller {
  submit(event) {
    if (this.element.method.toLowerCase() !== "get") return

    const action = new URL(this.element.action, window.location.origin)
    if (action.pathname !== "/imoveis") return

    let marker = this.element.querySelector('input[name="v"]')
    if (!marker) {
      marker = document.createElement("input")
      marker.type = "hidden"
      marker.name = "v"
      this.element.append(marker)
    }
    marker.value = "2"
    // Sem interceptar o envio: o submit nativo leva filtros + marcador e o
    // servidor redireciona para a URL amigável nova.
  }
}
