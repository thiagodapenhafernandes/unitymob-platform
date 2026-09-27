import { Controller } from "@hotwired/stimulus"

// Modal do simulador (public_theme/components/financing_simulator_modal).
// <dialog> nativo; a animação vem da classe is-open (CSS da variante): abre
// com showModal + classe no próximo quadro, fecha tirando a classe e só então
// chama close(). Esc e clique fora fecham com a mesma animação. O botão de
// lead dentro do simulador fecha o modal antes, para o formulário de contato
// não ficar atrás do <dialog> (que vive na camada superior).
const CLOSE_FALLBACK_MS = 400

export default class extends Controller {
  connect() {
    this.onCtaClick = (event) => {
      if (event.target.closest(".public-theme-financing-simulator__cta")) this.close()
    }
    this.element.addEventListener("click", this.onCtaClick, true)
  }

  disconnect() {
    this.element.removeEventListener("click", this.onCtaClick, true)
    document.body.classList.remove("no-scroll")
  }

  open() {
    if (this.element.open) return

    this.element.showModal()
    document.body.classList.add("no-scroll")
    requestAnimationFrame(() => requestAnimationFrame(() => this.element.classList.add("is-open")))
  }

  close() {
    if (!this.element.open || this.closing) return

    this.closing = true
    this.element.classList.remove("is-open")
    const finish = () => {
      if (!this.closing) return
      this.closing = false
      clearTimeout(this.fallback)
      this.element.close()
      document.body.classList.remove("no-scroll")
    }
    this.element.addEventListener("transitionend", (event) => { if (event.target === this.element) finish() }, { once: true })
    this.fallback = setTimeout(finish, CLOSE_FALLBACK_MS)
  }

  cancel(event) {
    event.preventDefault()
    this.close()
  }

  // Clique na área escura: o alvo é o próprio <dialog>, não o painel.
  backdrop(event) {
    if (event.target === this.element) this.close()
  }
}
