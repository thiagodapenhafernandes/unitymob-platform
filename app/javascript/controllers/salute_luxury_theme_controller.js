import { Controller } from "@hotwired/stimulus"

// Acima desta largura o hero enxuto não vale: o desktop mantém o hero completo.
const HERO_COMPACT_MAX_WIDTH = 768
// Rolagem mínima para o botão sair do centro do hero e docar no canto.
const HERO_COMPACT_DOCK_SCROLL = 8
// Precisa casar com a transição de opacidade do .sl-filter-fab no CSS: é a
// janela em que o botão fica invisível e a troca de estado acontece.
const HERO_COMPACT_FADE_MS = 220

export default class extends Controller {
  static targets = ["header", "mobileNav", "menuMedia", "transactionInput", "transactionButton", "filterDrawer", "filterForm"]

  static values = { heroCompact: Boolean }

  connect() {
    this.handleScroll = this.handleScroll.bind(this)
    this.handleKeydown = this.handleKeydown.bind(this)
    this.closeOpenCombobox = this.closeOpenCombobox.bind(this)

    window.addEventListener("scroll", this.handleScroll, { passive: true })
    document.addEventListener("keydown", this.handleKeydown)
    document.addEventListener("click", this.closeOpenCombobox)

    this.handleScroll()
    this.initComboboxes()
    this.drawAllRanges()
    this.initReveals()
    this.initFilterFabVisibility()
    this.initHeroCompactFab()
  }

  disconnect() {
    window.removeEventListener("scroll", this.handleScroll)
    document.removeEventListener("keydown", this.handleKeydown)
    document.removeEventListener("click", this.closeOpenCombobox)
    window.removeEventListener("resize", this.handleHeroCompactResize)
    window.removeEventListener("orientationchange", this.handleHeroCompactResize)
    this.revealObserver?.disconnect()
    this.filterFabMedia?.removeEventListener?.("change", this.handleFilterFabMediaChange)
    this.heroCompactMedia?.removeEventListener?.("change", this.handleHeroCompactResize)
    window.clearTimeout(this.heroCompactFadeTimer)
    document.body.classList.remove("no-scroll")
  }

  handleScroll() {
    if (this.hasHeaderTarget) this.headerTarget.classList.toggle("scrolled", window.scrollY > 36)
    this.updateFilterFabVisibility()
    this.updateHeroCompactFab()
  }

  handleKeydown(event) {
    if (event.key === "Escape" && this.hasFilterDrawerTarget && this.filterDrawerTarget.classList.contains("open")) {
      this.closeFilter()
    }
  }

  setTransaction(event) {
    const button = event.currentTarget
    this.transactionButtonTargets.forEach((target) => target.setAttribute("aria-pressed", "false"))
    button.setAttribute("aria-pressed", "true")

    if (this.hasTransactionInputTarget) {
      this.transactionInputTarget.value = button.dataset.transactionType || "venda"
    }
  }

  openMenu() {
    if (!this.hasMobileNavTarget) return

    this.loadMenuMedia()
    this.mobileNavTarget.classList.add("open")
    this.mobileNavTarget.setAttribute("aria-hidden", "false")
    document.body.classList.add("no-scroll")
  }

  loadMenuMedia() {
    if (!this.hasMenuMediaTarget) return

    const image = this.menuMediaTarget
    if (image.src || !image.dataset.src) return

    image.src = image.dataset.src
    delete image.dataset.src
  }

  closeMenu() {
    if (!this.hasMobileNavTarget) return

    this.mobileNavTarget.classList.remove("open")
    this.mobileNavTarget.setAttribute("aria-hidden", "true")
    document.body.classList.remove("no-scroll")
  }

  openFilter() {
    if (!this.hasFilterDrawerTarget) return

    this.filterDrawerTarget.classList.add("open")
    this.filterDrawerTarget.setAttribute("aria-hidden", "false")
    document.body.classList.add("no-scroll")
    this.drawAllRanges()
  }

