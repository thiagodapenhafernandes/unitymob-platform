import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    processingInterval: { type: Number, default: 2000 },
    idleInterval: { type: Number, default: 6000 },
    slowInterval: { type: Number, default: 15000 }
  }

  connect() {
    this.boundOnFrameLoad = () => this.reschedule()
    this.element.addEventListener("turbo:frame-load", this.boundOnFrameLoad)
    this.startPolling()
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-load", this.boundOnFrameLoad)
    this.stopPolling()
  }

  startPolling() {
    this.scheduleNextTick()
  }

  stopPolling() {
    if (!this.timer) return

    clearTimeout(this.timer)
    this.timer = null
  }

  reschedule() {
    this.stopPolling()
    this.scheduleNextTick()
  }

  scheduleNextTick() {
    const interval = this.nextInterval()
    this.timer = setTimeout(() => {
      this.refreshFrame()
      this.scheduleNextTick()
    }, interval)
  }

  nextInterval() {
    const status = this.currentStatus()
    if (status === "processing") return this.processingIntervalValue
    if (status === "completed" || status === "failed") return this.slowIntervalValue
    return this.idleIntervalValue
  }

  currentStatus() {
    const marker = this.element.querySelector("[data-dwv-sync-status-state]")
    return marker?.dataset?.syncStatus || "idle"
  }

  refreshFrame() {
    if (document.hidden) return

    const src = this.element.getAttribute("src")
    if (!src) return

    const url = new URL(src, window.location.origin)
    url.searchParams.set("_ts", Date.now().toString())
    this.element.setAttribute("src", `${url.pathname}${url.search}`)
  }
}
