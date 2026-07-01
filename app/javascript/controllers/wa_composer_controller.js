import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body", "fileInput", "fileSummary", "fileName", "template", "modeLabel", "error", "submit"]

  connect() {
    this.submitting = false
    this.successTimer = null
    this.pendingMessageId = null
    this.optimisticObjectUrls = new Map()
    this.refreshState()
  }

  disconnect() {
    if (this.successTimer) clearTimeout(this.successTimer)
    this.revokeAllOptimisticObjectUrls()
  }

  fileChanged() {
    const file = this.fileInputTarget.files[0]
    if (!file) {
      this.hideSummary()
      this.refreshState()
      return
    }

    if (this.hasTemplateTarget) this.templateTarget.value = ""
    this.fileNameTarget.textContent = `${this.fileKind(file)} · ${file.name} · ${this.humanSize(file.size)}`
    this.fileSummaryTarget.classList.remove("is-hidden")
    this.refreshState()
  }

  clearFile() {
    this.fileInputTarget.value = ""
    this.hideSummary()
    this.refreshState()
  }

  templateChanged() {
    if (!this.hasTemplateTarget) return

    if (this.templateTarget.value) {
      this.clearFile()
      this.bodyTarget.value = ""
      this.bodyTarget.disabled = true
      this.bodyTarget.placeholder = "Modelos aprovados são enviados sem texto livre adicional"
    } else {
      this.bodyTarget.disabled = false
      this.bodyTarget.placeholder = "Escreva uma mensagem..."
    }

    this.refreshState()
  }

  bodyChanged() {
    this.hideError()
    this.refreshState()
  }

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey) return
    if (event.isComposing) return

    event.preventDefault()
    this.element.requestSubmit()
  }

  async submit(event) {
    event.preventDefault()
    if (this.submitting) return

    if (this.successTimer) clearTimeout(this.successTimer)
    this.hideError()
    this.submitting = true
    const optimisticPayload = this.buildOptimisticPayload()
    if (optimisticPayload) {
      this.pendingMessageId = optimisticPayload.tempId
      window.dispatchEvent(new CustomEvent("wa:message-submitting", { detail: optimisticPayload }))
    }
    this.refreshState()

    try {
      const response = await fetch(this.element.action, {
        method: this.element.method || "POST",
        body: new FormData(this.element),
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        credentials: "same-origin"
      })

      const payload = await response.json().catch(() => ({}))
      if (!response.ok || payload.ok === false) {
        this.showError(payload.error || "Nao foi possivel enviar a mensagem.")
        this.dispatchFailedMessage()
        return
      }

      this.showSuccessState(payload)
      window.dispatchEvent(new CustomEvent("wa:message-sent", {
        detail: { ...payload, tempId: this.pendingMessageId }
      }))
      this.revokeOptimisticObjectUrl(this.pendingMessageId)
      this.resetForm()
    } catch (_error) {
      this.showError("Nao foi possivel enviar a mensagem.")
      this.dispatchFailedMessage()
    } finally {
      this.submitting = false
      this.pendingMessageId = null
      this.refreshState()
    }
  }

  hideSummary() {
    if (!this.hasFileSummaryTarget) return

    this.fileSummaryTarget.classList.add("is-hidden")
    if (this.hasFileNameTarget) this.fileNameTarget.textContent = "Nenhum arquivo"
  }

  refreshState() {
    const hasTemplate = this.hasTemplateTarget && this.templateTarget.value.length > 0
    const hasFile = this.fileInputTarget.files.length > 0
    const hasBody = this.bodyTarget.value.trim().length > 0

    if (!hasTemplate && this.bodyTarget.disabled) {
      this.bodyTarget.disabled = false
      this.bodyTarget.placeholder = "Escreva uma mensagem..."
    }

    if (this.hasModeLabelTarget) {
      this.modeLabelTarget.textContent = this.submitting
        ? "Enviando..."
        : hasTemplate
          ? "Modelo aprovado"
          : hasFile
            ? `${this.fileKind(this.fileInputTarget.files[0])} com legenda`
            : "Mensagem livre"
    }

    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = this.submitting || !(hasTemplate || hasFile || hasBody)
      this.submitTarget.classList.toggle("is-loading", this.submitting)
    }
  }

  resetForm() {
    if (this.hasBodyTarget) {
      this.bodyTarget.value = ""
      this.bodyTarget.disabled = false
      this.bodyTarget.placeholder = "Escreva uma mensagem..."
    }

    if (this.hasTemplateTarget) this.templateTarget.value = ""
    if (this.hasFileInputTarget) this.fileInputTarget.value = ""

    this.hideSummary()
    this.hideError()
  }

  showError(message) {
    if (!this.hasErrorTarget) {
      window.alert(message)
      return
    }

    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("is-hidden")
  }

  hideError() {
    if (!this.hasErrorTarget) return

    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("is-hidden")
  }

  showSuccessState(payload) {
    if (!this.hasModeLabelTarget) return

    const kind = payload?.type === "template"
      ? "Modelo enviado"
      : payload?.type === "text"
        ? "Mensagem enviada"
        : "Arquivo enviado"

    this.modeLabelTarget.textContent = kind
    this.modeLabelTarget.classList.add("is-success")
    this.successTimer = setTimeout(() => {
      this.modeLabelTarget.classList.remove("is-success")
      this.refreshState()
    }, 1800)
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  humanSize(bytes) {
    const size = Number(bytes || 0)
    if (size < 1024) return `${size} B`
    if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`

    return `${(size / (1024 * 1024)).toFixed(1)} MB`
  }

  fileKind(file) {
    const type = String(file?.type || "")
    if (type.startsWith("image/")) return "Imagem"
    if (type.startsWith("video/")) return "Vídeo"
    if (type.startsWith("audio/")) return "Áudio"

    return "Documento"
  }

  buildOptimisticPayload() {
    const tempId = `wa-temp-${Date.now()}-${Math.floor(Math.random() * 10000)}`
    const body = this.hasBodyTarget ? this.bodyTarget.value.trim() : ""
    const file = this.hasFileInputTarget ? this.fileInputTarget.files[0] : null
    const templateName = this.hasTemplateTarget ? this.templateTarget.value.trim() : ""
    const html = this.optimisticHtml({ tempId, body, file, templateName })

    return html ? { tempId, html } : null
  }

  optimisticHtml({ tempId, body, file, templateName }) {
    const content = this.optimisticContent({ tempId, body, file, templateName })
    if (!content) return null
    const compactClass = this.element.classList.contains("wa-inbox-composer--compact") ? "wa-inbox-bubble--compact" : ""
    const meta = this.optimisticMeta()

    return `
      <div class="wa-inbox-bubble-row wa-inbox-bubble-row--outbound is-optimistic" data-wa-temp-id="${tempId}">
        <div class="wa-inbox-bubble wa-inbox-bubble--outbound ${file ? "wa-inbox-bubble--media" : ""} ${compactClass}">
          <div class="wa-inbox-bubble__surface">
            ${content}
          </div>
          ${meta}
        </div>
      </div>
    `
  }

  optimisticContent({ tempId, body, file, templateName }) {
    if (templateName) {
      return `
        <div class="wa-inbox-bubble__eyebrow"><i class="bi bi-file-text"></i> modelo ${this.escapeHtml(templateName)}</div>
      `
    }

    if (file) {
      const kind = this.fileKind(file)
      const meta = `${kind} · ${this.humanSize(file.size)}`
      const bodyHtml = body ? `<div class="wa-inbox-bubble__body wa-inbox-bubble__body--media">${this.escapeHtml(body)}</div>` : ""
      const objectUrl = this.optimisticObjectUrl(tempId, file)
      const mediaBlock = kind === "Imagem" && objectUrl
        ? `
          <div class="wa-inbox-bubble__media-block wa-inbox-bubble__media-block--image">
            <div class="wa-inbox-media-frame wa-inbox-media-frame--image wa-inbox-media wa-inbox-media--image-link">
              <img src="${this.escapeHtml(objectUrl)}" alt="${this.escapeHtml(file.name)}" class="wa-inbox-media wa-inbox-media--image">
            </div>
            <div class="wa-inbox-media-card__meta">${this.escapeHtml(meta)}</div>
          </div>
        `
        : kind === "Vídeo" && objectUrl
          ? `
            <div class="wa-inbox-bubble__media-block wa-inbox-bubble__media-block--video">
              <div class="wa-inbox-media-frame wa-inbox-media-frame--video wa-inbox-media wa-inbox-media--video-link">
                <video src="${this.escapeHtml(objectUrl)}" class="wa-inbox-media wa-inbox-media--video" muted playsinline preload="metadata"></video>
                <span class="wa-inbox-media__play" aria-hidden="true">
                  <i class="bi bi-play-fill"></i>
                </span>
              </div>
              <div class="wa-inbox-media-card__meta">${this.escapeHtml(meta)}</div>
            </div>
          `
          : kind === "Áudio"
        ? `
          <div class="wa-inbox-bubble__media-block wa-inbox-bubble__media-block--audio">
            <div class="wa-audio-preview wa-audio-preview--message">
              <button type="button" class="wa-audio-preview__toggle" aria-label="Áudio pendente" disabled>
                <i class="bi bi-play-fill"></i>
              </button>
              <div class="wa-audio-preview__body">
                <div class="wa-audio-preview__meta">
                  <span class="wa-audio-preview__eyebrow">Áudio</span>
                  <strong class="wa-audio-preview__title">${this.escapeHtml(file.name)}</strong>
                </div>
                <div class="wa-audio-preview__summary">${this.escapeHtml(meta)}</div>
                <button type="button" class="wa-audio-preview__track" aria-label="Áudio pendente" disabled>
                  <span class="wa-audio-preview__track-fill" style="width:0%"></span>
                </button>
                <div class="wa-audio-preview__footer">
                  <span class="wa-audio-preview__time"><span>0:00</span><span>/</span><span>0:00</span></span>
                  <span class="wa-audio-preview__hint">Aguardando envio</span>
                </div>
              </div>
            </div>
          </div>
        `
        : `
          <div class="wa-inbox-bubble__media-block wa-inbox-bubble__media-block--document">
            <div class="wa-inbox-media-card wa-inbox-media-card--document wa-inbox-media-card--message">
              <span class="wa-inbox-media-card__icon"><i class="bi bi-paperclip"></i></span>
              <span class="wa-inbox-media-card__copy">
                <span class="wa-inbox-media-card__title">${this.escapeHtml(file.name)}</span>
                <span class="wa-inbox-media-card__meta">${this.escapeHtml(meta)}</span>
              </span>
            </div>
          </div>
        `
      return `
        ${mediaBlock}
        ${bodyHtml}
      `
    }

    if (body) {
      return `
        <div class="wa-inbox-bubble__body wa-inbox-bubble__body--text">${this.escapeHtml(body)}</div>
      `
    }

    return null
  }

  optimisticMeta() {
    return `
      <div class="wa-inbox-bubble__meta" data-wa-message-status="pending">
        <div class="wa-inbox-bubble__time">
          ${this.escapeHtml(this.currentTimeLabel())}
          <i class="bi bi-clock" data-wa-message-status-icon title="Enviando" aria-label="Enviando"></i>
        </div>
      </div>
    `
  }

  currentTimeLabel() {
    return new Intl.DateTimeFormat("pt-BR", {
      hour: "2-digit",
      minute: "2-digit"
    }).format(new Date())
  }

  escapeHtml(value) {
    return String(value || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }

  dispatchFailedMessage() {
    if (!this.pendingMessageId) return

    window.dispatchEvent(new CustomEvent("wa:message-send-failed", {
      detail: { tempId: this.pendingMessageId }
    }))
  }

  optimisticObjectUrl(tempId, file) {
    if (!tempId || !file || typeof URL === "undefined" || typeof URL.createObjectURL !== "function") return null
    if (this.optimisticObjectUrls.has(tempId)) return this.optimisticObjectUrls.get(tempId)

    const objectUrl = URL.createObjectURL(file)
    this.optimisticObjectUrls.set(tempId, objectUrl)
    return objectUrl
  }

  revokeOptimisticObjectUrl(tempId) {
    const objectUrl = this.optimisticObjectUrls.get(tempId)
    if (!objectUrl) return

    URL.revokeObjectURL(objectUrl)
    this.optimisticObjectUrls.delete(tempId)
  }

  revokeAllOptimisticObjectUrls() {
    this.optimisticObjectUrls.forEach((objectUrl) => URL.revokeObjectURL(objectUrl))
    this.optimisticObjectUrls.clear()
  }
}
