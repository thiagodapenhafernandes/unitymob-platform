import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    chartUrl: String,
    data: Object
  }

  connect() {
    this.charts = {}
    this.renderCharts()
    this.handleFullscreenChange = this.handleFullscreenChange.bind(this)
    document.addEventListener("fullscreenchange", this.handleFullscreenChange)
    this.enterTvFromQueryString()
  }

  disconnect() {
    document.removeEventListener("fullscreenchange", this.handleFullscreenChange)
    this.clearTvBodyState()
    this.destroyCharts()
  }

  renderCharts(options = {}) {
    this.ensureChartJs().then(() => {
      requestAnimationFrame(() => {
        Object.entries(this.chartConfigs()).forEach(([id, config]) => this.renderOne(id, config, options))
      })
    }).catch(() => {})
  }

  enterTv(event) {
    this.enterTvMode(event.currentTarget.dataset.captTvTab)
  }

  enterActiveTv() {
    this.enterTvMode(this.activeTabId())
  }

  exitTv() {
    this.finishTvTransition()
    this.clearTvBodyState()
    const exitButton = this.element.querySelector("[data-capt-tv-exit]")
    if (exitButton) exitButton.hidden = true
    if (document.fullscreenElement) document.exitFullscreen().catch(() => {})
    window.setTimeout(() => this.renderCharts({ force: true }), 180)
  }

  rerenderVisibleCharts() {
    window.setTimeout(() => this.renderCharts({ force: true }), 120)
  }

  enterTvMode(tabId, requestFullscreen = true) {
    const targetTabId = tabId || "tab-geral"
    this.startTvTransition()
    this.activateTab(targetTabId)
    document.body.classList.add("capt-dashboard-tv-active")
    this.setTvBodyTabClass(targetTabId)
    const exitButton = this.element.querySelector("[data-capt-tv-exit]")
    if (exitButton) exitButton.hidden = false

    const fullscreenRequest = requestFullscreen && this.element.requestFullscreen && !document.fullscreenElement
      ? this.element.requestFullscreen().catch(() => {})
      : Promise.resolve()

    fullscreenRequest.finally(() => {
      requestAnimationFrame(() => requestAnimationFrame(() => {
        this.renderCharts({ force: true })
        window.setTimeout(() => this.finishTvTransition(), 180)
      }))
    })
  }

  enterTvFromQueryString() {
    const params = new URLSearchParams(window.location.search)
    if (params.get("tv") !== "1") return
    window.setTimeout(() => this.enterTvMode(params.get("tab") || this.activeTabId(), false), 0)
  }

  activateTab(tabId) {
    const trigger = this.element.querySelector(`[data-ax-tabs-target-param="#${tabId}"]`)
    if (trigger) trigger.click()
  }

  activeTabId() {
    return this.element.querySelector("#captTabs .ax-form-tabs__item.active")?.dataset.axTabsTargetParam?.replace("#", "") || "tab-geral"
  }

  ensureChartJs() {
    if (window.Chart) return Promise.resolve()
    if (window.__captDashChartLoader) return window.__captDashChartLoader

    window.__captDashChartLoader = new Promise((resolve, reject) => {
      let script = document.getElementById("capt-dashboard-chartjs")
      if (!script) {
        script = document.createElement("script")
        script.id = "capt-dashboard-chartjs"
        script.src = this.chartUrlValue
        script.async = true
        script.dataset.turboTrack = "reload"
        document.head.appendChild(script)
      }
      script.addEventListener("load", resolve, { once: true })
      script.addEventListener("error", reject, { once: true })
    })

    return window.__captDashChartLoader
  }

  chartConfigs() {
    const data = this.dataValue || {}

    return {
      gaugeVenda: this.gaugeConfig(data.totalVenda, data.metaVenda, "#f59e0b"),
      gaugeLocacao: this.gaugeConfig(data.totalLocacao, data.metaLocacao, "#f59e0b"),
      gaugeVendaBig: this.gaugeConfig(data.totalVenda, data.metaVenda, "#f59e0b"),
      gaugeLocacaoBig: this.gaugeConfig(data.totalLocacao, data.metaLocacao, "#f59e0b"),
      pubVenda: this.donutConfig(data.publicadoVenda, data.naoPublicadoVenda, "#f59e0b"),
      pubLocacao: this.donutConfig(data.publicadoLocacao, data.naoPublicadoLocacao, "#f59e0b"),
      focusVendaBig: this.donutConfig(data.regiaoFocoVenda, Math.max(data.totalVenda - data.regiaoFocoVenda, 0), "#f59e0b"),
      pubVendaBig: this.donutConfig(data.publicadoVenda, data.naoPublicadoVenda, "#f59e0b"),
      focusLocacaoBig: this.donutConfig(data.regiaoFocoLocacao, Math.max(data.totalLocacao - data.regiaoFocoLocacao, 0), "#f59e0b"),
      pubLocacaoBig: this.donutConfig(data.publicadoLocacao, data.naoPublicadoLocacao, "#f59e0b"),
      admLocacaoBig: this.donutConfig(data.captacaoAdmLocacao, Math.max(data.totalLocacao - data.captacaoAdmLocacao, 0), "#f59e0b")
    }
  }

  gaugeConfig(current, target, color) {
    const currentValue = Number(current || 0)
    const targetValue = Math.max(Number(target || 1), 1)

    return {
      type: "doughnut",
      data: {
        datasets: [{
          data: [currentValue, Math.max(targetValue - currentValue, 0)],
          backgroundColor: [color, this.chartPalette().track],
          borderWidth: 0
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        resizeDelay: 150,
        rotation: 270,
        circumference: 180,
        cutout: "75%",
        plugins: { legend: { display: false }, tooltip: { enabled: false } }
      }
    }
  }

  donutConfig(yes, no, color = "#f59e0b", labels = ["Sim", "Não"]) {
    const palette = this.chartPalette()
    return {
      type: "doughnut",
      data: {
        labels,
        datasets: [{
          data: [Number(yes || 0), Number(no || 0)],
          backgroundColor: [color, palette.track],
          borderWidth: 2,
          borderColor: palette.border
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        resizeDelay: 150,
        cutout: "55%",
        plugins: {
          legend: { position: "bottom", labels: { color: palette.legend, boxWidth: 10, padding: 8, font: { size: 11 } } }
        }
      }
    }
  }

  chartPalette() {
    const dark = document.documentElement.dataset.adminTheme === "dark"
    return dark
      ? { track: "#26364d", border: "#172033", legend: "#aebbd0" }
      : { track: "#e5e7eb", border: "#ffffff", legend: "#64748b" }
  }

  renderOne(id, config, options = {}) {
    const canvas = this.element.querySelector(`#${id}`)
    if (!canvas || !window.Chart) return
    if (!options.force && !canvas.offsetParent) return
    this.destroyChart(id)
    this.charts[id] = new window.Chart(canvas, config)
  }

  handleFullscreenChange() {
    if (!document.fullscreenElement) {
      this.finishTvTransition()
      this.clearTvBodyState()
    }
    window.setTimeout(() => this.renderCharts({ force: true }), 180)
  }

  startTvTransition() {
    document.body.classList.add("capt-dashboard-tv-entering")
    const transition = this.element.querySelector("[data-capt-tv-transition]")
    if (transition) transition.hidden = false
  }

  finishTvTransition() {
    document.body.classList.remove("capt-dashboard-tv-entering")
    const transition = this.element.querySelector("[data-capt-tv-transition]")
    if (transition) transition.hidden = true
  }

  setTvBodyTabClass(tabId) {
    this.clearTvTabClass()
    const slug = String(tabId || "tab-geral").replace(/^tab-/, "")
    document.body.classList.add(`capt-dashboard-tv-tab-${slug}`)
  }

  clearTvTabClass() {
    Array.from(document.body.classList).forEach((className) => {
      if (className.startsWith("capt-dashboard-tv-tab-")) {
        document.body.classList.remove(className)
      }
    })
  }

  clearTvBodyState() {
    this.finishTvTransition()
    document.body.classList.remove("capt-dashboard-tv-active")
    this.clearTvTabClass()
  }

  destroyChart(id) {
    if (!this.charts[id]) return
    try { this.charts[id].destroy() } catch (_error) {}
    delete this.charts[id]
  }

  destroyCharts() {
    Object.keys(this.charts || {}).forEach((id) => this.destroyChart(id))
  }
}
