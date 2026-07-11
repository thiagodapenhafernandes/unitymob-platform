import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    chartUrl: String,
    leads: Array,
    leadsMode: { type: String, default: "daily" },
    statuses: Object
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
        this.renderLeadsChart()
        this.renderStatusChart()
      })
    }).catch(() => {})
  }

  ensureChartJs() {
    if (window.Chart) return Promise.resolve()
    if (window.__adminDashboardChartLoader) return window.__adminDashboardChartLoader

    window.__adminDashboardChartLoader = new Promise((resolve, reject) => {
      let script = document.getElementById("admin-dashboard-chartjs")
      if (!script) {
        script = document.createElement("script")
        script.id = "admin-dashboard-chartjs"
        script.src = this.chartUrlValue
        script.async = true
        script.dataset.turboTrack = "reload"
        document.head.appendChild(script)
      }
      script.addEventListener("load", resolve, { once: true })
      script.addEventListener("error", reject, { once: true })
    })

    return window.__adminDashboardChartLoader
  }

  renderLeadsChart() {
    const canvas = this.element.querySelector("#leadsChart")
    if (!canvas || !window.Chart) return

    const labels = this.leadsValue.map(([date]) => {
      if (this.leadsModeValue === "hourly") return date.toString()

      const [year, month, day] = date.toString().split("-").map((part) => Number.parseInt(part, 10))
      if (year && month && day) return `${String(day).padStart(2, "0")}/${String(month).padStart(2, "0")}`

      const parsed = new Date(date)
      return `${String(parsed.getDate()).padStart(2, "0")}/${String(parsed.getMonth() + 1).padStart(2, "0")}`
    })
    const values = this.leadsValue.map(([, count]) => count)

    this.destroyChart("leads")
    this.charts.leads = new window.Chart(canvas, {
      type: "line",
      data: {
        labels,
        datasets: [{
          label: "Leads",
          data: values,
          borderColor: "#325c8e",
          backgroundColor: "rgba(50,92,142,0.10)",
          borderWidth: 2,
          tension: 0.35,
          fill: true,
          pointBackgroundColor: "#325c8e",
          pointRadius: 3,
          pointHoverRadius: 6
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        resizeDelay: 150,
        animation: { duration: 300 },
        plugins: { legend: { display: false }, tooltip: { mode: "index", intersect: false } },
        scales: {
          y: { beginAtZero: true, ticks: { precision: 0 }, grid: { color: "rgba(15,23,42,0.06)" } },
          x: { grid: { display: false }, ticks: { autoSkip: true, maxTicksLimit: 8 } }
        }
      }
    })
  }

  renderStatusChart() {
    const canvas = this.element.querySelector("#leadsStatusChart")
    if (!canvas || !window.Chart) return

    const labels = Object.keys(this.statusesValue).map((status) => (status || "sem status").toString().replace(/_/g, " "))
    const values = Object.values(this.statusesValue)
    const palette = ["#325c8e", "#2f7d5c", "#d99a2b", "#738297", "#7b68a6", "#b42318", "#98a2b3", "#4f9d8f"]

    this.destroyChart("status")
    this.charts.status = new window.Chart(canvas, {
      type: "doughnut",
      data: {
        labels,
        datasets: [{
          data: values,
          backgroundColor: palette.slice(0, labels.length),
          borderWidth: 2,
          borderColor: "#fff"
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        resizeDelay: 150,
        animation: { duration: 300 },
        cutout: "62%",
        plugins: {
          legend: { position: "bottom", labels: { boxWidth: 12, padding: 12, font: { size: 11 } } }
        }
      }
    })
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
