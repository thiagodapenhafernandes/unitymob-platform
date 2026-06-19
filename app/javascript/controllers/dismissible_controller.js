import { Controller } from "@hotwired/stimulus"

// Banner de dica que some ao fechar e não volta (lembra via localStorage).
export default class extends Controller {
  static values = { key: String }

  connect() {
    if (this.keyValue && this.stored() === "1") {
      this.element.style.display = "none"
    }
  }

  dismiss() {
    try {
      if (this.keyValue) localStorage.setItem(`hint:${this.keyValue}`, "1")
    } catch (_e) {
      /* ignore */
    }
    this.element.style.display = "none"
  }

  stored() {
    try {
      return localStorage.getItem(`hint:${this.keyValue}`)
    } catch (_e) {
      return null
    }
  }
}
