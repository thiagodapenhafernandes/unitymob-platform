import { Controller } from "@hotwired/stimulus"

// Modal "Arquivar Lead": revela e exige a justificativa assim que um motivo é escolhido.
export default class extends Controller {
  static targets = ["justification"]

  reveal(event) {
    const hasReason = event.target.value.trim().length > 0
    this.justificationTarget.hidden = !hasReason
    const textarea = this.justificationTarget.querySelector("textarea")
    if (!textarea) return

    textarea.disabled = !hasReason
    textarea.required = hasReason
    if (hasReason) textarea.focus()
  }
}