  closeFilter() {
    if (!this.hasFilterDrawerTarget) return

    this.filterDrawerTarget.classList.remove("open")
    this.filterDrawerTarget.setAttribute("aria-hidden", "true")
    document.body.classList.remove("no-scroll")
  }

  setSegment(event) {
    const button = event.currentTarget
    const group = button.closest(".seg")
    if (!group) return

    group.querySelectorAll("button").forEach((target) => target.setAttribute("aria-pressed", "false"))
    button.setAttribute("aria-pressed", "true")

    const segmentName = group.dataset.segmented || group.dataset.seg
    const value = button.dataset.value || ""
    const input = this.element.querySelector(`[data-segmented-input="${segmentName}"]`)
    if (input) input.value = value
    if (segmentName === "transaction") this.syncPriceRangeForTransaction(value)
  }

  setPill(event) {
    const button = event.currentTarget
    const group = button.closest("[data-pills], [data-pill-group]")
    if (!group) return

    const wasPressed = button.getAttribute("aria-pressed") === "true"
    group.querySelectorAll("button").forEach((target) => target.setAttribute("aria-pressed", "false"))
    button.setAttribute("aria-pressed", wasPressed ? "false" : "true")

    this.syncPillInput(group)
  }

  // O hidden do grupo troca de nome conforme a pill: 1/2/3 mandam a quantidade
  // exata (bedrooms/suites/parking) e o 4+ manda o mínimo (min_*).
  syncPillInput(group) {
    const input = group.querySelector("[data-pill-input]")
    if (!input) return

    const active = group.querySelector("button[aria-pressed='true']")
    if (active) {
      input.name = active.dataset.name || input.dataset.pillInput
      input.value = active.dataset.value || ""
    } else {
      input.name = input.dataset.pillInput
      input.value = ""
    }
  }

  toggleQuickFilter(event) {
    const chip = event.currentTarget
    const checkbox = this.characteristicCheckbox(chip.dataset.quickFilter)
    if (!checkbox) return

    checkbox.checked = !checkbox.checked
    chip.setAttribute("aria-pressed", checkbox.checked ? "true" : "false")
  }

  syncQuickFilters() {
    if (!this.hasFilterFormTarget) return

    this.filterFormTarget.querySelectorAll("[data-quick-filter]").forEach((chip) => {
      const checkbox = this.characteristicCheckbox(chip.dataset.quickFilter)
      chip.setAttribute("aria-pressed", checkbox && checkbox.checked ? "true" : "false")
    })
  }

  characteristicCheckbox(value) {
    if (!value || !this.hasFilterFormTarget) return null

    return this.filterFormTarget.querySelector(`input[type='checkbox'][data-characteristic="${value}"]`)
  }

  drawRange(event) {
    const track = event.currentTarget.closest(".dr-track")
    if (track) this.drawRangeTrack(track)
  }

  raiseRangeThumb(event) {
    const track = event.currentTarget.closest(".dr-track")
    if (!track) return

    track.querySelectorAll("input[type='range']").forEach((input) => { input.style.zIndex = 3 })
    event.currentTarget.style.zIndex = 6
  }

  resetFilter() {
    window.setTimeout(() => {
      if (!this.hasFilterFormTarget) return

      this.filterFormTarget.querySelectorAll(".seg").forEach((group) => {
        group.querySelectorAll("button").forEach((button, index) => {
          button.setAttribute("aria-pressed", index === 0 ? "true" : "false")
        })
      })
      this.syncPriceRangeForTransaction("venda")
      this.filterFormTarget.querySelectorAll("[data-pills], [data-pill-group]").forEach((group) => {
        group.querySelectorAll("button").forEach((button) => button.setAttribute("aria-pressed", "false"))
        this.syncPillInput(group)
      })
      this.syncQuickFilters()
      this.filterFormTarget.querySelectorAll(".dr-track").forEach((track) => {
        const lo = track.querySelector(".dr-lo")
        const hi = track.querySelector(".dr-hi")
        if (lo) lo.value = track.dataset.min
        if (hi) hi.value = track.dataset.max
        this.drawRangeTrack(track)
      })
    }, 0)
  }

