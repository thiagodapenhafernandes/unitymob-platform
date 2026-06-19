import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    formId: String,
    message: { type: String, default: "Confirmar esta ação?" },
    confirmLabel: { type: String, default: "Confirmar" },
    cancelLabel: { type: String, default: "Cancelar" }
  }

  request(event) {
    event.preventDefault()
    event.stopPropagation()

    this.closeOpenConfirmations()
    this.showConfirmation()
  }

  confirm(event) {
    event.preventDefault()
    event.stopPropagation()

    const form = document.getElementById(this.formIdValue)
    if (!form) return

    if (typeof form.requestSubmit === "function") {
      form.requestSubmit()
    } else {
      form.submit()
    }
  }

  cancel(event) {
    event.preventDefault()
    event.stopPropagation()
    this.closeConfirmation()
  }

  showConfirmation() {
    const item = this.element.closest(".ax-file-list__item") || this.element
    item.classList.add("is-confirming")

    const panel = document.createElement("div")
    panel.className = "ax-confirm-submit__panel"
    panel.dataset.axConfirmSubmitPanel = "true"
    panel.innerHTML = `
      <span class="ax-confirm-submit__message">${this.escapeHtml(this.messageValue)}</span>
      <span class="ax-confirm-submit__actions">
        <button type="button" class="ax-confirm-submit__btn" data-ax-confirm-submit-cancel>${this.escapeHtml(this.cancelLabelValue)}</button>
        <button type="button" class="ax-confirm-submit__btn ax-confirm-submit__btn--danger" data-ax-confirm-submit-confirm>${this.escapeHtml(this.confirmLabelValue)}</button>
      </span>
    `

    panel.querySelector("[data-ax-confirm-submit-cancel]").addEventListener("click", this.cancel.bind(this))
    panel.querySelector("[data-ax-confirm-submit-confirm]").addEventListener("click", this.confirm.bind(this))
    item.appendChild(panel)
  }

  closeConfirmation() {
    const item = this.element.closest(".ax-file-list__item") || this.element
    item.classList.remove("is-confirming")
    item.querySelector("[data-ax-confirm-submit-panel]")?.remove()
  }

  closeOpenConfirmations() {
    document.querySelectorAll("[data-ax-confirm-submit-panel]").forEach((panel) => {
      panel.closest(".ax-file-list__item")?.classList.remove("is-confirming")
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
