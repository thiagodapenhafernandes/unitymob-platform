import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "bar", "percent", "title", "message"]

  submit(event) {
    if (this.submitting) {
      event.preventDefault()
      return
    }

    if (!this.hasSelectedFiles()) {
      this.showIndeterminate("Salvando informações", "Validando os dados antes de avançar.")
      return
    }

    event.preventDefault()
    this.submitting = true
    this.submitter = event.submitter || document.activeElement
    this.uploadWithProgress()
  }

  uploadWithProgress() {
    const xhr = new XMLHttpRequest()
    const formData = this.formData()
    this.disableSubmitters()

    xhr.open(this.element.method || "POST", this.element.action, true)
    xhr.setRequestHeader("Accept", "text/html, application/xhtml+xml")
    xhr.setRequestHeader("X-Requested-With", "XMLHttpRequest")

    xhr.upload.addEventListener("loadstart", () => {
      this.showDeterminate("Enviando anexos", "As fotos e autorizações estão sendo enviadas.", 1)
    })

    xhr.upload.addEventListener("progress", (event) => {
      if (!event.lengthComputable) {
        this.showIndeterminate("Enviando anexos", "As fotos e autorizações estão sendo enviadas.")
        return
      }

      const uploadPercent = Math.max(1, Math.min(95, Math.round((event.loaded / event.total) * 95)))
      this.showDeterminate("Enviando anexos", "As fotos e autorizações estão sendo enviadas.", uploadPercent)
    })

    xhr.upload.addEventListener("load", () => {
      this.showDeterminate("Processando", "Upload concluído. O sistema está salvando e validando a captação.", 96)
    })

    xhr.addEventListener("load", () => this.handleResponse(xhr))
    xhr.addEventListener("error", () => this.fail("Não foi possível enviar os anexos. Verifique sua conexão e tente novamente."))
    xhr.addEventListener("abort", () => this.fail("Envio cancelado."))

    xhr.send(formData)
  }

  handleResponse(xhr) {
    if (xhr.status >= 200 && xhr.status < 400) {
      this.showDeterminate("Concluído", "Avançando para a próxima etapa.", 100)
      window.location.href = xhr.responseURL || window.location.href
      return
    }

    if (xhr.status === 422 && xhr.responseText) {
      document.open()
      document.write(xhr.responseText)
      document.close()
      return
    }

    this.fail("O servidor não conseguiu concluir o envio. Tente novamente.")
  }

  formData() {
    if (typeof FormData === "function") {
      try {
        return new FormData(this.element, this.submitter)
      } catch (_) {
        const fallback = new FormData(this.element)
        this.appendSubmitter(fallback)
        return fallback
      }
    }
  }

  appendSubmitter(formData) {
    if (!this.submitter || !this.submitter.name) return
    formData.append(this.submitter.name, this.submitter.value || "")
  }

  hasSelectedFiles() {
    return Array.from(this.element.querySelectorAll("input[type='file']")).some((input) => input.files && input.files.length > 0)
  }

  showDeterminate(title, message, percent) {
    this.panelTarget.hidden = false
    this.panelTarget.classList.remove("is-indeterminate", "is-error")
    this.titleTarget.textContent = title
    this.messageTarget.textContent = message
    this.setProgress(percent)
  }

  showIndeterminate(title, message) {
    this.panelTarget.hidden = false
    this.panelTarget.classList.add("is-indeterminate")
    this.panelTarget.classList.remove("is-error")
    this.titleTarget.textContent = title
    this.messageTarget.textContent = message
    this.percentTarget.textContent = "..."
    this.barTarget.style.width = "45%"
  }

  setProgress(percent) {
    const normalizedPercent = Math.max(0, Math.min(100, percent))
    this.percentTarget.textContent = `${normalizedPercent}%`
    this.barTarget.style.width = `${normalizedPercent}%`
  }

  disableSubmitters() {
    this.element.querySelectorAll("button[type='submit'], input[type='submit']").forEach((button) => {
      button.disabled = true
      button.classList.add("disabled")
    })
  }

  enableSubmitters() {
    this.element.querySelectorAll("button[type='submit'], input[type='submit']").forEach((button) => {
      button.disabled = false
      button.classList.remove("disabled")
    })
  }

  fail(message) {
    this.submitting = false
    this.enableSubmitters()
    this.panelTarget.hidden = false
    this.panelTarget.classList.remove("is-indeterminate")
    this.panelTarget.classList.add("is-error")
    this.titleTarget.textContent = "Envio interrompido"
    this.messageTarget.textContent = message
    this.percentTarget.textContent = "Erro"
  }
}
