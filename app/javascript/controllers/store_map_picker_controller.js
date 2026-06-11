import { Controller } from "@hotwired/stimulus"

// Mapa Leaflet para selecionar o centro geográfico de uma loja + visualizar
// o raio de geofence. Usa OpenStreetMap como tiles (sem chave de API).
//
// Usage (edit/new):
//   <div data-controller="store-map-picker"
//        data-store-map-picker-latitude-value="-26.9906"
//        data-store-map-picker-longitude-value="-48.6348"
//        data-store-map-picker-radius-value="150">
//     <div data-store-map-picker-target="map" style="height: 400px;"></div>
//     <input data-store-map-picker-target="latitudeInput" ...>
//     <input data-store-map-picker-target="longitudeInput" ...>
//     <input data-store-map-picker-target="radiusInput" ...>
//     <span data-store-map-picker-target="radiusLabel"></span>
//   </div>
//
// Usage (show, readonly): data-store-map-picker-readonly-value="true"
export default class extends Controller {
  static targets = ["map", "latitudeInput", "longitudeInput", "radiusInput", "radiusLabel"]
  static values = {
    latitude: Number,
    longitude: Number,
    radius: { type: Number, default: 150 },
    readonly: { type: Boolean, default: false }
  }

  connect() {
    this.ensureLeafletLoaded().then(() => this.initMap())
    this.boundGeocoded = (e) => this.handleGeocoded(e)
    document.addEventListener("cep-lookup:geocoded", this.boundGeocoded)
  }

  disconnect() {
    document.removeEventListener("cep-lookup:geocoded", this.boundGeocoded)
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  }

  handleGeocoded(event) {
    if (!this.map || this.readonlyValue) return
    const { lat, lng } = event.detail || {}
    if (!lat || !lng) return
    this.map.setView([lat, lng], 18)
    this.placeMarker(lat, lng)
  }

  // --- Setup ---

  async ensureLeafletLoaded() {
    if (window.L) return
    await Promise.all([
      this.loadCSS("https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"),
      this.loadScript("https://unpkg.com/leaflet@1.9.4/dist/leaflet.js")
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
      const s = document.createElement("script")
      s.src = src
      s.onload = resolve
      s.onerror = reject
      document.head.appendChild(s)
    })
  }

  initMap() {
    const defaultLat = this.hasLatitudeValue && this.latitudeValue ? this.latitudeValue : -26.9906  // BC default
    const defaultLng = this.hasLongitudeValue && this.longitudeValue ? this.longitudeValue : -48.6348
    const hasInitialPoint = this.hasLatitudeValue && this.latitudeValue && this.hasLongitudeValue && this.longitudeValue

    this.map = L.map(this.mapTarget).setView([defaultLat, defaultLng], hasInitialPoint ? 17 : 12)

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: '© OpenStreetMap',
      maxZoom: 19
    }).addTo(this.map)

    if (hasInitialPoint) {
      this.placeMarker(defaultLat, defaultLng)
    }

    if (!this.readonlyValue) {
      this.map.on("click", (e) => this.placeMarker(e.latlng.lat, e.latlng.lng))
    }
  }

  // --- Marker e círculo ---

  placeMarker(lat, lng) {
    if (this.marker) this.map.removeLayer(this.marker)
    if (this.circle) this.map.removeLayer(this.circle)

    this.marker = L.marker([lat, lng], {
      draggable: !this.readonlyValue
    }).addTo(this.map)

    if (!this.readonlyValue) {
      this.marker.on("dragend", (e) => {
        const pos = e.target.getLatLng()
        this.writeCoords(pos.lat, pos.lng)
        this.redrawCircle(pos.lat, pos.lng)
      })
    }

    this.redrawCircle(lat, lng)
    this.writeCoords(lat, lng)
  }

  redrawCircle(lat, lng) {
    if (this.circle) this.map.removeLayer(this.circle)
    this.circle = L.circle([lat, lng], {
      radius: this.radiusValue,
      color: "#0d6efd",
      fillColor: "#0d6efd",
      fillOpacity: 0.15,
      weight: 2
    }).addTo(this.map)
  }

  writeCoords(lat, lng) {
    if (this.hasLatitudeInputTarget) this.latitudeInputTarget.value = lat.toFixed(7)
    if (this.hasLongitudeInputTarget) this.longitudeInputTarget.value = lng.toFixed(7)
  }

  // --- Actions ---

  updateRadius() {
    const v = parseInt(this.radiusInputTarget.value, 10) || 150
    this.radiusValue = v
    if (this.hasRadiusLabelTarget) this.radiusLabelTarget.textContent = `${v}m`
    if (this.marker) {
      const pos = this.marker.getLatLng()
      this.redrawCircle(pos.lat, pos.lng)
    }
  }

  updateFromInputs() {
    const lat = parseFloat(this.latitudeInputTarget.value)
    const lng = parseFloat(this.longitudeInputTarget.value)
    if (!isNaN(lat) && !isNaN(lng)) {
      this.map.setView([lat, lng], 17)
      this.placeMarker(lat, lng)
    }
  }
}
