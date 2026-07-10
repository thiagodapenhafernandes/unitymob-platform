import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "panel", "inactiveHint"]

  static values = {
    kind: { type: String, default: "checkbox" }
  }

  connect() {
    this.sync()
  }

  sync(event) {
    this.panelTargets.forEach((panel) => {
      const visible = this.panelMatches(panel) || (!event && panel.dataset.conditionalRevealPreserve === "true")
      this.setPanelState(panel, visible)
    })

    if (event) {
      this.panelTargets.forEach((panel) => delete panel.dataset.conditionalRevealPreserve)
    }

    if (this.hasInactiveHintTarget) {
      this.setVisible(this.inactiveHintTarget, !this.panelTargets.some((panel) => !panel.hidden))
    }
  }

  panelMatches(panel) {
    if (this.kindValue === "positive") return this.numericTriggerValue() > 0
    if (this.kindValue === "select") return this.selectValueMatches(panel)

    return this.triggerTarget.checked
  }

  numericTriggerValue() {
    return Number.parseFloat(String(this.triggerTarget.value || "").replace(",", ".")) || 0
  }

  selectValueMatches(panel) {
    const currentValue = String(this.triggerTarget.value || "").trim()
    const acceptedValues = String(panel.dataset.conditionalRevealValues || "")
      .split("|")
      .map((value) => value.trim())
      .filter(Boolean)

    return acceptedValues.includes("*") ? currentValue.length > 0 : acceptedValues.includes(currentValue)
  }

  setPanelState(panel, enabled) {
    this.setVisible(panel, enabled)

    panel.querySelectorAll("input, select, textarea, button").forEach((field) => {
      field.disabled = !enabled
      if (field.dataset.conditionalRequired === "true") field.required = enabled
      if (field.dataset.conditionalRequiredValues) {
        const requiredValues = field.dataset.conditionalRequiredValues.split("|").map((value) => value.trim())
        field.required = enabled && requiredValues.includes(String(this.triggerTarget.value || "").trim())
      }

      if (field.tomselect) {
        enabled ? field.tomselect.enable() : field.tomselect.disable()
      }
    })
  }

  setVisible(element, visible) {
    element.hidden = !visible
    element.classList.toggle("is-hidden", !visible)
  }
}
