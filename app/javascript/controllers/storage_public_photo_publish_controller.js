import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar", "percent", "message", "processed", "total", "published", "failed", "button"]
  static values = {
    url: String,
    runningInterval: { type: Number, default: 1200 },
    idleInterval: { type: Number, default: 7000 }
  }

  connect() {
    this.refresh()
  }

  disconnect() {
    this.stop()
  }

  refresh() {
    if (!this.hasUrlValue || document.hidden) {
      this.schedule(this.idleIntervalValue)
      return
    }

    fetch(this.urlWithCacheBust(), { headers: { Accept: "application/json" } })
      .then((response) => {
        if (!response.ok) throw new Error("status_request_failed")
        return response.json()
      })
      .then((status) => {
        this.render(status)
        this.schedule(this.activeStatus(status.status) ? this.runningIntervalValue : this.idleIntervalValue)
      })
      .catch(() => this.schedule(this.idleIntervalValue))
  }

  stop() {
    if (!this.timer) return

    clearTimeout(this.timer)
    this.timer = null
  }

  schedule(interval) {
    this.stop()
    this.timer = setTimeout(() => this.refresh(), interval)
  }

  render(status) {
    const percent = Math.max(0, Math.min(100, Number(status.percent || 0)))

    if (this.hasBarTarget) {
      this.barTarget.style.width = `${percent}%`
      this.barTarget.parentElement?.setAttribute("aria-valuenow", percent.toString())
    }

    this.setTextIfPresent("percent", this.percent(percent))
    this.setTextIfPresent("message", status.message || "Nenhuma publicação em andamento.")
    this.setTextIfPresent("processed", this.integer(status.processed))
    this.setTextIfPresent("total", this.integer(status.total))
    this.setTextIfPresent("published", this.integer(status.published))
    this.setTextIfPresent("failed", this.integer(status.failed))

    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = this.activeStatus(status.status)
    }
  }

  activeStatus(status) {
    return ["queued", "running"].includes(status)
  }

  setTextIfPresent(name, value) {
    if (!this[`has${this.capitalize(name)}Target`]) return

    this[`${name}Target`].textContent = value
  }

  capitalize(value) {
    return value.charAt(0).toUpperCase() + value.slice(1)
  }

  integer(value) {
    return new Intl.NumberFormat("pt-BR").format(Number(value || 0))
  }

  percent(value) {
    return `${new Intl.NumberFormat("pt-BR", {
      minimumFractionDigits: 1,
      maximumFractionDigits: 1
    }).format(Number(value || 0))}%`
  }

  urlWithCacheBust() {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("_ts", Date.now().toString())
    return url.toString()
  }
}
