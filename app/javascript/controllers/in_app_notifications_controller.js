import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Sino + toast em tempo real. O servidor envia { id, title, body, url, unread_count }.
export default class extends Controller {
  static targets = ["badge", "list", "empty", "toasts", "soundToggle"]
  static values = { unread: Number, readUrl: String, readAllUrl: String }

  connect() {
    this.unlockAudio = () => this.audio()?.resume?.()
    document.addEventListener("pointerdown", this.unlockAudio, { once: true })
    document.addEventListener("keydown", this.unlockAudio, { once: true })
    this.renderSoundToggle()
    // A navbar tem backdrop-filter, que vira o "bloco de contenção" de position: fixed e esconde o toast
    // fora da tela. O contêiner dos toasts vive direto no body.
    this.toastHost = this.hasToastsTarget ? this.toastsTarget : null
    if (this.toastHost) document.body.append(this.toastHost)
    this.subscription = consumer.subscriptions.create(
      { channel: "InAppNotificationsChannel" },
      { received: (data) => this.received(data) }
    )
  }

  disconnect() {
    consumer.subscriptions.remove(this.subscription)
    this.toastHost?.remove()
    document.removeEventListener("pointerdown", this.unlockAudio)
    document.removeEventListener("keydown", this.unlockAudio)
  }

  received(data) {
    if (data.event === "whatsapp_message") return this.messageArrived(data)
    if (data.event === "read") return this.markRead(data)
    if (data.event === "attendance_changed") return window.dispatchEvent(new CustomEvent("wa:attendance-changed", { detail: data }))

    this.playSound()
    this.renderBadge(data.unread_count)
    this.prepend(data)
    this.toast(data)
  }

  // Notificações lidas em outro lugar (ex.: conversa aberta): tira o destaque e atualiza a contagem.
  markRead({ ids, unread_count }) {
    ids.forEach((id) => {
      document.querySelectorAll(`[data-notification-id='${id}']`).forEach((el) => {
        if (el.classList.contains("ax-notifications__toast")) el.remove()
        else el.classList.remove("is-unread")
      })
    })
    this.renderBadge(unread_count)
  }

  // Mensagem do cliente: só toca se o atendente não estiver com essa conversa aberta e em foco.
  messageArrived(data) {
    const viewing = document.hasFocus() && window.location.pathname.endsWith(`/atendimento/whatsapp/${data.conversation_id}`)
    if (!viewing) this.playSound()
  }

  // Som gerado no navegador (sem arquivo de áudio). Navegadores só liberam áudio após o primeiro clique/tecla na página.
  audio() {
    const Context = window.AudioContext || window.webkitAudioContext
    if (!Context) return null
    window.axNotificationAudio ||= new Context()
    return window.axNotificationAudio
  }

  soundEnabled() {
    try { return localStorage.getItem("axNotificationSound") !== "off" } catch (_error) { return true }
  }

  // Som "Cristal": sino de vidro em duas notas (mi 6 e si 6), com parciais inarmônicos e eco curto.
  playSound() {
    const context = this.soundEnabled() ? this.audio() : null
    if (!context || context.state !== "running") return

    const out = this.soundOutput(context)
    const now = context.currentTime
    this.soundBell(context, out, 1318.5, now, 1.1, 0.22)
    this.soundBell(context, out, 1975.5, now + 0.16, 1.4, 0.24)
  }

  // Compressor (evita estourar) + eco curto que dá corpo ao som.
  soundOutput(context) {
    const master = context.createGain()
    master.gain.value = Math.pow(0.7, 1.6)
    const compressor = context.createDynamicsCompressor()
    compressor.threshold.value = -14
    compressor.ratio.value = 4
    compressor.attack.value = 0.003
    compressor.release.value = 0.2
    const delay = context.createDelay(0.5)
    delay.delayTime.value = 0.11
    const feedback = context.createGain()
    feedback.gain.value = 0.28
    const tone = context.createBiquadFilter()
    tone.type = "lowpass"
    tone.frequency.value = 3200
    const wet = context.createGain()
    wet.gain.value = 0.22
    master.connect(compressor)
    compressor.connect(context.destination)
    master.connect(delay)
    delay.connect(tone)
    tone.connect(feedback)
    feedback.connect(delay)
    tone.connect(wet)
    wet.connect(compressor)
    return master
  }

