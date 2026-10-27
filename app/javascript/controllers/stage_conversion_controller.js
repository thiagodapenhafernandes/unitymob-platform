import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["event", "trigger"]
  static values = { actions: Object }

  connect() { this.sync() }

  sync() {
    const event = this.eventTarget.value
    const enabled = !this.eventTarget.disabled && event !== "" && event !== "none"
    this.triggerTarget.disabled = !enabled
    for (const option of this.triggerTarget.options) {
      option.disabled = Object.keys(this.actionsValue).length > 0 &&
        option.value !== "stage_entered" && option.value !== this.actionsValue[event]
    }
    if (enabled && this.triggerTarget.selectedOptions[0]?.disabled) this.triggerTarget.value = "stage_entered"
  }
}
