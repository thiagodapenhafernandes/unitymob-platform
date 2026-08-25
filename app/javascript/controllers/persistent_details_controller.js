import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    key: String
  }

  connect() {
    if (!this.keyValue) return

    const stored = this.readStoredState()
    if (stored === "open") this.element.open = true
    if (stored === "closed") this.element.open = false
  }

  save() {
    if (!this.keyValue) return

    try {
      window.localStorage.setItem(this.keyValue, this.element.open ? "open" : "closed")
    } catch (_) {
      // Preferencia visual: se o navegador bloquear storage, o filtro segue funcional.
    }
  }

  readStoredState() {
    try {
      return window.localStorage.getItem(this.keyValue)
    } catch (_) {
      return null
    }
  }
}
