import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    formId: String,
    message: { type: String, default: "Confirmar esta ação?" },
    confirmLabel: { type: String, default: "Confirmar" },
    cancelLabel: { type: String, default: "Cancelar" }
  }

  disconnect() {
    this.closeConfirmation()
  }

  request(event) {
    event.preventDefault()
    event.stopPropagation()

    this.previouslyFocusedElement = event.currentTarget || document.activeElement
    this.closeOpenConfirmations()
    this.showConfirmation()
  }

  confirm(event) {
    event.preventDefault()
    event.stopPropagation()

    const form = document.getElementById(this.formIdValue)
    if (!form) {
      this.closeConfirmation({ restoreFocus: true })
      return
    }

    const confirmButton = event.currentTarget
    confirmButton.disabled = true
    confirmButton.setAttribute("aria-busy", "true")

    if (typeof form.requestSubmit === "function") {
      form.requestSubmit()
    } else {
      form.submit()
    }
  }

  cancel(event) {
    event.preventDefault()
    event.stopPropagation()
    this.closeConfirmation({ restoreFocus: true })
  }

  showConfirmation() {
    const item = this.element.closest(".ax-file-list__item") || this.element
    item.classList.add("is-confirming")

    const panel = document.createElement("div")
    panel.className = "ax-confirm-submit__panel"
    panel.dataset.axConfirmSubmitPanel = "true"
    panel.setAttribute("role", "alertdialog")
    panel.setAttribute("aria-modal", "false")
    panel.setAttribute("aria-label", this.messageValue)
    panel.innerHTML = `
      <span class="ax-confirm-submit__message">${this.escapeHtml(this.messageValue)}</span>
      <span class="ax-confirm-submit__actions">
        <button type="button" class="ax-confirm-submit__btn" data-ax-confirm-submit-cancel>${this.escapeHtml(this.cancelLabelValue)}</button>
        <button type="button" class="ax-confirm-submit__btn ax-confirm-submit__btn--danger" data-ax-confirm-submit-confirm>${this.escapeHtml(this.confirmLabelValue)}</button>
      </span>
    `

    const cancelButton = panel.querySelector("[data-ax-confirm-submit-cancel]")
    cancelButton.addEventListener("click", this.cancel.bind(this))
    panel.querySelector("[data-ax-confirm-submit-confirm]").addEventListener("click", this.confirm.bind(this))
    panel.addEventListener("keydown", (event) => {
      if (event.key === "Escape") this.cancel(event)
    })
    item.appendChild(panel)
    cancelButton.focus()
  }

  closeConfirmation(options = {}) {
    const item = this.element.closest(".ax-file-list__item") || this.element
    item.classList.remove("is-confirming")
    item.querySelector("[data-ax-confirm-submit-panel]")?.remove()
    if (options.restoreFocus && this.previouslyFocusedElement?.isConnected) this.previouslyFocusedElement.focus()
    this.previouslyFocusedElement = null
  }

  closeOpenConfirmations() {
    document.querySelectorAll("[data-ax-confirm-submit-panel]").forEach((panel) => {
      panel.closest(".is-confirming")?.classList.remove("is-confirming")
      panel.remove()
    })
  }

  escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;")
  }
}
