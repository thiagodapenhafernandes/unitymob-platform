import { Controller } from "@hotwired/stimulus"

// Banner de dica que some ao fechar e não volta (lembra via localStorage).
export default class extends Controller {
  static values = { key: String, storageKey: String }

  connect() {
    this.element.hidden = this.keyValue && this.stored() === "1"
    this.syncAccessibleState()
  }

  disconnect() {
    window.clearTimeout(this.dismissTimer)
  }

  dismiss(event) {
    event?.preventDefault()
    const focusTarget = this.adjacentFocusTarget(event?.currentTarget)

    try {
      if (this.storageIdentifier) localStorage.setItem(`hint:${this.storageIdentifier}`, "1")
    } catch (_e) {
      /* ignore */
    }

    if (focusTarget) {
      focusTarget.focus()
    } else {
      event?.currentTarget?.blur()
    }
    this.element.classList.add("is-dismissing")
    this.element.setAttribute("aria-hidden", "true")
    this.dispatch("dismissed", { detail: { key: this.keyValue } })

    const finish = () => {
      this.element.hidden = true
      this.element.classList.remove("is-dismissing")
    }

    if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) {
      finish()
    } else {
      this.dismissTimer = window.setTimeout(finish, 180)
    }
  }

  stored() {
    try {
      return localStorage.getItem(`hint:${this.storageIdentifier}`)
    } catch (_e) {
      return null
    }
  }

  syncAccessibleState() {
    if (this.element.hidden) {
      this.element.setAttribute("aria-hidden", "true")
    } else {
      this.element.removeAttribute("aria-hidden")
    }
  }

  adjacentFocusTarget(currentTarget) {
    const selector = [
      "a[href]",
      "button:not([disabled])",
      "input:not([disabled])",
      "select:not([disabled])",
      "textarea:not([disabled])",
      "[tabindex]:not([tabindex='-1'])"
    ].join(",")
    const candidates = Array.from(document.querySelectorAll(selector))
      .filter((element) => !element.closest("[hidden], [aria-hidden='true'], [inert]"))
    const currentIndex = candidates.indexOf(currentTarget)

    return candidates[currentIndex + 1] || candidates[currentIndex - 1] || null
  }

  get storageIdentifier() {
    return this.hasStorageKeyValue ? this.storageKeyValue : this.keyValue
  }
}
