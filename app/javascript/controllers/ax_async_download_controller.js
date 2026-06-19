import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    accept: { type: String, default: "*/*" },
    filename: String,
    loadingText: String,
    url: String
  }

  connect() {
    this.originalHtml = this.element.innerHTML
  }

  async download(event) {
    event.preventDefault()

    if (this.element.dataset.downloading === "true") return

    this.setLoading(true)
    this.dispatch("start")

    try {
      const url = this.downloadUrl()
      if (!url) throw new Error("URL de download ausente.")

      const response = await fetch(url, {
        headers: { Accept: this.acceptValue },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`Download falhou com status ${response.status}.`)

      const blob = await response.blob()
      const filename = this.downloadFilename(response)
      this.saveBlob(blob, filename)
      this.dispatch("success", { detail: { filename } })
    } catch (error) {
      this.dispatch("error", { detail: { error } })
      console.error(error)
    } finally {
      this.setLoading(false)
      this.dispatch("finish")
    }
  }

  downloadUrl() {
    if (this.hasUrlValue) return this.urlValue
    if (this.element instanceof HTMLAnchorElement) return this.element.href

    return this.element.getAttribute("href") || ""
  }

  downloadFilename(response) {
    return this.filenameValue ||
      this.element.getAttribute("download") ||
      this.filenameFromDisposition(response.headers.get("Content-Disposition")) ||
      "download"
  }

  filenameFromDisposition(disposition) {
    if (!disposition) return null

    const encoded = disposition.match(/filename\*=UTF-8''([^;]+)/i)
    if (encoded?.[1]) return decodeURIComponent(encoded[1].replace(/"/g, ""))

    const plain = disposition.match(/filename="?([^";]+)"?/i)
    return plain?.[1] || null
  }

  saveBlob(blob, filename) {
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement("a")
    anchor.href = url
    anchor.download = filename
    anchor.style.display = "none"
    document.body.appendChild(anchor)
    anchor.click()

    window.setTimeout(() => {
      URL.revokeObjectURL(url)
      anchor.remove()
    }, 1000)
  }

  setLoading(on) {
    this.element.dataset.downloading = on ? "true" : "false"
    this.element.setAttribute("aria-busy", on ? "true" : "false")
    this.element.setAttribute("aria-disabled", on ? "true" : "false")
    this.element.style.pointerEvents = on ? "none" : ""
    this.element.innerHTML = on ? this.loadingHtml() : this.originalHtml
  }

  loadingHtml() {
    const spinner = '<span class="spinner-border spinner-border-sm" aria-hidden="true"></span>'
    if (!this.hasLoadingTextValue || !this.loadingTextValue) return spinner

    return `${spinner}<span>${this.escapeHtml(this.loadingTextValue)}</span>`
  }

  escapeHtml(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
  }
}
