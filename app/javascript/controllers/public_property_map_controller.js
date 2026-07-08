import { Controller } from "@hotwired/stimulus"

const LEAFLET_CSS_URL = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
const LEAFLET_JS_URL = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"

export default class extends Controller {
  static targets = ["map"]
  static values = {
    latitude: Number,
    longitude: Number,
    radius: { type: Number, default: 220 }
  }

  connect() {
    if (!this.hasMapTarget || !this.hasValidCoordinates) return

    this.intersectionObserver = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return
      this.intersectionObserver.disconnect()
      this.load()
    }, { rootMargin: "180px" })

    this.intersectionObserver.observe(this.element)
  }

  disconnect() {
    if (this.intersectionObserver) this.intersectionObserver.disconnect()
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  get hasValidCoordinates() {
    return Number.isFinite(this.latitudeValue) &&
      Number.isFinite(this.longitudeValue) &&
      this.latitudeValue >= -90 &&
      this.latitudeValue <= 90 &&
      this.longitudeValue >= -180 &&
      this.longitudeValue <= 180 &&
      !(this.latitudeValue === 0 && this.longitudeValue === 0)
  }

  async load() {
    await this.ensureLeafletLoaded()
    if (!window.L || this.map) return

    const center = [this.latitudeValue, this.longitudeValue]
    this.map = window.L.map(this.mapTarget, {
      attributionControl: true,
      dragging: false,
      scrollWheelZoom: false,
      doubleClickZoom: false,
      boxZoom: false,
      keyboard: false,
      tap: false,
      zoomControl: false
    }).setView(center, 15)

    window.L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: "© OpenStreetMap",
      maxZoom: 19
    }).addTo(this.map)

    window.L.circle(center, {
      radius: this.radiusValue,
      color: "#053c5e",
      fillColor: "#0b6b8f",
      fillOpacity: 0.16,
      weight: 2
    }).addTo(this.map)

    window.requestAnimationFrame(() => this.map.invalidateSize())
  }

  async ensureLeafletLoaded() {
    if (window.L) return

    await Promise.all([
      this.loadCSS(LEAFLET_CSS_URL),
      this.loadScript(LEAFLET_JS_URL)
    ])
  }

  loadCSS(href) {
    return new Promise((resolve) => {
      if (document.querySelector(`link[href="${href}"]`)) return resolve()

      const link = document.createElement("link")
      link.rel = "stylesheet"
      link.href = href
      link.onload = resolve
      document.head.appendChild(link)
    })
  }

  loadScript(src) {
    return new Promise((resolve, reject) => {
      if (document.querySelector(`script[src="${src}"]`)) return resolve()

      const script = document.createElement("script")
      script.src = src
      script.async = true
      script.onload = resolve
      script.onerror = reject
      document.head.appendChild(script)
    })
  }
}
