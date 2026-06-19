import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.openFromTrigger = this.openFromTrigger.bind(this)
    document.addEventListener("click", this.openFromTrigger, true)
  }

  disconnect() {
    document.removeEventListener("click", this.openFromTrigger, true)
  }

  openFromTrigger(event) {
    const trigger = event.target.closest("[data-media-modal-url]")
    if (!trigger || !this.matchesModal(trigger)) return

    event.preventDefault()
    event.stopPropagation()
    event.stopImmediatePropagation()
    this.closeSourceDropdown(trigger)
    this.open(trigger.dataset.mediaModalUrl)
  }

  async open(url) {
    if (!url) return

    this.showLoading()
    this.openModal()

    try {
      const response = await fetch(url, {
        headers: {
          "Accept": "text/html",
          "X-Requested-With": "XMLHttpRequest"
        }
      })

      if (!response.ok) throw new Error("Não foi possível carregar o organizador de mídia.")

      this.panelTarget.innerHTML = await response.text()
      this.openModal()
    } catch (error) {
      this.showError(error.message)
      this.openModal()
    }
  }

  matchesModal(trigger) {
    const modalId = trigger.dataset.mediaModalId || "adminHabitationMediaModal"
    return modalId === this.element.id || modalId === `#${this.element.id}`
  }

  showLoading() {
    this.panelTarget.innerHTML = `
      <div class="ax-media-modal__state">
        <span class="ax-media-modal__spinner" aria-hidden="true"></span>
        <span>Carregando mídia...</span>
      </div>
    `
  }

  openModal() {
    const modalController = this.application.getControllerForElementAndIdentifier(this.element, "ax-modal")

    if (modalController?.open) {
      modalController.open()
      return
    }

    this.element.hidden = false
    this.element.setAttribute("aria-hidden", "false")
    document.documentElement.style.overflow = "hidden"
  }

  closeSourceDropdown(trigger) {
    const dropdown = trigger.closest('[data-controller~="ax-dropdown"]')
    if (!dropdown) return

    const dropdownController = this.application.getControllerForElementAndIdentifier(dropdown, "ax-dropdown")
    if (dropdownController?.close) dropdownController.close()
  }

  showError(message) {
    this.panelTarget.innerHTML = `
      <div class="ax-media-modal__state ax-media-modal__state--error">
        <i class="bi bi-exclamation-triangle"></i>
        <strong>${this.escapeHtml(message || "Não foi possível carregar o organizador de mídia.")}</strong>
        <button type="button" class="ax-btn ax-btn--sm" data-action="ax-modal#close">Fechar</button>
      </div>
    `
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;")
  }
}