  initComboboxes() {
    this.element.querySelectorAll("[data-cbx]").forEach((combobox) => {
      if (combobox.dataset.initialized === "true") return

      combobox.dataset.initialized = "true"
      const hidden = combobox.querySelector("input[type='hidden']")
      const trigger = combobox.querySelector(".cbx-trigger")
      const tags = combobox.querySelector(".cbx-tags")
      const input = combobox.querySelector(".cbx-input")
      const panel = combobox.querySelector(".cbx-panel")
      const empty = combobox.querySelector(".cbx-empty")
      const options = Array.from(panel.querySelectorAll(".cbx-opt"))
      const placeholder = input.getAttribute("placeholder") || ""
      const compactSelection = combobox.closest(".drawer-form") !== null
      const selected = new Map()

      options.forEach((option) => {
        option.dataset.raw = option.querySelector(".cbx-lbl").textContent
        option.insertAdjacentHTML("beforeend", '<svg class="cbx-check" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 13l4 4L19 7"/></svg>')
      })

      const visible = () => options.filter((option) => option.style.display !== "none")
      const clearActive = () => options.forEach((option) => option.classList.remove("active"))
      const setActive = (option) => {
        clearActive()
        if (!option) return

        option.classList.add("active")
        option.scrollIntoView({ block: "nearest" })
      }
      const open = () => {
        if (combobox.classList.contains("open")) return

        this.element.querySelectorAll(".cbx.open").forEach((openCombobox) => {
          if (openCombobox !== combobox) openCombobox.classList.remove("open")
        })
        combobox.classList.add("open")
        trigger.setAttribute("aria-expanded", "true")
        setActive(visible()[0])
      }
      const close = () => {
        combobox.classList.remove("open")
        trigger.setAttribute("aria-expanded", "false")
        clearActive()
      }
      const filter = () => {
        const query = this.normalize(input.value)
        let any = false

        options.forEach((option) => {
          const raw = option.dataset.raw || ""
          const show = !query || this.normalize(option.dataset.search || raw).includes(query)
          option.style.display = show ? "" : "none"
          if (show) any = true
          option.querySelector(".cbx-lbl").textContent = raw
        })

        if (empty) empty.hidden = any
      }
      const sync = () => {
        hidden.value = Array.from(selected.keys()).join(", ")
        tags.innerHTML = ""
        const entries = Array.from(selected.entries())
        const appendTag = (value, label) => {
          const tag = document.createElement("span")
          tag.className = "cbx-tag"
          tag.innerHTML = '<span></span><button type="button" aria-label="Remover">&times;</button>'
          tag.querySelector("span").textContent = label
          tag.querySelector("button").addEventListener("mousedown", (event) => {
            event.preventDefault()
            event.stopPropagation()
            toggle(value, label)
          })
          tags.appendChild(tag)
        }

        if (compactSelection && entries.length > 1) {
          const [value, label] = entries[0]
          appendTag(value, label)

          const count = document.createElement("span")
          count.className = "cbx-count"
          count.textContent = entries.length
          count.setAttribute("aria-label", `${entries.length} itens selecionados`)
          tags.appendChild(count)
        } else {
          entries.forEach(([value, label]) => appendTag(value, label))
        }
        input.placeholder = selected.size ? "" : placeholder
      }
      const toggle = (value, label) => {
        const option = options.find((candidate) => candidate.dataset.value === value)
        if (selected.has(value)) {
          selected.delete(value)
          if (option) option.classList.remove("selected")
        } else {
          selected.set(value, label)
          if (option) option.classList.add("selected")
        }
        sync()
      }
      const pick = (option) => {
        toggle(option.dataset.value, option.dataset.raw)
        input.value = ""
        filter()
        input.focus()
      }

      options.forEach((option) => {
        option.addEventListener("mousedown", (event) => {
          event.preventDefault()
          pick(option)
        })
      })
      input.addEventListener("input", () => {
        open()
        filter()
        setActive(visible()[0])
      })
      input.addEventListener("focus", open)
      trigger.addEventListener("click", (event) => {
        if (event.target.closest(".cbx-tag")) return
        input.focus()
        open()
      })
      combobox.addEventListener("keydown", (event) => {
        if (event.key === "ArrowDown" || event.key === "ArrowUp") {
          event.preventDefault()
          if (!combobox.classList.contains("open")) {
            open()
            return
          }
          const candidates = visible()
          if (!candidates.length) return
          let index = candidates.findIndex((option) => option.classList.contains("active"))
          index = event.key === "ArrowDown" ? (index + 1) % candidates.length : (index - 1 + candidates.length) % candidates.length
          setActive(candidates[index])
        } else if (event.key === "Enter") {
          event.preventDefault()
          const active = panel.querySelector(".cbx-opt.active")
          if (combobox.classList.contains("open") && active && active.style.display !== "none") pick(active)
        } else if (event.key === "Escape") {
          close()
          input.blur()
        }
      })

      sync()
      filter()
    })
  }

