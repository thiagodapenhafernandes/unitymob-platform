import { Controller } from "@hotwired/stimulus"

const LEAFLET_CSS_URL = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
const LEAFLET_JS_URL = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"

export default class extends Controller {
  static targets = ["map", "streetView", "mapButton", "satelliteButton", "streetViewButton", "shell"]
  static values = {
    provider: { type: String, default: "leaflet" },
    apiKey: String,
    latitude: Number,
    longitude: Number,
    streetLatitude: Number,
    streetLongitude: Number,
    radius: { type: Number, default: 220 },
    zoom: { type: Number, default: 15 },
    satelliteEnabled: Boolean,
    streetViewEnabled: Boolean
  }

  connect() {
    if (!this.hasMapTarget || !this.hasValidCoordinates) return

    this.intersectionObserver = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return

      this.intersectionObserver.disconnect()
      this.loadMap()
    }, { rootMargin: "180px" })

    this.intersectionObserver.observe(this.mapTarget)
  }

  disconnect() {
    this.intersectionObserver?.disconnect()
    if (this.leafletMap) this.leafletMap.remove()
    this.leafletMap = null
    this.googleMap = null
    this.streetView = null
  }

  async showMap(event) {
    event?.preventDefault()
    this.scrollToLocation(event)
    await this.loadMap()
    this.activatePanel("map")
    if (this.googleMap) this.googleMap.setMapTypeId("roadmap")
    this.setSatelliteActive(false)
  }

  async showStreetView(event) {
    event?.preventDefault()
    if (!this.streetViewEnabledValue || !this.hasStreetViewCoordinates) return

    this.scrollToLocation(event)
    await this.ensureGoogleLoaded()
    this.activatePanel("street")
    this.initializeStreetView()
  }

  async toggleSatellite(event) {
    event?.preventDefault()
    if (this.providerValue !== "google" || !this.satelliteEnabledValue) return

    await this.loadMap()
    this.activatePanel("map")
    const nextType = this.googleMap.getMapTypeId() === "satellite" ? "roadmap" : "satellite"
    this.googleMap.setMapTypeId(nextType)
    this.setSatelliteActive(nextType === "satellite")
  }

  get hasValidCoordinates() {
    return this.validCoordinatePair(this.latitudeValue, this.longitudeValue)
  }

  get hasStreetViewCoordinates() {
    return this.validCoordinatePair(this.streetLatitudeValue, this.streetLongitudeValue)
  }

  async loadMap() {
    if (this.providerValue === "google" && this.hasApiKeyValue) {
      await this.loadGoogleMap()
    } else {
      await this.loadLeafletMap()
    }
  }

  async loadGoogleMap() {
    await this.ensureGoogleLoaded()
    if (this.googleMap) return

    const center = { lat: this.latitudeValue, lng: this.longitudeValue }
    this.googleMap = new window.google.maps.Map(this.mapTarget, {
      center,
      zoom: this.zoomValue,
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: true,
      gestureHandling: "cooperative"
    })

    if (this.radiusValue > 0) {
      new window.google.maps.Circle({
        map: this.googleMap,
        center,
        radius: this.radiusValue,
        strokeColor: "#053c5e",
        strokeOpacity: 0.9,
        strokeWeight: 2,
        fillColor: "#0b6b8f",
        fillOpacity: 0.16
      })
    } else {
      new window.google.maps.Marker({ map: this.googleMap, position: center })
    }
  }

  async loadLeafletMap() {
    await this.ensureLeafletLoaded()
    if (!window.L || this.leafletMap) return

    const center = [this.latitudeValue, this.longitudeValue]
    this.leafletMap = window.L.map(this.mapTarget, {
      attributionControl: true,
      dragging: false,
      scrollWheelZoom: false,
      doubleClickZoom: false,
      boxZoom: false,
      keyboard: false,
      tap: false,
      zoomControl: false
    }).setView(center, this.zoomValue)

    window.L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: "© OpenStreetMap",
      maxZoom: 19
    }).addTo(this.leafletMap)

    if (this.radiusValue > 0) {
      window.L.circle(center, {
        radius: this.radiusValue,
        color: "#053c5e",
        fillColor: "#0b6b8f",
        fillOpacity: 0.16,
        weight: 2
      }).addTo(this.leafletMap)
    } else {
      window.L.marker(center).addTo(this.leafletMap)
    }

    window.requestAnimationFrame(() => this.leafletMap.invalidateSize())
  }

  initializeStreetView() {
    if (this.streetView || !this.hasStreetViewTarget) return

    const position = { lat: this.streetLatitudeValue, lng: this.streetLongitudeValue }
    this.streetView = new window.google.maps.StreetViewPanorama(this.streetViewTarget, {
      position,
      pov: { heading: 0, pitch: 0 },
      addressControl: true,
      fullscreenControl: true,
      motionTracking: false
    })
  }

  activatePanel(panel) {
    const showingStreet = panel === "street"
    if (this.hasMapTarget) this.mapTarget.hidden = showingStreet
    if (this.hasStreetViewTarget) this.streetViewTarget.hidden = !showingStreet

    if (this.hasMapButtonTarget) {
      this.mapButtonTarget.classList.toggle("is-active", !showingStreet)
      this.mapButtonTarget.setAttribute("aria-selected", String(!showingStreet))
    }
    if (this.hasStreetViewButtonTarget) {
      this.streetViewButtonTarget.classList.toggle("is-active", showingStreet)
      this.streetViewButtonTarget.setAttribute("aria-selected", String(showingStreet))
    }

    if (showingStreet) this.setSatelliteActive(false)

    if (!showingStreet && this.leafletMap) {
      window.requestAnimationFrame(() => this.leafletMap.invalidateSize())
    }
  }

  setSatelliteActive(active) {
    if (!this.hasSatelliteButtonTarget) return

    this.satelliteButtonTarget.classList.toggle("is-active", active)
    this.satelliteButtonTarget.setAttribute("aria-selected", String(active))
    if (active && this.hasMapButtonTarget) {
      this.mapButtonTarget.classList.remove("is-active")
      this.mapButtonTarget.setAttribute("aria-selected", "false")
    }
  }

  scrollToLocation(event) {
    if (!event?.currentTarget?.closest(".public-habitations-show__media-actions")) return

    document.getElementById("localizacao-imovel")?.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  validCoordinatePair(latitude, longitude) {
    return Number.isFinite(latitude) &&
      Number.isFinite(longitude) &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      !(latitude === 0 && longitude === 0)
  }

  async ensureGoogleLoaded() {
    if (window.google?.maps) return
    await this.waitForPrivacyConsent()
    if (window.__unitymobGoogleMapsPromise) return window.__unitymobGoogleMapsPromise

    window.__unitymobGoogleMapsPromise = new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(this.apiKeyValue)}&v=weekly`
      script.async = true
      script.onload = resolve
      script.onerror = () => {
        window.__unitymobGoogleMapsPromise = null
        reject(new Error("Não foi possível carregar o Google Maps"))
      }
      document.head.appendChild(script)
    })

    return window.__unitymobGoogleMapsPromise
  }

  waitForPrivacyConsent() {
    if (!window.SaluteLgpdConsent || window.SaluteLgpdConsent.accepted()) return Promise.resolve()

    return new Promise((resolve) => {
      window.addEventListener("salute:lgpd-consent-accepted", resolve, { once: true })
    })
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
