import { Controller } from "@hotwired/stimulus"

// Drawer "Filtro detalhado" do site público, compartilhado por todos os temas
// (cada tema só muda o CSS). Abre/fecha, trava a rolagem, e cuida dos controles
// do formulário: finalidade (__segment), faixas (__range-track), pills de quantidade.
// Os selects múltiplos são o controller `combobox`.
export default class extends Controller {
  static targets = ["drawer", "form", "trigger", "visual", "content"]

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    // Outros pontos da página (ex.: "Filtro detalhado" do hero em Barra) abrem o drawer por evento, sem depender do botão flutuante.
    this.handleExternalOpen = (event) => {
      if (event.detail) event.detail.handled = true
      this.open()
    }
    window.addEventListener("public-filter-drawer:open", this.handleExternalOpen)
  }

  disconnect() {
    window.removeEventListener("public-filter-drawer:open", this.handleExternalOpen)
    document.removeEventListener("keydown", this.handleKeydown)
    this.unlockScroll()
  }

  open(event) {
    event?.preventDefault()
    if (this.hasContentTarget) this.contentTarget.replaceWith(this.contentTarget.content)
    if (this.hasVisualTarget && this.visualTarget.dataset.backgroundUrl) {
      this.visualTarget.style.backgroundImage = `url(${JSON.stringify(this.visualTarget.dataset.backgroundUrl)})`
      delete this.visualTarget.dataset.backgroundUrl
    }
    this.lastTrigger = event?.currentTarget || null
    this.drawerTarget.classList.add("open")
    this.drawerTarget.setAttribute("aria-hidden", "false")
    this.triggerTargets.forEach((trigger) => trigger.setAttribute("aria-expanded", "true"))
    document.addEventListener("keydown", this.handleKeydown)
    this.lockScroll()
    this.drawAllRanges()
    window.requestAnimationFrame(() => this.drawerTarget.querySelector("[data-filter-drawer-initial-focus]")?.focus({ preventScroll: true }))
  }

  close(event) {
    event?.preventDefault()
    if (!this.drawerTarget.classList.contains("open")) return

    this.drawerTarget.classList.remove("open")
    this.drawerTarget.setAttribute("aria-hidden", "true")
    this.triggerTargets.forEach((trigger) => trigger.setAttribute("aria-expanded", "false"))
    document.removeEventListener("keydown", this.handleKeydown)
    this.unlockScroll()
    this.lastTrigger?.focus({ preventScroll: true })
  }

  handleKeydown(event) {
    if (event.key === "Escape" && !event.target.closest?.(".public-theme-combobox.open")) this.close()
  }

  // Botão "Limpar" é type=reset: o navegador limpa os campos nativos e aqui
  // voltam os controles desenhados (finalidade, pills, faixas).
  reset() {
    window.setTimeout(() => {
      this.formTarget.querySelectorAll(".public-theme-filter-drawer__segment").forEach((group) => {
        group.querySelectorAll("button").forEach((button, index) => {
          button.setAttribute("aria-pressed", index === 0 ? "true" : "false")
        })
      })
      const transaction = this.formTarget.querySelector('[data-segmented-input="transaction"]')
      if (transaction) transaction.value = "venda"
      this.syncPriceRangeForTransaction("venda")
      this.formTarget.querySelectorAll("[data-pill-group]").forEach((group) => {
        group.querySelectorAll("button").forEach((button) => button.setAttribute("aria-pressed", "false"))
        this.syncPillInput(group)
      })
      this.formTarget.querySelectorAll(".public-theme-filter-drawer__range-track").forEach((track) => {
        const lo = track.querySelector(".public-theme-filter-drawer__range-lo")
        const hi = track.querySelector(".public-theme-filter-drawer__range-hi")
        if (lo) lo.value = track.dataset.min
        if (hi) hi.value = track.dataset.max
        this.drawRangeTrack(track)
      })
    }, 0)
  }

  setSegment(event) {
    const button = event.currentTarget
    const group = button.closest(".public-theme-filter-drawer__segment")
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
    const group = button.closest("[data-pill-group]")
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

  drawRange(event) {
    const track = event.currentTarget.closest(".public-theme-filter-drawer__range-track")
    if (track) this.drawRangeTrack(track)
  }

  raiseRangeThumb(event) {
    const track = event.currentTarget.closest(".public-theme-filter-drawer__range-track")
    if (!track) return

    track.querySelectorAll("input[type='range']").forEach((input) => { input.style.zIndex = 3 })
    event.currentTarget.style.zIndex = 6
  }

  drawAllRanges() {
    this.element.querySelectorAll(".public-theme-filter-drawer__range-track").forEach((track) => this.drawRangeTrack(track))
  }

  syncPriceRangeForTransaction(transaction) {
    const track = this.formTarget.querySelector('.public-theme-filter-drawer__range-track[data-range="valor"]')
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

    const lo = track.querySelector(".public-theme-filter-drawer__range-lo")
    const hi = track.querySelector(".public-theme-filter-drawer__range-hi")
    if (lo) lo.value = min
    if (hi) hi.value = max
    this.drawRangeTrack(track)
  }

  isRentalTransaction(transaction) {
    return ["aluguel", "locacao", "locação", "alugar"].includes((transaction || "").toLowerCase())
  }

  drawRangeTrack(track) {
    const lo = track.querySelector(".public-theme-filter-drawer__range-lo")
    const hi = track.querySelector(".public-theme-filter-drawer__range-hi")
    const fill = track.querySelector(".public-theme-filter-drawer__range-fill")
    const wrap = track.closest(".public-theme-filter-drawer__range")
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

  lockScroll() {
    document.documentElement.classList.add("public-global-search-lock")
    document.body.classList.add("public-global-search-lock")
  }

  unlockScroll() {
    document.documentElement.classList.remove("public-global-search-lock")
    document.body.classList.remove("public-global-search-lock")
  }
}