  closeOpenCombobox(event) {
    this.element.querySelectorAll(".cbx.open").forEach((combobox) => {
      if (!combobox.contains(event.target)) {
        combobox.classList.remove("open")
        combobox.querySelector(".cbx-trigger")?.setAttribute("aria-expanded", "false")
      }
    })
  }

  drawAllRanges() {
    this.element.querySelectorAll(".dr-track").forEach((track) => this.drawRangeTrack(track))
  }

  syncPriceRangeForTransaction(transaction) {
    if (!this.hasFilterFormTarget) return

    const track = this.filterFormTarget.querySelector('.dr-track[data-range="valor"]')
    if (!track) return

    const prefix = this.isRentalTransaction(transaction) ? "rental" : "sale"
    const min = Number(track.dataset[`${prefix}Min`] || track.dataset.min)
    const max = Number(track.dataset[`${prefix}Max`] || track.dataset.max)
    const step = Number(track.dataset[`${prefix}Step`] || track.dataset.step)
    if (!Number.isFinite(min) || !Number.isFinite(max) || !Number.isFinite(step) || max <= min || step <= 0) return

    this.configureRangeTrack(track, { min, max, step })
  }

  configureRangeTrack(track, { min, max, step }) {
    track.dataset.min = min
    track.dataset.max = max
    track.dataset.step = step

    track.querySelectorAll("input[type='range']").forEach((input) => {
      input.min = min
      input.max = max
      input.step = step
    })

    const lo = track.querySelector(".dr-lo")
    const hi = track.querySelector(".dr-hi")
    if (lo) lo.value = min
    if (hi) hi.value = max
    this.drawRangeTrack(track)
  }

  isRentalTransaction(transaction) {
    return ["aluguel", "locacao", "locação", "alugar"].includes((transaction || "").toLowerCase())
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
    this.filterFab = this.element.querySelector(".sl-filter-fab")
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
      this.filterFab.classList.add("sl-filter-fab--visible")
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
    this.filterFab.classList.toggle("sl-filter-fab--visible", visible)
  }

  // ===== Hero enxuto no mobile =====
  // O botão do hero e o FAB do canto são o MESMO elemento: no topo ele fica
  // centralizado na dobra e, a qualquer rolagem, desliza para a posição docada.
  initHeroCompactFab() {
    if (!this.heroCompactValue) return

    this.heroCompactFab = this.element.querySelector(".sl-filter-fab")
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
    this.heroCompactFab.classList.add("sl-filter-fab--fading")
    this.heroCompactFadeTimer = window.setTimeout(() => {
      this.applyHeroCompactState(this.heroCompactCentered)
      this.heroCompactFab?.classList.remove("sl-filter-fab--fading")
    }, HERO_COMPACT_FADE_MS)
  }

