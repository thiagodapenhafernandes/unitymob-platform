import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    chartUrl: String,
    leads: Array,
    leadsMode: { type: String, default: "daily" },
    leadsUrls: Array,
    statuses: Object,
    acquisitionChannels: Array,
    acquisitionTrend: Array
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
        this.renderAcquisitionChart()
        this.renderAcquisitionTrendChart()
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
    const chartTheme = this.chartTheme()

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
        onClick: (_event, elements) => {
          const index = elements?.[0]?.index
          const url = Number.isInteger(index) ? this.leadsUrlsValue[index] : null
          if (url) window.location.assign(url)
        },
        onHover: (event, elements) => {
          if (event?.native?.target) event.native.target.style.cursor = elements.length ? "pointer" : "default"
        },
        plugins: { legend: { display: false }, tooltip: { mode: "index", intersect: false } },
        scales: {
          y: { beginAtZero: true, ticks: { precision: 0, color: chartTheme.text }, grid: { color: chartTheme.grid } },
          x: { grid: { display: false }, ticks: { color: chartTheme.text, autoSkip: true, maxTicksLimit: 8 } }
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
    const chartTheme = this.chartTheme()

    this.destroyChart("status")
    this.charts.status = new window.Chart(canvas, {
      type: "doughnut",
      data: {
        labels,
        datasets: [{
          data: values,
          backgroundColor: palette.slice(0, labels.length),
          borderWidth: 2,
          borderColor: chartTheme.surface
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        resizeDelay: 150,
        animation: { duration: 300 },
        cutout: "62%",
        plugins: {
          legend: { position: "bottom", labels: { color: chartTheme.text, boxWidth: 12, padding: 12, font: { size: 11 } } }
        }
      }
    })
  }

  renderAcquisitionChart() {
    const canvas = this.element.querySelector("#leadsAcquisitionChart")
    if (!canvas || !window.Chart) return
    const theme = this.chartTheme()
    this.destroyChart("acquisition")
    this.charts.acquisition = new window.Chart(canvas, {
      type: "bar",
      data: { labels: this.acquisitionChannelsValue.map((row) => row.label), datasets: [{ data: this.acquisitionChannelsValue.map((row) => row.count), backgroundColor: "#325c8e", borderRadius: 4 }] },
      options: { indexAxis: "y", responsive: true, maintainAspectRatio: false, plugins: { legend: { display: false } }, scales: {
        x: { beginAtZero: true, ticks: { precision: 0, color: theme.text }, grid: { color: theme.grid } },
        y: { ticks: { color: theme.text }, grid: { display: false } }
      } }
    })
  }

  renderAcquisitionTrendChart() {
    const canvas = this.element.querySelector("#leadsAcquisitionTrendChart")
    if (!canvas || !window.Chart) return
    const labels = [...new Set(this.acquisitionTrendValue.map((row) => row.date))].sort()
    const channels = [...new Set(this.acquisitionTrendValue.map((row) => row.channel))]
    const names = Object.fromEntries(this.acquisitionChannelsValue.map((row) => [row.key, row.label]))
    const palette = ["#325c8e", "#2f7d5c", "#d99a2b", "#7b68a6", "#738297", "#b42318", "#4f9d8f", "#98a2b3"]
    const theme = this.chartTheme()
    this.destroyChart("acquisitionTrend")
    this.charts.acquisitionTrend = new window.Chart(canvas, {
      type: "bar",
      data: { labels: labels.map((date) => date.split("-").reverse().slice(0, 2).join("/")), datasets: channels.map((channel, index) => ({
        label: names[channel] || channel.replaceAll("_", " "),
        data: labels.map((date) => this.acquisitionTrendValue.find((row) => row.date === date && row.channel === channel)?.count || 0),
        backgroundColor: palette[index % palette.length], stack: "channels"
      })) },
      options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { position: "bottom", labels: { color: theme.text, boxWidth: 10, font: { size: 10 } } } }, scales: {
        x: { stacked: true, ticks: { color: theme.text, maxTicksLimit: 10 }, grid: { display: false } },
        y: { stacked: true, beginAtZero: true, ticks: { precision: 0, color: theme.text }, grid: { color: theme.grid } }
      } }
    })
  }

  chartTheme() {
    const styles = getComputedStyle(document.documentElement)
    const dark = document.documentElement.dataset.adminTheme === "dark"

    return {
      text: dark ? styles.getPropertyValue("--ab-muted").trim() || "#b4bdca" : "#667085",
      grid: dark ? "rgba(230,237,247,0.10)" : "rgba(15,23,42,0.06)",
      surface: dark ? styles.getPropertyValue("--admin-surface").trim() || "#172033" : "#ffffff"
    }
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
