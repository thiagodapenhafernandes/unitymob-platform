import { Controller } from "@hotwired/stimulus"

// Envia pings de localização a cada PING_INTERVAL_MS enquanto o PWA está
// visível. Pausa quando a aba fica escondida e retoma com um ping imediato
// ao voltar. Usa window.__lastFieldPosition do geolocation_controller.
export default class extends Controller {
  static values = {
    pingUrl: String,
    csrf: String,
    intervalMs: { type: Number, default: 90_000 }
  }

  connect() {
    this.boundVisibilityChange = this.handleVisibilityChange.bind(this)
    document.addEventListener("visibilitychange", this.boundVisibilityChange)

    if (document.visibilityState === "visible") {
      this.startTicker()
    }
  }

  disconnect() {
    this.stopTicker()
    document.removeEventListener("visibilitychange", this.boundVisibilityChange)
  }

  handleVisibilityChange() {
    if (document.visibilityState === "visible") {
      this.sendPing() // ping imediato ao voltar
      this.startTicker()
    } else {
      this.stopTicker()
    }
  }

  startTicker() {
    if (this.tickerId) return
    this.tickerId = setInterval(() => this.sendPing(), this.intervalMsValue)
  }

  stopTicker() {
    if (this.tickerId) {
      clearInterval(this.tickerId)
      this.tickerId = null
    }
  }

  async sendPing() {
    const pos = window.__lastFieldPosition
    if (!pos) return

    const battery = await this.getBatteryLevel()

    // A plataforma web (navigator.geolocation) NÃO expõe a flag nativa de mock
    // location do Android — só apps nativos conseguem lê-la. Enviar false aqui
    // afirmaria um sinal que não temos; por isso OMITIMOS is_mock_location e
    // deixamos o servidor tratar a ausência como DESCONHECIDO (não "limpo").
    // Detecção real de mock no web é limitada por design da Web Platform.
    const payload = {
      lat: pos.latitude,
      lng: pos.longitude,
      accuracy: pos.accuracy,
      battery_level: battery,
      fingerprint_hash: window.__fieldFingerprint || null
    }

    try {
      const res = await fetch(this.pingUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue,
          "Accept": "application/json"
        },
        body: JSON.stringify(payload),
        keepalive: true
      })
      if (res.status === 202) {
        // Queued pelo service worker — está offline
        return
      }
      const data = await res.json().catch(() => ({}))
      if (data.auto_checked_out) {
        // Server fez auto-checkout — recarrega para atualizar UI
        window.location.reload()
      }
    } catch (_) {
      // SW vai reenfileirar; falha silenciosa aqui é ok
    }
  }

  async getBatteryLevel() {
    if (!navigator.getBattery) return null
    try {
      const b = await navigator.getBattery()
      return Math.round(b.level * 100)
    } catch (_) {
      return null
    }
  }
}
