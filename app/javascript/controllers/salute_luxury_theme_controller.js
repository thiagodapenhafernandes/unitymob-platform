import { Controller } from "@hotwired/stimulus"

// Acima desta largura o hero enxuto não vale: o desktop mantém o hero completo.
const HERO_COMPACT_MAX_WIDTH = 768
// Rolagem mínima para o botão sair do centro do hero e docar no canto.
const HERO_COMPACT_DOCK_SCROLL = 8
// Precisa casar com a transição de opacidade do .public-theme-filter-fab no CSS: é a
// janela em que o botão fica invisível e a troca de estado acontece.
const HERO_COMPACT_FADE_MS = 220

export default class extends Controller {
  static targets = ["header", "transactionInput", "transactionButton"]

  static values = { heroCompact: Boolean }

  connect() {
    this.handleScroll = this.handleScroll.bind(this)

    window.addEventListener("scroll", this.handleScroll, { passive: true })

    this.handleScroll()
    this.observeHeaderHeight()
    this.initReveals()
    this.initFilterFabVisibility()
    this.initHeroCompactFab()
  }

  disconnect() {
    window.removeEventListener("scroll", this.handleScroll)
    window.removeEventListener("resize", this.handleHeroCompactResize)
    window.removeEventListener("orientationchange", this.handleHeroCompactResize)
    this.revealObserver?.disconnect()
    this.headerResizeObserver?.disconnect()
    this.filterFabMedia?.removeEventListener?.("change", this.handleFilterFabMediaChange)
    this.heroCompactMedia?.removeEventListener?.("change", this.handleHeroCompactResize)
    window.clearTimeout(this.heroCompactFadeTimer)
    document.body.classList.remove("no-scroll")
  }

  // Altura real do header fixo em --sl-header-height: páginas internas usam
  // como respiro no topo (o menu pode quebrar em duas linhas, o logo muda).
  observeHeaderHeight() {
    if (!this.hasHeaderTarget || !window.ResizeObserver) return

    const publish = () => this.element.style.setProperty("--sl-header-height", `${this.headerTarget.offsetHeight}px`)
    this.headerResizeObserver = new ResizeObserver(publish)
    this.headerResizeObserver.observe(this.headerTarget)
    publish()
  }

  handleScroll() {
    if (this.hasHeaderTarget) this.headerTarget.classList.toggle("scrolled", window.scrollY > 36)
    this.updateFilterFabVisibility()
    this.updateHeroCompactFab()
  }

  setTransaction(event) {
    const button = event.currentTarget
    this.transactionButtonTargets.forEach((target) => target.setAttribute("aria-pressed", "false"))
    button.setAttribute("aria-pressed", "true")

    if (this.hasTransactionInputTarget) {
      this.transactionInputTarget.value = button.dataset.transactionType || "venda"
    }
  }

  // O menu é o componente navigation-overlay (controller próprio); aqui só o
  // botão do header pede a abertura.
  openMenu() {
    window.dispatchEvent(new CustomEvent("public-navigation:open"))
  }

