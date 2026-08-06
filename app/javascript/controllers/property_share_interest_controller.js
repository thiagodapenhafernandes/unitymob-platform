import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "dialog",
    "identityError",
    "identityForm",
    "nameInput",
    "notice",
    "previewDialog",
    "previewBody",
    "previewTitle",
    "selectedProperty",
    "submitButton"
  ]
  static values = { url: String, errorMessage: String }

  connect() {
    this.previewCloseHandler = () => document.documentElement.classList.remove("shared-property-preview-open")
    if (this.hasPreviewDialogTarget) this.previewDialogTarget.addEventListener("close", this.previewCloseHandler)
  }

  disconnect() {
    this.closePreview()
    if (this.hasPreviewDialogTarget && this.previewCloseHandler) this.previewDialogTarget.removeEventListener("close", this.previewCloseHandler)
  }

  interest(event) {
    this.habitationId = event.currentTarget.dataset.habitationId
    this.propertyTitle = event.currentTarget.dataset.propertyTitle || ""
    this.send({})
  }

  identify(event) {
    event.preventDefault()
    const data = new FormData(event.currentTarget)
    this.send({ name: data.get("name"), phone: data.get("phone") })
  }

  close() {
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  async preview(event) {
    event.preventDefault()
    const link = event.currentTarget
    if (!this.hasPreviewDialogTarget || !this.hasPreviewBodyTarget) {
      window.location.href = link.href
      return
    }

    this.previewTitleTarget.textContent = link.dataset.propertyTitle || "Detalhes do imóvel"
    this.previewBodyTarget.innerHTML = '<div class="shared-property-preview__loading">Carregando detalhes...</div>'
    if (!this.previewDialogTarget.open) this.previewDialogTarget.showModal()
    document.documentElement.classList.add("shared-property-preview-open")

    try {
      const response = await fetch(link.dataset.previewUrl || link.href, { headers: { Accept: "text/html" } })
      if (!response.ok) throw new Error("Falha ao carregar detalhes.")
      this.previewBodyTarget.innerHTML = await response.text()
    } catch (error) {
      this.previewBodyTarget.innerHTML = `<div class="shared-property-preview__error">${error.message}</div>`
    }
  }

  closePreview() {
    if (!this.hasPreviewDialogTarget || !this.previewDialogTarget.open) return

    this.previewDialogTarget.close()
    document.documentElement.classList.remove("shared-property-preview-open")
  }

  async send(identity) {
    this.setSubmitting(true)
    this.hideIdentityError()

    try {
      const body = new FormData(); body.append("habitation_id", this.habitationId)
      Object.entries(identity).forEach(([key, value]) => body.append(key, value))
      const response = await fetch(this.urlValue, { method: "POST", headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "", Accept: "application/json" }, body })
      const payload = await response.json()

      if (payload.requires_identity) return this.openIdentityDialog()
      if (!response.ok) return this.showIdentityError(payload.error || this.errorMessageValue)

      this.close()
      this.show(payload.message)
    } catch {
      this.showIdentityError(this.errorMessageValue)
    } finally {
      this.setSubmitting(false)
    }
  }

  openIdentityDialog() {
    if (this.hasSelectedPropertyTarget && this.propertyTitle) {
      this.selectedPropertyTarget.textContent = `Interesse em: ${this.propertyTitle}`
      this.selectedPropertyTarget.hidden = false
    }

    if (!this.dialogTarget.open) this.dialogTarget.showModal()
    requestAnimationFrame(() => {
      if (this.hasNameInputTarget) this.nameInputTarget.focus()
    })
  }

  show(message) { this.noticeTarget.textContent = message; this.noticeTarget.hidden = false }

  showIdentityError(message) {
    if (!this.hasIdentityErrorTarget) return this.show(message)

    this.identityErrorTarget.textContent = message
    this.identityErrorTarget.hidden = false
  }

  hideIdentityError() {
    if (!this.hasIdentityErrorTarget) return

    this.identityErrorTarget.textContent = ""
    this.identityErrorTarget.hidden = true
  }

  setSubmitting(submitting) {
    if (!this.hasSubmitButtonTarget) return

    this.submitButtonTarget.disabled = submitting
    this.submitButtonTarget.setAttribute("aria-busy", submitting ? "true" : "false")
  }
}
