import { Controller } from "@hotwired/stimulus"

// Conecta com data-controller="clipboard"
// Targets: source (input com texto), button (botão de copiar), content (span com label do botão)
// Values: successContent (texto do botão após copiar)
export default class extends Controller {
  static targets = ["source", "button", "content"]
  static values = {
    successContent: { type: String, default: "Copiado!" },
    successDuration: { type: Number, default: 2000 }
  }

  copy(event) {
    event.preventDefault()
    if (!this.hasSourceTarget) return

    const text = this.sourceTarget.value || this.sourceTarget.textContent
    if (!text) return

    const original = this.hasContentTarget ? this.contentTarget.textContent : null

    const finish = () => {
      if (this.hasContentTarget) {
        this.contentTarget.textContent = this.successContentValue
      }
      if (this.hasButtonTarget) {
        this.buttonTarget.classList.add("btn-success")
        this.buttonTarget.classList.remove("btn-primary")
      }
      setTimeout(() => {
        if (this.hasContentTarget && original !== null) {
          this.contentTarget.textContent = original
        }
        if (this.hasButtonTarget) {
          this.buttonTarget.classList.remove("btn-success")
          this.buttonTarget.classList.add("btn-primary")
        }
      }, this.successDurationValue)
    }

    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(finish).catch(() => this.fallback(text, finish))
    } else {
      this.fallback(text, finish)
    }
  }

  select(event) {
    const input = event.currentTarget
    if (typeof input.select !== "function") return

    input.select()
    if (typeof input.setSelectionRange === "function") {
      input.setSelectionRange(0, input.value?.length || 0)
    }
  }

  fallback(text, onSuccess) {
    this.sourceTarget.select()
    this.sourceTarget.setSelectionRange(0, 99999)
    try {
      document.execCommand("copy")
      onSuccess()
    } catch (err) {
      console.error("Falha ao copiar para o clipboard:", err)
    }
  }
}