  initReveals() {
    const selectors = [
      ".sl-hero .public-theme-hero__tagline",
      ".sl-hero .public-theme-hero__title",
      ".sl-hero .public-theme-hero__lead",
      ".sl-hero .sl-transaction",
      ".sl-hero .sl-search",
      ".sl-hero .sl-filter-link",
      ".public-theme-stats-strip__item",
      ".public-theme-section__head",
      ".public-theme-property-card--salute-luxury",
      ".public-theme-feature-grid__item",
      ".public-theme-region-grid__item",
      ".public-theme-brand-about__media",
      ".public-theme-brand-about__content",
      ".public-theme-testimonials__item",
      ".public-theme-contact-cta__title",
      ".public-theme-contact-cta__body",
      ".public-theme-contact-cta__action"
    ]
    const elements = Array.from(this.element.querySelectorAll(selectors.join(",")))
    if (!elements.length) return

    elements.forEach((element, index) => {
      element.classList.add("sl-reveal")
      element.style.setProperty("--sl-reveal-delay", `${(index % 3) * 80}ms`)
    })
    this.element.classList.add("sl-effects-ready")

    if (!window.IntersectionObserver || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      elements.forEach((element) => element.classList.add("in"))
      return
    }

    this.revealObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return

        entry.target.classList.add("in")
        this.revealObserver.unobserve(entry.target)
      })
    }, { threshold: 0.12 })

    elements.forEach((element) => this.revealObserver.observe(element))
  }

  initFilterFabVisibility() {
    this.filterFab = this.element.querySelector(".public-theme-filter-fab")
    if (!this.filterFab) return

    this.filterFabMedia = window.matchMedia("(max-width: 400px)")
    this.handleFilterFabMediaChange = () => this.updateFilterFabVisibility()
    this.filterFabMedia.addEventListener?.("change", this.handleFilterFabMediaChange)

    this.filterFabSections = Array.from(this.element.querySelectorAll([
      ".sl-hero",
      "#imoveis",
      "#preco-reduzido",
      "#locacao",
      "#empreendimentos"
    ].join(",")))

    if (!this.filterFabSections.length) {
      this.filterFab.classList.add("public-theme-filter-fab--visible")
      return
    }
    this.updateFilterFabVisibility()
  }

  updateFilterFabVisibility() {
    if (!this.filterFab) return

    const relevantSectionVisible = this.filterFabSections?.some((section) => {
      const rect = section.getBoundingClientRect()
      const visibleHeight = Math.min(rect.bottom, window.innerHeight) - Math.max(rect.top, 0)
      return visibleHeight >= 48
    })
    // No hero enxuto o botão é a CTA principal da dobra: nunca some.
    const visible = this.heroCompactValue || !this.filterFabMedia?.matches || relevantSectionVisible
    this.filterFab.classList.toggle("public-theme-filter-fab--visible", visible)
  }

  // ===== Hero enxuto no mobile =====
  // O botão do hero e o FAB do canto são o MESMO elemento: no topo ele fica
  // centralizado na dobra e, a qualquer rolagem, desliza para a posição docada.
  initHeroCompactFab() {
    if (!this.heroCompactValue) return

    this.heroCompactFab = this.element.querySelector(".public-theme-filter-fab")
    this.heroCompactHero = this.element.querySelector(".sl-hero")
    if (!this.heroCompactFab || !this.heroCompactHero) return

    this.heroCompactOffset = null
    this.heroCompactCentered = null
    this.handleHeroCompactResize = () => {
      this.heroCompactOffset = null
      // Se o botão já está centralizado, remede e reposiciona na hora: o
      // updateHeroCompactFab sozinho não faria nada, porque o estado não mudou.
      if (this.heroCompactCentered) this.applyHeroCompactState(true)
      this.updateHeroCompactFab()
    }

    this.heroCompactMedia = window.matchMedia(`(max-width: ${HERO_COMPACT_MAX_WIDTH}px)`)
    this.heroCompactMedia.addEventListener?.("change", this.handleHeroCompactResize)
    window.addEventListener("resize", this.handleHeroCompactResize, { passive: true })
    window.addEventListener("orientationchange", this.handleHeroCompactResize)

    // Um frame de folga: medir antes de as fontes do hero assentarem daria uma
    // âncora vertical errada.
    window.requestAnimationFrame(() => this.updateHeroCompactFab())
  }

  updateHeroCompactFab() {
    if (!this.heroCompactFab) return

    const centered = Boolean(this.heroCompactMedia?.matches) && window.scrollY <= HERO_COMPACT_DOCK_SCROLL
    if (centered === this.heroCompactCentered) return

    const firstRun = this.heroCompactCentered === null
    this.heroCompactCentered = centered

    // Na primeira aplicação o botão já nasce no estado certo, sem piscar.
    if (firstRun) {
      this.applyHeroCompactState(centered)
      return
    }

    // Os dois estados diferem em posição E forma, então a troca só acontece com
    // o botão invisível: ele some onde estava e reaparece já no outro formato.
    window.clearTimeout(this.heroCompactFadeTimer)
    this.heroCompactFab.classList.add("public-theme-filter-fab--fading")
    this.heroCompactFadeTimer = window.setTimeout(() => {
      this.applyHeroCompactState(this.heroCompactCentered)
      this.heroCompactFab?.classList.remove("public-theme-filter-fab--fading")
    }, HERO_COMPACT_FADE_MS)
  }

  applyHeroCompactState(centered) {
    if (centered && !this.heroCompactOffset) {
      this.heroCompactOffset = this.measureHeroCompactOffset()
      this.heroCompactFab.style.setProperty("--sl-fab-dx", `${this.heroCompactOffset.dx}px`)
      this.heroCompactFab.style.setProperty("--sl-fab-dy", `${this.heroCompactOffset.dy}px`)
    }

    this.heroCompactFab.classList.toggle("public-theme-filter-fab--hero", centered)
  }

  // Âncora vertical: meio do espaço livre entre o fim do texto do hero e o pé
  // da dobra — acompanha título/lead de qualquer altura, sem número fixo.
  measureHeroCompactOffset() {
    const fab = this.heroCompactFab
    const hero = this.heroCompactHero

    // Mede a PÍLULA na âncora docada: sem o translate (--measuring) e já com a
    // forma do estado centralizado (--hero), senão o retângulo seria o do
    // círculo, que tem tamanho diferente e jogaria o centro fora do lugar.
    const wasHero = fab.classList.contains("public-theme-filter-fab--hero")
    fab.classList.add("public-theme-filter-fab--hero", "public-theme-filter-fab--measuring")
    const dockedRect = fab.getBoundingClientRect()
    fab.classList.remove("public-theme-filter-fab--measuring")
    if (!wasHero) fab.classList.remove("public-theme-filter-fab--hero")

    // Normaliza o hero para coordenadas de página, para a medida valer mesmo se
    // recalculada com a página rolada. O FAB é fixed, então o retângulo dele já
    // é relativo à viewport e fica fora dessa conta.
    const scrollY = window.scrollY
    const heroRect = hero.getBoundingClientRect()
    const heroBottom = heroRect.bottom + scrollY
    const content = hero.querySelector(".sl-lead") || hero.querySelector(".public-theme-hero__title")
    const contentBottom = content
      ? content.getBoundingClientRect().bottom + scrollY
      : heroRect.top + scrollY + heroRect.height / 2

    const targetX = heroRect.left + heroRect.width / 2
    const targetY = (contentBottom + heroBottom) / 2

    return {
      dx: Math.round(targetX - (dockedRect.left + dockedRect.width / 2)),
      dy: Math.round(targetY - (dockedRect.top + dockedRect.height / 2))
    }
  }
}