  applyHeroCompactState(centered) {
    if (centered && !this.heroCompactOffset) {
      this.heroCompactOffset = this.measureHeroCompactOffset()
      this.heroCompactFab.style.setProperty("--sl-fab-dx", `${this.heroCompactOffset.dx}px`)
      this.heroCompactFab.style.setProperty("--sl-fab-dy", `${this.heroCompactOffset.dy}px`)
    }

    this.heroCompactFab.classList.toggle("sl-filter-fab--hero", centered)
  }

  // Âncora vertical: meio do espaço livre entre o fim do texto do hero e o pé
  // da dobra — acompanha título/lead de qualquer altura, sem número fixo.
  measureHeroCompactOffset() {
    const fab = this.heroCompactFab
    const hero = this.heroCompactHero

    // Mede a PÍLULA na âncora docada: sem o translate (--measuring) e já com a
    // forma do estado centralizado (--hero), senão o retângulo seria o do
    // círculo, que tem tamanho diferente e jogaria o centro fora do lugar.
    const wasHero = fab.classList.contains("sl-filter-fab--hero")
    fab.classList.add("sl-filter-fab--hero", "sl-filter-fab--measuring")
    const dockedRect = fab.getBoundingClientRect()
    fab.classList.remove("sl-filter-fab--measuring")
    if (!wasHero) fab.classList.remove("sl-filter-fab--hero")

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

  drawRangeTrack(track) {
    const lo = track.querySelector(".dr-lo")
    const hi = track.querySelector(".dr-hi")
    const fill = track.querySelector(".dr-fill")
    const wrap = track.closest(".df-range")
    const outLo = wrap?.querySelector("[data-range-out-lo]")
    const outHi = wrap?.querySelector("[data-range-out-hi]")
    if (!lo || !hi || !fill || !outLo || !outHi) return

    const min = Number(track.dataset.min)
    const max = Number(track.dataset.max)
    let low = Number(lo.value)
    let high = Number(hi.value)

    if (low > high) {
      if (document.activeElement === lo) {
        high = low
        hi.value = high
      } else {
        low = high
        lo.value = low
      }
    }

    const lowPercent = ((low - min) / (max - min)) * 100
    const highPercent = ((high - min) / (max - min)) * 100
    fill.style.left = `${lowPercent}%`
    fill.style.width = `${Math.max(0, highPercent - lowPercent)}%`
    outLo.textContent = this.formatRangeValue(track, low, false)
    outHi.textContent = this.formatRangeValue(track, high, true)

    this.syncRangeHidden(track, low, high, min, max)
  }

  syncRangeHidden(track, low, high, min, max) {
    const name = track.dataset.range
    const minInput = this.element.querySelector(`[data-range-hidden="${name}-min"]`)
    const maxInput = this.element.querySelector(`[data-range-hidden="${name}-max"]`)
    if (minInput) minInput.value = low > min ? low : ""
    if (maxInput) maxInput.value = high < max ? high : ""
  }

  formatRangeValue(track, value, top) {
    if (track.dataset.money === "1") {
      return `R$ ${Number(value).toLocaleString("pt-BR")}${top && Number(value) >= Number(track.dataset.max) ? " +" : ""}`
    }

    const suffix = track.dataset.suffix || ""
    const cleanSuffix = suffix.includes("m²") ? " m²" : ""
    return `${Number(value).toLocaleString("pt-BR")}${cleanSuffix}${top && Number(value) >= Number(track.dataset.max) ? " +" : ""}`
  }

  normalize(value) {
    return (value || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .trim()
  }
}
