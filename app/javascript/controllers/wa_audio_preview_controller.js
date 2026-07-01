import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["audio", "toggle", "icon", "fill", "current", "duration"]

  connect() {
    this.userInitiatedPlay = false
    this.handlePageShow = this.handlePageShow.bind(this)
    this.handleVisibilityChange = this.handleVisibilityChange.bind(this)
    this.prepareAudio()
    this.disarmEmbeddedPlayers()
    this.pauseAndReset()
    this.syncDuration()
    this.syncProgress()
    this.syncState()
    window.addEventListener("pageshow", this.handlePageShow)
    document.addEventListener("visibilitychange", this.handleVisibilityChange)
  }

  disconnect() {
    window.removeEventListener("pageshow", this.handlePageShow)
    document.removeEventListener("visibilitychange", this.handleVisibilityChange)
    this.pauseAndReset()
  }

  toggle() {
    if (!this.hasAudioTarget) return

    if (this.audioTarget.paused) {
      this.pauseOtherPlayers()
      this.userInitiatedPlay = true
      this.ensureSourceLoaded()
      this.audioTarget.play().catch(() => {})
      return
    }

    this.userInitiatedPlay = false
    this.audioTarget.pause()
  }

  seek(event) {
    if (!this.hasAudioTarget || !this.audioTarget.duration) return

    const rect = event.currentTarget.getBoundingClientRect()
    const x = Math.min(Math.max(event.clientX - rect.left, 0), rect.width)
    const ratio = rect.width > 0 ? x / rect.width : 0
    this.audioTarget.currentTime = this.audioTarget.duration * ratio
    this.syncProgress()
  }

  handlePlay() {
    if (!this.userInitiatedPlay) {
      this.pauseAndReset()
      return
    }

    this.syncState()
  }

  syncDuration() {
    if (!this.hasDurationTarget || !this.hasAudioTarget) return

    const duration = this.audioTarget.duration || 0
    this.durationTarget.textContent = this.formatTime(duration)
  }

  syncProgress() {
    if (!this.hasFillTarget || !this.hasAudioTarget) return

    const duration = this.audioTarget.duration || 0
    const current = this.audioTarget.currentTime || 0
    const percent = duration > 0 ? (current / duration) * 100 : 0

    this.fillTarget.style.width = `${percent}%`
    if (this.hasCurrentTarget) this.currentTarget.textContent = this.formatTime(current)
    if (this.hasDurationTarget && duration > 0) this.durationTarget.textContent = this.formatTime(duration)
  }

  syncState() {
    if (!this.hasToggleTarget || !this.hasIconTarget || !this.hasAudioTarget) return

    const playing = !this.audioTarget.paused && !this.audioTarget.ended
    this.element.classList.toggle("is-playing", playing)
    this.toggleTarget.setAttribute("aria-label", playing ? "Pausar áudio" : "Reproduzir áudio")
    this.iconTarget.className = playing ? "bi bi-pause-fill" : "bi bi-play-fill"
  }

  pauseOtherPlayers() {
    document.querySelectorAll('[data-controller~="wa-audio-preview"] audio').forEach((audio) => {
      if (audio !== this.audioTarget) audio.pause()
    })
  }

  handlePageShow() {
    this.pauseAndReset()
  }

  handleVisibilityChange() {
    if (document.hidden) this.pauseAndReset()
  }

  pauseAndReset() {
    if (!this.hasAudioTarget) return

    this.userInitiatedPlay = false
    this.audioTarget.pause()
    this.audioTarget.currentTime = 0
    this.syncProgress()
    this.syncState()
  }

  prepareAudio() {
    if (!this.hasAudioTarget) return

    const source = this.audioTarget.dataset.src || this.audioTarget.getAttribute("src") || this.audioTarget.currentSrc
    if (source) this.audioTarget.dataset.src = source
    this.audioTarget.autoplay = false
    this.audioTarget.preload = "none"
    this.audioTarget.removeAttribute("src")
    this.audioTarget.load()
  }

  disarmEmbeddedPlayers() {
    this.element.querySelectorAll("audio, video").forEach((media) => {
      media.autoplay = false
      media.pause()

      if (media !== this.audioTarget) {
        try {
          media.currentTime = 0
        } catch (_error) {
          /* noop */
        }
      }
    })
  }

  ensureSourceLoaded() {
    if (!this.hasAudioTarget || this.audioTarget.dataset.loaded === "true") return

    const source = this.audioTarget.dataset.src
    if (!source) return

    this.audioTarget.src = source
    this.audioTarget.dataset.loaded = "true"
    this.audioTarget.load()
  }

  formatTime(value) {
    const seconds = Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0
    const minutes = Math.floor(seconds / 60)
    const rest = seconds % 60

    return `${minutes}:${String(rest).padStart(2, "0")}`
  }
}
