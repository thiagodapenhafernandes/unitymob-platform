import { Controller } from "@hotwired/stimulus"

// Modal de travas de campos por perfil (card #1 / Opção B).
// Masters "travar/liberar tudo" + contador de travados.
export default class extends Controller {
  static targets = ["checkbox", "lockedCount"]

  lockAll() {
    this.setAll(true)
  }

  unlockAll() {
    this.setAll(false)
  }

  setAll(checked) {
    this.checkboxTargets.forEach((box) => { box.checked = checked })
    this.recount()
  }

  recount() {
    if (!this.hasLockedCountTarget) return
    const locked = this.checkboxTargets.filter((box) => box.checked).length
    this.lockedCountTarget.textContent = String(locked)
  }
}
