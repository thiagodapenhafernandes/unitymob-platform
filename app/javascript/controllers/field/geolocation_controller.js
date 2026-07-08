import { Controller } from "@hotwired/stimulus"

// Gerencia o estado de geolocalização no PWA /field.
// Pede permissão a partir de um toque do usuário, usa watchPosition em foreground,
// chama /field/stores/discover
// para saber a loja mais próxima e se corretor está no raio.
//
// Atualiza o banner de status (cor + ícone + texto) e o botão de check-in.
export default class extends Controller {
  static targets = ["statusBox", "statusIcon", "statusTitle", "statusDescription", "locationButton", "checkinButton"]
  static values = { discoverUrl: String }

  connect() {
    this.closestStore = null
    this.currentPosition = null
    this.watchId = null
    this.renderStatus(
      "neutral",
      "bi-geo-alt",
      "Ative sua localização",
      "Toque no botão para permitir o GPS e encontrar a loja mais próxima."
    )
    this.showLocationButton("Ativar localização")
    this.disableCheckin()
    this.startIfPermissionAlreadyGranted()
  }

  disconnect() {
    if (this.watchId) navigator.geolocation.clearWatch(this.watchId)
  }

  async startIfPermissionAlreadyGranted() {
    if (!navigator.permissions?.query) return

    try {
      const permission = await navigator.permissions.query({ name: "geolocation" })
      if (permission.state === "granted") this.requestGeolocation()
    } catch (_) {
      // Safari/iOS pode não suportar a Permissions API para geolocation.
    }
  }

  requestGeolocation(event) {
    if (event) event.preventDefault()

    if (!("geolocation" in navigator)) {
      this.renderStatus("error", "bi-x-octagon-fill", "GPS não disponível", "Seu navegador não suporta geolocalização.")
      this.showLocationButton("Tentar novamente")
      return
    }

    if (!window.isSecureContext) {
      this.renderStatus(
        "error",
        "bi-lock-fill",
        "Localização bloqueada",
        "O GPS só funciona em conexão segura. Acesse o PWA por HTTPS."
      )
      this.showLocationButton("Tentar novamente")
      return
    }

    this.renderStatus("neutral", "bi-geo-alt", "Procurando sua localização…", "Permita o acesso ao GPS para continuar.")
    this.setLocationButtonLoading()
    this.disableCheckin()

    navigator.geolocation.getCurrentPosition(
      (pos) => {
        this.onPosition(pos)
        this.startWatch()
      },
      (err) => this.onError(err),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
    )
  }

  startWatch() {
    if (this.watchId) navigator.geolocation.clearWatch(this.watchId)
    this.watchId = navigator.geolocation.watchPosition(
      (pos) => this.onPosition(pos),
      (err) => this.onError(err),
      { enableHighAccuracy: true, timeout: 20000, maximumAge: 5000 }
    )
  }

  async onPosition(pos) {
    this.currentPosition = pos
    const { latitude, longitude, accuracy } = pos.coords

    // Publica para o field--checkin controller pegar na hora do clique.
    window.__lastFieldPosition = { latitude, longitude, accuracy, timestamp: pos.timestamp }

    if (accuracy > 50) {
      this.renderStatus("warn", "bi-exclamation-triangle-fill",
        "Sinal de GPS fraco",
        `Precisão: ${Math.round(accuracy)}m. Vá até uma janela ou saia para a rua.`)
      this.disableCheckin()
      this.showLocationButton("Atualizar localização")
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
          "Não há lojas cadastradas para check-in na sua região.")
        this.disableCheckin()
        this.showLocationButton("Atualizar localização")
        return
      }

      if (nearest.inside_radius) {
        this.renderStatus("ok", "bi-check-circle-fill",
          "No raio de check-in",
          `${nearest.name} está a ${Math.round(nearest.distance_meters)}m de você.`)
        this.enableCheckin(nearest)
      } else {
        this.renderStatus("warn", "bi-exclamation-circle-fill",
          "Check-in indisponível",
          `${nearest.name} está a ${Math.round(nearest.distance_meters)}m de você. O raio permitido é ${nearest.geofence_radius_meters}m.`)
        this.disableCheckin()
        this.showLocationButton("Atualizar localização")
      }
    } catch (e) {
      this.renderStatus("error", "bi-wifi-off", "Falha ao localizar loja", "Não foi possível consultar as lojas agora. Tente novamente.")
      this.disableCheckin()
      this.showLocationButton("Tentar novamente")
    }
  }

  onError(err) {
    const codes = {
      1: ["Localização bloqueada", "Permita localização para este site/app nas configurações do navegador e tente novamente."],
      2: ["Sinal indisponível", "Tente sair para um ambiente aberto."],
      3: ["Tempo esgotado", "O GPS demorou para responder. Tente de novo."]
    }
    const [title, desc] = codes[err.code] || ["Erro de GPS", err.message]
    this.renderStatus("error", "bi-geo-alt-fill", title, desc)
    this.disableCheckin()
    this.showLocationButton("Tentar novamente")
  }

  enableCheckin(store) {
    if (this.hasLocationButtonTarget) this.locationButtonTarget.hidden = true
    if (this.hasCheckinButtonTarget) {
      this.checkinButtonTarget.hidden = false
      this.checkinButtonTarget.disabled = false
      this.checkinButtonTarget.dataset.storeSlug = store.slug
      this.setButtonContent(this.checkinButtonTarget, "bi-box-arrow-in-right", `Fazer check-in em ${store.name}`)
    }
  }

  disableCheckin() {
    if (this.hasCheckinButtonTarget) {
      this.checkinButtonTarget.disabled = true
      this.checkinButtonTarget.hidden = true
      delete this.checkinButtonTarget.dataset.storeSlug
    }
  }

  showLocationButton(label) {
    if (!this.hasLocationButtonTarget) return

    this.locationButtonTarget.hidden = false
    this.locationButtonTarget.disabled = false
    this.setButtonContent(this.locationButtonTarget, "bi-crosshair", label)
  }

  setLocationButtonLoading() {
    if (!this.hasLocationButtonTarget) return

    this.locationButtonTarget.hidden = false
    this.locationButtonTarget.disabled = true
    this.locationButtonTarget.replaceChildren()
    const spinner = document.createElement("span")
    spinner.className = "spinner-border spinner-border-sm me-2"
    this.locationButtonTarget.append(spinner, document.createTextNode("Localizando…"))
  }

  setButtonContent(button, iconClass, label) {
    button.replaceChildren()
    const icon = document.createElement("i")
    icon.className = `bi ${iconClass} me-2`
    button.append(icon, document.createTextNode(label))
  }

  renderStatus(level, icon, title, description) {
    const statusBox = this.hasStatusBoxTarget ? this.statusBoxTarget : this.element
    statusBox.classList.remove("status-ok", "status-warn", "status-error", "status-info", "status-neutral")
    statusBox.classList.add(`status-${level}`)

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
