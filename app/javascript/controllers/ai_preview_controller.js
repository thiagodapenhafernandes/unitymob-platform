import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async submit(event) {
    event.preventDefault()

    const button = event.currentTarget
    const confirmMessage = button.dataset.aiPreviewConfirmMessage
    if (confirmMessage && !window.confirm(confirmMessage)) return

    const originalHtml = button.innerHTML
    this.setLoading(button)

    try {
      const response = await fetch(button.href, {
        method: button.dataset.aiPreviewMethod || "POST",
        credentials: "same-origin",
        headers: {
          "Accept": "text/html",
          "Turbo-Frame": button.dataset.turboFrame || "",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        }
      })
      const html = await response.text()

      this.replaceFrame(button.dataset.turboFrame, html)

      if (!response.ok) throw new Error(`AI preview request failed with status ${response.status}`)
    } catch (error) {
      button.innerHTML = originalHtml
      button.classList.remove("disabled")
      button.removeAttribute("aria-disabled")
      console.error(error)
      window.alert("Não foi possível processar a ação da IA.")
    }
  }

  loading(event) {
    const button = event.currentTarget
    this.setLoading(button)
  }

  setLoading(button) {
    const loadingText = button.dataset.aiPreviewLoadingText || "Processando..."

    button.classList.add("disabled")
    button.setAttribute("aria-disabled", "true")
    button.innerHTML = `
      <span class="spinner-border spinner-border-sm me-1" aria-hidden="true"></span>
      ${loadingText}
    `
  }

  replaceFrame(frameId, html) {
    if (!frameId) return

    const frame = document.getElementById(frameId)
    if (!frame) return

    const template = document.createElement("template")
    template.innerHTML = html.trim()
    const responseFrame = template.content.querySelector(`turbo-frame#${CSS.escape(frameId)}`)

    if (responseFrame) {
      frame.replaceWith(responseFrame)
    } else {
      frame.innerHTML = html
    }
  }
}
