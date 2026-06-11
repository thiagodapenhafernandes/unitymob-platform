import { Controller } from "@hotwired/stimulus"

// Ação de check-in e check-out via fetch JSON.
// Pega lat/lng atuais do field-geolocation controller (na Fase 3 via window.__lastPosition).
// Valores:
//   - mode: "new" (form de check-in) ou "active" (botão de check-out)
//   - createUrl / checkOutUrl
//   - csrf: token do Rails
export default class extends Controller {
  static targets = ["actionButton", "duration"]
  static values = {
    mode: String,
    createUrl: String,
    checkOutUrl: String,
    checkInId: Number,
    csrf: String
  }

  connect() {
    if (this.modeValue === "active" && this.hasDurationTarget) {
      this.startDurationTicker()
    }
  }

  disconnect() {
    if (this.tickerId) clearInterval(this.tickerId)
  }

  // --- Actions ---

  async checkIn(event) {
    event.preventDefault()
    const position = window.__lastFieldPosition
    if (!position) {
      this.flashError("Aguarde o GPS localizar você.")
      return
    }

    this.disableButton("Enviando…")

    const payload = {
      lat: position.latitude,
      lng: position.longitude,
      accuracy: position.accuracy,
      fingerprint_hash: window.__fieldFingerprint || null,
      device_info: this.collectDeviceInfo()
    }

    try {
      const res = await fetch(this.createUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue,
          "Accept": "application/json"
        },
        body: JSON.stringify(payload)
      })
      const data = await res.json()
      if (res.ok && data.ok) {
        window.location.reload()
      } else {
        this.flashError(data.message || "Falha ao fazer check-in.")
        this.enableButton()
      }
    } catch (e) {
      this.flashError("Erro de rede ao enviar check-in.")
      this.enableButton()
    }
  }

  async checkOut(event) {
    event.preventDefault()
    if (!confirm("Confirmar check-out?")) return

    this.disableButton("Enviando…")

    const position = window.__lastFieldPosition || {}
    const payload = {
      lat: position.latitude,
      lng: position.longitude,
      accuracy: position.accuracy
    }

    try {
      const res = await fetch(this.checkOutUrlValue, {
        method: "PATCH",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue,
          "Accept": "application/json"
        },
        body: JSON.stringify(payload)
      })
      const data = await res.json()
      if (res.ok && data.ok) {
        window.location.reload()
      } else {
        this.flashError(data.message || "Falha ao fazer check-out.")
        this.enableButton()
      }
    } catch (e) {
      this.flashError("Erro de rede ao enviar check-out.")
      this.enableButton()
    }
  }

  // --- Helpers ---

  collectDeviceInfo() {
    return {
      user_agent: navigator.userAgent,
      platform: navigator.platform,
      language: navigator.language,
      online: navigator.onLine,
      battery: window.__lastFieldBattery || null
    }
  }

  disableButton(label) {
    if (this.hasActionButtonTarget) {
      this.actionButtonTarget.dataset.originalText = this.actionButtonTarget.innerHTML
      this.actionButtonTarget.innerHTML = `<span class="spinner-border spinner-border-sm me-2"></span>${label}`
      this.actionButtonTarget.disabled = true
    }
  }

  enableButton() {
    if (this.hasActionButtonTarget && this.actionButtonTarget.dataset.originalText) {
      this.actionButtonTarget.innerHTML = this.actionButtonTarget.dataset.originalText
      this.actionButtonTarget.disabled = false
    }
  }

  flashError(msg) {
    alert(msg) // MVP: alert simples; podemos trocar por toast depois
  }

  startDurationTicker() {
    this.tickerId = setInterval(() => {
      // Nada por enquanto — o backend pode dar push via turbo streams depois
    }, 30000)
  }
}
