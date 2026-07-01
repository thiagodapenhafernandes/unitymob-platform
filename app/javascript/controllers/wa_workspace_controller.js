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
    this.syncButtons(false)
  }

  enterFullscreen() {
    const shell = this.hasShellTarget ? this.shellTarget : this.element
    if (!shell?.requestFullscreen || document.fullscreenElement) return

    shell.requestFullscreen().catch(() => {})
  }

  exitFullscreen() {
    if (!document.fullscreenElement || !document.exitFullscreen) return

    document.exitFullscreen().catch(() => {})
  }

  handleFullscreenChange() {
    this.syncButtons()
  }

  syncButtons(active = Boolean(document.fullscreenElement)) {
    if (this.hasEnterTarget) {
      this.enterTarget.hidden = active
      this.enterTarget.setAttribute("aria-hidden", active ? "true" : "false")
      this.enterTarget.setAttribute("aria-pressed", active ? "true" : "false")
    }
    if (this.hasExitTarget) {
      this.exitTarget.hidden = !active
      this.exitTarget.setAttribute("aria-hidden", active ? "false" : "true")
      this.exitTarget.setAttribute("aria-pressed", active ? "true" : "false")
    }
    if (this.hasShellTarget) this.shellTarget.classList.toggle("is-browser-fullscreen", active)
  }
}
