import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  loading(event) {
    const button = event.currentTarget
    const loadingText = button.dataset.aiPreviewLoadingText || "Processando..."

    button.classList.add("disabled")
    button.setAttribute("aria-disabled", "true")
    button.innerHTML = `
      <span class="spinner-border spinner-border-sm me-1" aria-hidden="true"></span>
      ${loadingText}
    `
  }
}