  // Parciais do sino: os agudos morrem primeiro.
  soundBell(context, out, frequency, at, duration, gain) {
    ;[[1, 1, 1], [2.76, 0.5, 0.6], [5.4, 0.28, 0.35], [8.93, 0.14, 0.2]].forEach(([ratio, level, decay]) => {
      const oscillator = context.createOscillator()
      const envelope = context.createGain()
      const length = duration * decay
      oscillator.frequency.setValueAtTime(frequency * ratio, at)
      envelope.gain.setValueAtTime(0.0001, at)
      envelope.gain.exponentialRampToValueAtTime(gain * level, at + 0.006)
      envelope.gain.exponentialRampToValueAtTime(0.0001, at + length)
      oscillator.connect(envelope).connect(out)
      oscillator.start(at)
      oscillator.stop(at + length + 0.05)
    })
  }

  toggleSound() {
    try { localStorage.setItem("axNotificationSound", this.soundEnabled() ? "off" : "on") } catch (_error) { /* sem storage: mantém ligado */ }
    this.renderSoundToggle()
    this.playSound()
  }

  renderSoundToggle() {
    if (!this.hasSoundToggleTarget) return
    const on = this.soundEnabled()
    this.soundToggleTarget.setAttribute("aria-pressed", String(on))
    this.soundToggleTarget.title = on ? "Som ligado (clique para silenciar)" : "Som desligado (clique para ligar)"
    this.soundToggleTarget.querySelector("i").className = on ? "bi bi-volume-up" : "bi bi-volume-mute"
  }

  renderBadge(count) {
    if (!this.hasBadgeTarget) return
    this.badgeTarget.hidden = !count
    this.badgeTarget.textContent = count > 99 ? "99+" : count
  }

  prepend(data) {
    if (!this.hasListTarget) return
    const item = this.buildLink(data, "ax-menu__item ax-notifications__item is-unread")
    item.dataset.notificationId = data.id
    item.dataset.action = "click->in-app-notifications#open"
    this.listTarget.prepend(item)
    if (this.hasEmptyTarget) this.emptyTarget.hidden = true
  }

  toast(data) {
    const toast = this.buildLink(data, "ax-notifications__toast")
    toast.dataset.notificationId = data.id
    toast.dataset.action = "click->in-app-notifications#open"
    const close = document.createElement("button")
    close.type = "button"
    close.className = "ax-notifications__toast-close"
    close.setAttribute("aria-label", "Fechar")
    close.textContent = "×"
    close.addEventListener("click", (event) => {
      event.preventDefault()
      event.stopPropagation()
      toast.remove()
    })
    toast.append(close)
    this.toastHost?.append(toast)
    setTimeout(() => toast.remove(), 15000)
  }

  buildLink(data, className) {
    const link = document.createElement("a")
    link.href = data.url || "#"
    link.className = className
    const title = document.createElement("span")
    title.className = "ax-notifications__item-title"
    title.textContent = data.title
    link.append(title)
    if (data.body) {
      const body = document.createElement("span")
      body.className = "ax-notifications__item-body"
      body.textContent = data.body
      link.append(body)
    }
    return link
  }

  open(event) {
    const link = event.currentTarget
    link.classList.remove("is-unread")
    this.post(this.readUrlValue.replace(/0$/, link.dataset.notificationId))
    if (link.classList.contains("ax-notifications__toast")) link.remove()
  }

  readAll() {
    this.post(this.readAllUrlValue)
    this.element.querySelectorAll(".is-unread").forEach((el) => el.classList.remove("is-unread"))
    this.renderBadge(0)
  }

  post(url) {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    return fetch(url, { method: "POST", keepalive: true, headers: { "X-CSRF-Token": token, Accept: "application/json" }, credentials: "same-origin" })
      .then((response) => response.ok ? response.json() : null)
      .then((data) => { if (data) this.renderBadge(data.unread_count) })
      .catch(() => {})
  }
}
