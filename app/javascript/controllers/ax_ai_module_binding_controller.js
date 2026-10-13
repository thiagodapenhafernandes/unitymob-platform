import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["exception", "provider", "model", "custom", "summary", "status"]
  static values = { presets: Object }

  connect() {
    this.form = this.element.closest("form")
    this.refresh = () => this.sync()
    this.form.addEventListener("change", this.refresh)
    this.form.addEventListener("input", this.refresh)
    this.sync()
  }

  disconnect() {
    this.form.removeEventListener("change", this.refresh)
    this.form.removeEventListener("input", this.refresh)
  }

  sync() {
    const exception = this.exceptionTarget.checked
    const providerKey = (exception && this.providerTarget.value) || this.form.querySelector("#ai_provider").value
    const preset = this.presetsValue[providerKey]
    const modelField = this.modelTargets.find(field => field.dataset.provider === providerKey)
    const presetModel = this.form.querySelector(`#${preset.modelId}`)?.value
    const selection = (exception && modelField?.value) || presetModel
    const custom = exception && modelField?.value === "__custom__"
      ? this.customTargets.find(field => field.dataset.provider === providerKey)?.value
      : this.form.querySelector(`#${preset.customId}`)?.value
    const model = selection === "__custom__" ? (custom?.trim() || "Informe o modelo")
      : (!selection || selection === "__automatic__" ? preset.fallback : selection)
    this.summaryTarget.textContent = `${preset.label} · ${model}`
    this.statusTarget.textContent = exception ? "Exceção · configuração personalizada" : "Herdando o preset da conta"
  }
}
