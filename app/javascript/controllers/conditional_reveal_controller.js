import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "panel", "inactiveHint"]

  static values = {
    kind: { type: String, default: "checkbox" },
    fallbackSelector: String
  }

  connect() {
    this.fallbackTrigger = this.hasFallbackSelectorValue ? document.querySelector(this.fallbackSelectorValue) : null
    this.fallbackSync = (event) => this.sync(event)
    this.fallbackTrigger?.addEventListener("change", this.fallbackSync)
    this.sync()
  }

  disconnect() {
    this.fallbackTrigger?.removeEventListener("change", this.fallbackSync)
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
    if (this.kindValue === "radio") return this.radioValueMatches(panel)

    return this.triggerTarget.checked
  }

  numericTriggerValue() {
    return Number.parseFloat(String(this.triggerTarget.value || "").replace(",", ".")) || 0
  }

  selectValueMatches(panel) {
    const currentValue = String(this.triggerTarget.value || this.fallbackTrigger?.value || "").trim()

    return this.valuesMatch(panel, currentValue)
  }

  radioValueMatches(panel) {
    const checked = this.triggerTargets.find((trigger) => trigger.checked) || this.triggerTargets[0]
    const currentValue = String((checked && checked.value) || "").trim()

    return this.valuesMatch(panel, currentValue)
  }

  valuesMatch(panel, currentValue) {
    const acceptedValues = String(panel.dataset.conditionalRevealValues || "")
      .split("|")
      .map((value) => value.trim())
      .filter(Boolean)

    return acceptedValues.includes("*") ? currentValue.length > 0 : acceptedValues.includes(currentValue)
  }

  setPanelState(panel, enabled) {
    this.setVisible(panel, enabled)

    panel.querySelectorAll("input, select, textarea, button").forEach((field) => {
      const fieldEnabled = enabled && field.getAttribute?.("aria-disabled") !== "true" && !field.closest('[data-conditional-reveal-target~="panel"][hidden]')
      field.disabled = !fieldEnabled
      if (field.dataset.conditionalRequired === "true") field.required = fieldEnabled
      if (field.dataset.conditionalRequiredValues) {
        const requiredValues = field.dataset.conditionalRequiredValues.split("|").map((value) => value.trim())
        field.required = fieldEnabled && requiredValues.includes(String(this.triggerTarget.value || "").trim())
      }

      if (field.tomselect) {
        fieldEnabled ? field.tomselect.enable() : field.tomselect.disable()
      }
    })
  }

  setVisible(element, visible) {
    element.hidden = !visible
    element.classList.toggle("is-hidden", !visible)
  }
}
