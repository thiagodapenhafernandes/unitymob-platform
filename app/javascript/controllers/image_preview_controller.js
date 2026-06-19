import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "placeholder", "filename", "domain"]

  connect() {
  }

  update(event) {
    const input = event.target || this.inputTarget
    const file = input.files[0]

    if (file) {
      this._updatePreview(file)
    }
  }

  async fetchLogo(event) {
    console.log("🚀 fetchLogo triggered!")
    event.preventDefault()
    let domainInput = this.domainTarget.value.trim()

    if (!domainInput) {
      this.showMessage("Preencha o domínio primeiro. Ex.: google.com", "warning")
      return
    }

    // Smart cleanup: extract hostname if user pastes full URL
    try {
      if (domainInput.startsWith('http')) {
        domainInput = new URL(domainInput).hostname
      }
      // Remove trailing slashes just in case
      domainInput = domainInput.replace(/\/$/, '')
    } catch (e) {
      // If invalid URL, keep original input to try anyway
    }

    // Update field with sanitized value for user feedback
    this.domainTarget.value = domainInput

    const btn = event.currentTarget
    const originalContent = btn.innerHTML
    const originalClassName = btn.className

    // Set loading state
    btn.innerHTML = `
      <span class="ax-spinner" aria-hidden="true"></span>
      Buscando...
    `
    btn.disabled = true
    btn.setAttribute("aria-busy", "true")

    const googleUrl = `https://www.google.com/s2/favicons?domain=${domainInput}&sz=256`

    // Check if we are in admin namespace or root to build proxy URL
    // We use the proxy to avoid CORS issues from Google
    const proxyBase = "/admin/constructors/proxy_logo"
    const proxyUrl = `${proxyBase}?url=${encodeURIComponent(googleUrl)}`

    try {
      // Small artificial delay to show the spinner (UX)
      await new Promise(r => setTimeout(r, 600))

      const response = await fetch(proxyUrl)
      if (!response.ok) throw new Error("GoogleFailed")

      const blob = await response.blob()

      // Check if blob is valid image
      if (!blob || blob.type.indexOf("image") === -1) {
        throw new Error("InvalidImage")
      }

      const file = new File([blob], `${domainInput}-logo.png`, { type: blob.type })

      // Create a DataTransfer to simulate file selection
      const dataTransfer = new DataTransfer()
      dataTransfer.items.add(file)
      this.inputTarget.files = dataTransfer.files

      // Update UI manually
      this._updatePreview(file)

      // Success feedback
      btn.innerHTML = '<i class="bi bi-check-lg ax-ico"></i> Sucesso!'
      btn.className = this.successButtonClass(originalClassName)
      this.showMessage("Logo carregado com sucesso.", "success")
      setTimeout(() => {
        btn.innerHTML = originalContent
        btn.className = originalClassName
        btn.disabled = false
        btn.removeAttribute("aria-busy")
      }, 2000)
    } catch (error) {
      console.error("Erro no download:", error)

      this.showMessage(`Não foi possível encontrar um logo válido para "${domainInput}". Faça o upload manual.`, "danger")

      btn.innerHTML = originalContent
      btn.className = originalClassName
      btn.disabled = false
      btn.removeAttribute("aria-busy")
    }
  }

  successButtonClass(originalClassName) {
    if (originalClassName.includes("ax-btn")) return `${originalClassName} ax-btn--success`
    return originalClassName.replace("btn-outline-primary", "btn-success")
  }

  showMessage(message, tone = "info") {
    let status = this.element.querySelector("[data-image-preview-status]")
    if (!status) {
      status = document.createElement("div")
      status.dataset.imagePreviewStatus = "true"
      this.element.appendChild(status)
    }

    status.className = `ax-controller-status ax-controller-status--${tone}`
    status.textContent = message
  }

  _updatePreview(file) {
    // Update filename label
    if (this.hasFilenameTarget) {
      this.filenameTarget.textContent = file.name
    }

    // Create preview
    const reader = new FileReader()
    reader.onload = (e) => {
      if (this.hasPreviewTarget) {
        this.previewTarget.src = e.target.result
        this.previewTarget.classList.remove("d-none")
      }
      if (this.hasPlaceholderTarget) {
        this.placeholderTarget.classList.add("d-none")
      }
    }
    reader.readAsDataURL(file)
  }
}
