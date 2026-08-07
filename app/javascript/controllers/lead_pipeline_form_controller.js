import { Controller } from "@hotwired/stimulus"

// Formulário de criação de funil: adiciona/remove etapas antes do submit Rails.
export default class extends Controller {
  static targets = ["list", "template", "stageRow", "stageName"]

  addStage(event) {
    event.preventDefault()

    const marker = String(Date.now())
    const html = this.templateTarget.innerHTML.split("NEW_STAGE").join(marker)
    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.stageNameTargets[this.stageNameTargets.length - 1]?.focus()
  }

  removeStage(event) {
    event.preventDefault()

    const row = event.target.closest("[data-lead-pipeline-form-target='stageRow']")
    if (!row) return

    if (this.stageRowTargets.length <= 1) {
      row.querySelectorAll("input").forEach((input) => { input.value = "" })
      row.querySelector("select").value = "open"
      row.querySelector("[data-lead-pipeline-form-target='stageName']")?.focus()
      return
    }

    row.remove()
  }
}
