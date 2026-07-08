import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["shell", "enter", "exit"]

  connect() {
    this.handleFullscreenChange = this.handleFullscreenChange.bind(this)
    document.addEventListener("fullscreenchange", this.handleFullscreenChange)
    this.syncButtons()
  }

  disconnect() {
    document.removeEventListener("fullscreenchange", this.handleFullscreenChange)
    this.exitFakeFullscreen()
    this.syncButtons(false)
  }

  enterFullscreen() {
    if (document.fullscreenElement || this.fakeFullscreen) return

    const shell = this.hasShellTarget ? this.shellTarget : this.element
    if (shell?.requestFullscreen) {
      shell.requestFullscreen().catch(() => this.enterFakeFullscreen())
    } else {
      // iOS/PWA nao tem Fullscreen API: simula com position fixed
      this.enterFakeFullscreen()
    }
  }

  exitFullscreen() {
    if (document.fullscreenElement && document.exitFullscreen) {
      document.exitFullscreen().catch(() => {})
      return
    }

    this.exitFakeFullscreen()
  }

  enterFakeFullscreen() {
    const shell = this.hasShellTarget ? this.shellTarget : this.element
    this.fakeFullscreen = true
    shell.classList.add("is-fake-fullscreen")
    document.documentElement.classList.add("wa-fullscreen-lock")
    this.syncButtons(true)
  }

  exitFakeFullscreen() {
    if (!this.fakeFullscreen) return

    this.fakeFullscreen = false
    const shell = this.hasShellTarget ? this.shellTarget : this.element
    shell.classList.remove("is-fake-fullscreen")
    document.documentElement.classList.remove("wa-fullscreen-lock")
    this.syncButtons(false)
  }

  handleFullscreenChange() {
    this.syncButtons()
  }

  syncButtons(active = Boolean(document.fullscreenElement) || this.fakeFullscreen === true) {
    this.enterTargets.forEach((button) => {
      button.hidden = active
      button.setAttribute("aria-hidden", active ? "true" : "false")
      button.setAttribute("aria-pressed", active ? "true" : "false")
    })
    this.exitTargets.forEach((button) => {
      button.hidden = !active
      button.setAttribute("aria-hidden", active ? "false" : "true")
      button.setAttribute("aria-pressed", active ? "true" : "false")
    })
    if (this.hasShellTarget) this.shellTarget.classList.toggle("is-browser-fullscreen", active)
  }
}
