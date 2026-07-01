import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    chartUrl: String,
    data: Object
  }

  connect() {
    this.charts = {}
    this.render()
  }

  disconnect() {
    this.destroyCharts()
  }

  render() {
    this.ensureChartJs().then(() => {
      requestAnimationFrame(() => {
        this.renderTrendChart()
        this.renderScoreChart()
        this.renderPageTypesChart()
      })
    }).catch(() => {})
  }

  ensureChartJs() {
    if (window.Chart) return Promise.resolve()
    if (window.__seoDashboardChartLoader) return window.__seoDashboardChartLoader

    window.__seoDashboardChartLoader = new Promise((resolve, reject) => {
      let script = document.getElementById("seo-dashboard-chartjs")
      if (!script) {
        script = document.createElement("script")
        script.id = "seo-dashboard-chartjs"
        script.src = this.chartUrlValue
        script.async = true
        script.dataset.turboTrack = "reload"
        document.head.appendChild(script)
      }
      script.addEventListener("load", resolve, { once: true })
      script.addEventListener("error", reject, { once: true })
    })

    return window.__seoDashboardChartLoader
  }

  renderTrendChart() {
    const canvas = this.element.querySelector("#seoTrendChart")
    const trend = this.dataValue.dailyTrend || []
    if (!canvas || !window.Chart) return

    this.destroyChart("trend")
    this.charts.trend = new window.Chart(canvas, {
      type: "line",
      data: {
        labels: trend.map((item) => this.formatDate(item.date)),
        datasets: [
          {
            label: "Acessos",
            data: trend.map((item) => Number(item.visits || 0)),
            borderColor: "#365f8f",
            backgroundColor: "rgba(54,95,143,0.10)",
            borderWidth: 2,
            tension: 0.35,
            fill: true,
            pointRadius: 2,
            pointHoverRadius: 5
          },
          {
            label: "Únicos",
            data: trend.map((item) => Number(item.uniqueVisitors || 0)),
            borderColor: "#2f7d5c",
            backgroundColor: "rgba(47,125,92,0.08)",
            borderWidth: 2,
            tension: 0.35,
            fill: false,
            pointRadius: 2,
            pointHoverRadius: 5
          }
        ]
      },
      options: this.lineOptions()
    })
  }

  renderScoreChart() {
    const canvas = this.element.querySelector("#seoScoreChart")
    const buckets = this.dataValue.scoreBuckets || {}
    if (!canvas || !window.Chart) return

    this.destroyChart("score")
    this.charts.score = new window.Chart(canvas, {
      type: "doughnut",
      data: {
        labels: ["Bom", "Atenção", "Fraco"],
        datasets: [{
          data: [
            Number(buckets.strong || 0),
            Number(buckets.attention || 0),
            Number(buckets.weak || 0)
          ],
          backgroundColor: ["#16a34a", "#d97706", "#dc2626"],
          borderColor: "#fff",
          borderWidth: 2
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        resizeDelay: 150,
        cutout: "62%",
        animation: { duration: 300 },
        plugins: {
          legend: { position: "bottom", labels: { boxWidth: 10, padding: 10, font: { size: 11 } } }
        }
      }
    })
  }

  renderPageTypesChart() {
    const canvas = this.element.querySelector("#seoPageTypesChart")
    const pageTypes = this.dataValue.pageTypes || []
    if (!canvas || !window.Chart) return

    this.destroyChart("pageTypes")
    this.charts.pageTypes = new window.Chart(canvas, {
      type: "bar",
      data: {
        labels: pageTypes.map((item) => item.label || "sem tipo"),
        datasets: [{
          label: "Páginas",
          data: pageTypes.map((item) => Number(item.count || 0)),
          backgroundColor: "#365f8f",
          borderRadius: 4,
          barThickness: 12
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        resizeDelay: 150,
        indexAxis: "y",
        animation: { duration: 300 },
        plugins: { legend: { display: false }, tooltip: { mode: "index", intersect: false } },
        scales: {
          x: { beginAtZero: true, ticks: { precision: 0 }, grid: { color: "rgba(15,23,42,0.06)" } },
          y: { grid: { display: false }, ticks: { font: { size: 10 } } }
        }
      }
    })
  }

  lineOptions() {
    return {
      responsive: true,
      maintainAspectRatio: false,
      resizeDelay: 150,
      animation: { duration: 300 },
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { position: "bottom", labels: { boxWidth: 10, padding: 10, font: { size: 11 } } },
        tooltip: { mode: "index", intersect: false }
      },
      scales: {
        y: { beginAtZero: true, ticks: { precision: 0 }, grid: { color: "rgba(15,23,42,0.06)" } },
        x: { grid: { display: false }, ticks: { autoSkip: true, maxTicksLimit: 8 } }
      }
    }
  }

  formatDate(date) {
    const [year, month, day] = date.toString().split("-").map((part) => Number.parseInt(part, 10))
    if (year && month && day) return `${String(day).padStart(2, "0")}/${String(month).padStart(2, "0")}`

    const parsed = new Date(date)
    return `${String(parsed.getDate()).padStart(2, "0")}/${String(parsed.getMonth() + 1).padStart(2, "0")}`
  }

  destroyChart(name) {
    if (!this.charts[name]) return
    try { this.charts[name].destroy() } catch (_) {}
    delete this.charts[name]
  }

  destroyCharts() {
    Object.keys(this.charts || {}).forEach((name) => this.destroyChart(name))
  }
}
