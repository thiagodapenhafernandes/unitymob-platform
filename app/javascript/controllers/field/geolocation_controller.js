import { Controller } from "@hotwired/stimulus"

// Gerencia o estado de geolocalização no PWA /field.
// Pede permissão, usa watchPosition em foreground, chama /field/stores/discover
// para saber a loja mais próxima e se corretor está no raio.
//
// Atualiza o banner de status (cor + ícone + texto) e o botão de check-in.
// Fase 3 adiciona o handler de click no botão.
export default class extends Controller {
  static targets = ["statusIcon", "statusTitle", "statusDescription", "checkinButton"]
  static values = { discoverUrl: String }

  connect() {
    this.closestStore = null
    this.currentPosition = null
    this.requestGeolocation()
  }

  disconnect() {
    if (this.watchId) navigator.geolocation.clearWatch(this.watchId)
  }

  requestGeolocation() {
    if (!("geolocation" in navigator)) {
      this.renderStatus("error", "bi-x-octagon-fill", "GPS não disponível", "Seu navegador não suporta geolocalização.")
      return
    }

    this.renderStatus("neutral", "bi-geo-alt", "Procurando sua localização…", "Permita o acesso ao GPS para continuar.")

    this.watchId = navigator.geolocation.watchPosition(
      (pos) => this.onPosition(pos),
      (err) => this.onError(err),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
    )
  }

  async onPosition(pos) {
    this.currentPosition = pos
    const { latitude, longitude, accuracy } = pos.coords

    // Publica para o field-checkin controller pegar na hora do clique
    window.__lastFieldPosition = { latitude, longitude, accuracy, timestamp: pos.timestamp }

    if (accuracy > 50) {
      this.renderStatus("warn", "bi-exclamation-triangle-fill",
        "Sinal de GPS fraco",
        `Precisão: ${Math.round(accuracy)}m. Vá até uma janela ou saia para a rua.`)
      this.disableCheckin()
      return
    }

    await this.discoverStore(latitude, longitude)
  }

  async discoverStore(lat, lng) {
    try {
      const resp = await fetch(`${this.discoverUrlValue}?lat=${lat}&lng=${lng}`, {
        headers: { "Accept": "application/json" },
        credentials: "same-origin"
      })
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
      const json = await resp.json()
      const nearest = json.stores?.[0]
      this.closestStore = nearest

      if (!nearest) {
        this.renderStatus("warn", "bi-geo-alt-fill",
          "Nenhuma loja próxima",
          "Não há lojas cadastradas na sua região.")
        this.disableCheckin()
        return
      }

      if (nearest.inside_radius) {
        this.renderStatus("ok", "bi-check-circle-fill",
          "No raio de check-in",
          `${nearest.name} está a ${Math.round(nearest.distance_meters)}m de você.`)
        this.enableCheckin(nearest)
      } else {
        this.renderStatus("warn", "bi-exclamation-circle-fill",
          "Fora do raio",
          `${nearest.name} está a ${Math.round(nearest.distance_meters)}m (raio: ${nearest.geofence_radius_meters}m).`)
        this.disableCheckin()
      }
    } catch (e) {
      this.renderStatus("error", "bi-wifi-off", "Falha ao localizar loja", e.message)
      this.disableCheckin()
    }
  }

  onError(err) {
    const codes = {
      1: ["Permissão negada", "Habilite a localização nas configurações do navegador."],
      2: ["Sinal indisponível", "Tente sair para um ambiente aberto."],
      3: ["Tempo esgotado", "O GPS demorou para responder. Tente de novo."]
    }
    const [title, desc] = codes[err.code] || ["Erro de GPS", err.message]
    this.renderStatus("error", "bi-geo-alt-fill", title, desc)
    this.disableCheckin()
  }

  enableCheckin(store) {
    if (this.hasCheckinButtonTarget) {
      this.checkinButtonTarget.disabled = false
      this.checkinButtonTarget.dataset.storeSlug = store.slug
    }
  }

  disableCheckin() {
    if (this.hasCheckinButtonTarget) {
      this.checkinButtonTarget.disabled = true
    }
  }

  renderStatus(level, icon, title, description) {
    this.element.classList.remove("status-ok", "status-warn", "status-error", "status-info", "status-neutral")
    this.element.classList.add(`status-${level}`)

    if (this.hasStatusIconTarget) {
      this.statusIconTarget.innerHTML = `<i class="bi ${icon}" style="font-size: 2.5rem;"></i>`
    }
    if (this.hasStatusTitleTarget) {
      this.statusTitleTarget.textContent = title
    }
    if (this.hasStatusDescriptionTarget) {
      this.statusDescriptionTarget.textContent = description
    }
  }
}
