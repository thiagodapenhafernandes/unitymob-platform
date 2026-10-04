import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay", "form", "feedback", "submit"]
  static values = {
    successMessage: String
  }

  connect() {
    this.boundCloseOnEscape = this.closeOnEscape.bind(this)
    document.addEventListener("keydown", this.boundCloseOnEscape)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundCloseOnEscape)
  }

  open() {
    if (!this.hasOverlayTarget) return

    this.overlayTarget.hidden = false
    document.body.style.overflow = "hidden"
    this.clearFeedback()

    const firstField = this.formTarget?.querySelector("input:not([type='hidden']), select, textarea")
    window.setTimeout(() => firstField?.focus(), 80)
  }

  close() {
    if (!this.hasOverlayTarget) return

    this.overlayTarget.hidden = true
    document.body.style.overflow = ""
    // Um #modal-ID na URL reabriria o modal ao recarregar: some da barra de endereço ao fechar.
    if (window.location.hash.startsWith("#modal-")) window.history.replaceState(null, "", window.location.pathname + window.location.search)
  }

  closeOnEscape(event) {
    if (event.key === "Escape" && this.hasOverlayTarget && !this.overlayTarget.hidden) this.close()
  }

  async submit(event) {
    event.preventDefault()
    if (this.element.closest(".lp-preview-block")) return
    if (!this.hasFormTarget) return

    const fileError = this.fileError()
    if (fileError) {
      this.showFeedback(fileError, true)
      return
    }

    this.setSubmitting(true)
    this.clearFeedback()

    try {
      const response = await fetch(this.formTarget.action, {
        method: this.formTarget.method || "POST",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        body: new FormData(this.formTarget)
      })

      const payload = await response.json().catch(() => ({}))

      if (!response.ok || payload.success === false) {
        this.showFeedback((payload.errors || ["Não foi possível enviar o formulário."]).join(" "), true)
        return
      }

      this.showFeedback(payload.message || this.successMessageValue || "Mensagem enviada com sucesso.")
      this.formTarget.reset()

      if (payload.redirect_url) {
        window.setTimeout(() => { window.location.href = payload.redirect_url }, 700)
      } else {
        window.setTimeout(() => this.close(), 1100)
      }
    } catch (_error) {
      this.showFeedback("Não foi possível enviar o formulário. Tente novamente.", true)
    } finally {
      this.setSubmitting(false)
    }
  }

  // Confere tamanho e quantidade antes de subir (o servidor valida de novo).
  fileError() {
    for (const input of this.formTarget.querySelectorAll("input[type='file']")) {
      const files = Array.from(input.files || [])
      const maxBytes = Number(input.dataset.maxMb || 10) * 1024 * 1024
      const maxFiles = Number(input.dataset.maxFiles || 1)

      if (files.length > maxFiles) return `Envie no máximo ${maxFiles} arquivo(s).`
      const tooBig = files.find((file) => file.size > maxBytes)
      if (tooBig) return `${tooBig.name} passa do limite de ${input.dataset.maxMb} MB.`
    }
    return null
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  setSubmitting(isSubmitting) {
    if (!this.hasSubmitTarget) return

    this.submitTarget.disabled = isSubmitting
    this.submitTarget.setAttribute("aria-busy", isSubmitting ? "true" : "false")
  }

  showFeedback(message, isError = false) {
    if (!this.hasFeedbackTarget) return

    this.feedbackTarget.textContent = message
    this.feedbackTarget.hidden = false
    this.feedbackTarget.classList.toggle("is-error", isError)
  }

  clearFeedback() {
    if (!this.hasFeedbackTarget) return

    this.feedbackTarget.textContent = ""
    this.feedbackTarget.hidden = true
    this.feedbackTarget.classList.remove("is-error")
  }
}
