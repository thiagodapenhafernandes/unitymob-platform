import { Controller } from "@hotwired/stimulus"

// Abre modais de formulário a partir de qualquer link ou botão do site (menu, botões, banners, CTAs).
// Serve qualquer elemento com href / data-href apontando para `#modal-<ID>` (ou data-open-modal="<ID>"),
// inclusive "/pagina-atual#modal-<ID>". Também honra o hash ao carregar e quando ele muda (deep-link).
//
// Robustez (o link nunca pode "só colocar o ID na URL"):
//   - escuta na fase de CAPTURA: menus e overlays que tratam o clique antes não impedem a abertura;
//   - se o controller do modal ainda está carregando (lazy), espera ele conectar;
//   - sem controller (falha de JS), abre o modal direto e ainda fecha no X, no fundo e no Esc;
//   - hashchange cobre o caso de o navegador ter aplicado o #hash mesmo assim.
const PREFIX = "#modal-"
const TRIGGER = "[href], [data-href], [data-open-modal]"
const WAIT_MS = 3000

export default class extends Controller {
  connect() {
    this.onClick = (event) => this.intercept(event)
    this.onHashChange = () => this.openFromHash()
    document.addEventListener("click", this.onClick, true)
    window.addEventListener("hashchange", this.onHashChange)
    this.openFromHash()
  }

  disconnect() {
    document.removeEventListener("click", this.onClick, true)
    window.removeEventListener("hashchange", this.onHashChange)
  }

  intercept(event) {
    // Clique com modificador (nova aba/janela) e cliques que outro script já tratou seguem o fluxo normal.
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    const trigger = event.target.closest?.(TRIGGER)
    const slug = trigger && this.slugFor(trigger)
    if (!slug || !this.overlayFor(slug)) return

    // Sem stopPropagation: o menu em tela cheia e demais scripts ainda recebem o clique (e se fecham).
    event.preventDefault()
    this.open(slug)
  }

  openFromHash() {
    const hash = decodeURIComponent(window.location.hash)
    if (hash.startsWith(PREFIX) && hash.length > PREFIX.length) this.open(hash.slice(PREFIX.length))
  }

  slugFor(element) {
    if (element.dataset.openModal) return element.dataset.openModal

    const raw = element.getAttribute("href") || element.dataset.href
    if (!raw) return null

    let url
    try {
      url = new URL(raw, window.location.href)
    } catch (_error) {
      return null
    }
    if (!url.hash.startsWith(PREFIX) || url.hash.length <= PREFIX.length) return null
    // Só abre aqui se o link é desta página; de outra página o navegador navega e o modal abre ao carregar (hash).
    if (url.origin !== window.location.origin || url.pathname !== window.location.pathname) return null

    return decodeURIComponent(url.hash.slice(PREFIX.length))
  }

  overlayFor(slug) {
    return document.querySelector(`[data-modal-slug="${CSS.escape(slug)}"]`)
  }

  async open(slug) {
    const overlay = this.overlayFor(slug)
    if (!overlay) return false

    this.closeNavigation()
    const host = overlay.closest("[data-controller~='public-form-modal']") || overlay
    const modal = await this.waitForController(host, "public-form-modal")

    if (modal) modal.open()
    else this.openWithoutController(overlay)
    return true
  }

  // O controller do modal é carregado sob demanda: espera ele conectar (até WAIT_MS).
  async waitForController(element, identifier) {
    const deadline = Date.now() + WAIT_MS
    for (;;) {
      const controller = this.application.getControllerForElementAndIdentifier(element, identifier)
      if (controller || Date.now() > deadline) return controller

      await new Promise((resolve) => setTimeout(resolve, 50))
    }
  }

  // Plano B: o modal abre mesmo se o JS do modal falhar, e ainda fecha no X, no fundo e no Esc.
  openWithoutController(overlay) {
    overlay.hidden = false
    document.body.style.overflow = "hidden"

    const close = () => {
      overlay.hidden = true
      document.body.style.overflow = ""
      overlay.removeEventListener("click", onClick)
      document.removeEventListener("keydown", onKey)
    }
    const onClick = (event) => {
      if (event.target.closest(".public-form-modal__close, .public-form-modal__backdrop")) close()
    }
    const onKey = (event) => {
      if (event.key === "Escape") close()
    }
    overlay.addEventListener("click", onClick)
    document.addEventListener("keydown", onKey)
  }

  // O menu em tela cheia fica aberto por baixo do modal: fecha.
  closeNavigation() {
    const menu = document.querySelector("[data-controller~='navigation-overlay']")
    if (menu) this.application.getControllerForElementAndIdentifier(menu, "navigation-overlay")?.close()
  }
}
