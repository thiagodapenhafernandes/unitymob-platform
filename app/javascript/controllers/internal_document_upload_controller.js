import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  upload(event) {
    const input = event.target
    if (!input?.files?.length) return

    const form = input.form
    if (!form) return

    const status = document.querySelector(`[data-internal-document-upload-status="${input.id}"]`)
    const label = document.querySelector(`label[for="${input.id}"]`)
    const fileLabel = input.files.length === 1 ? "1 arquivo" : `${input.files.length} arquivos`

    this.renderProgress(status, `Preparando envio de ${fileLabel}...`, 0)
    this.setLabelDisabled(label, true)

    if (!window.XMLHttpRequest || !window.FormData) {
      form.requestSubmit()
      return
    }

    const request = new XMLHttpRequest()
    request.open((form.method || "post").toUpperCase(), form.action, true)
    request.setRequestHeader("Accept", "text/html")

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (token) request.setRequestHeader("X-CSRF-Token", token)

    request.upload.addEventListener("progress", (progressEvent) => {
      if (!progressEvent.lengthComputable) {
        this.renderProgress(status, `Enviando ${fileLabel}...`, 5)
        return
      }

      const percent = Math.max(1, Math.min(99, Math.round((progressEvent.loaded / progressEvent.total) * 100)))
      this.renderProgress(status, `Enviando ${fileLabel}...`, percent)
    })

    request.addEventListener("load", () => {
      if (request.status >= 200 && request.status < 300) {
        this.renderProgress(status, "100% - Anexo salvo. Atualizando lista...", 100, "success")
        window.location.assign(this.documentsUrl(request.responseURL || form.action))
        return
      }

      this.renderProgress(status, "Não foi possível anexar. Tente novamente.", 100, "danger")
      this.resetInput(input, label)
    })

    request.addEventListener("error", () => {
      this.renderProgress(status, "Falha de comunicação durante o envio.", 100, "danger")
      this.resetInput(input, label)
    })

    request.send(new FormData(form))
  }

  documentsUrl(url) {
    if (!url) return `${window.location.pathname}${window.location.search}#documents`

    const parsed = new URL(url, window.location.origin)
    parsed.hash = "documents"
    return parsed.toString()
  }

  renderProgress(status, message, percent, variant = "primary") {
    if (!status) return

    const safePercent = Math.max(0, Math.min(100, Number(percent) || 0))
    status.hidden = false
    status.classList.remove("ax-text-danger", "ax-text-muted")
    status.classList.toggle("ax-text-danger", variant === "danger")
    status.classList.toggle("ax-text-muted", variant !== "danger")
    status.innerHTML = `
      <div class="ax-upload-progress__header">
        <span>${this.escapeHtml(message)}</span>
        <strong>${safePercent}%</strong>
      </div>
      <div class="ax-progress ax-upload-progress__bar" role="progressbar" aria-valuenow="${safePercent}" aria-valuemin="0" aria-valuemax="100">
        <i class="ax-upload-progress__fill ax-upload-progress__fill--${variant}" style="width: ${safePercent}%;"></i>
      </div>
    `
  }

  resetInput(input, label) {
    this.setLabelDisabled(label, false)
    input.value = ""
  }

  setLabelDisabled(label, disabled) {
    if (!label) return

    label.classList.toggle("disabled", disabled)
    if (disabled) {
      label.setAttribute("aria-disabled", "true")
    } else {
      label.removeAttribute("aria-disabled")
    }
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
