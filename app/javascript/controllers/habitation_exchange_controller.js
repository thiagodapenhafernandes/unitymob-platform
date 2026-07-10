import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "master",
    "configuration",
    "inactiveHint",
    "vehicleToggle",
    "propertyToggle",
    "othersToggle",
    "vehiclePanel",
    "propertyPanel",
    "othersPanel",
    "vehicleValue",
    "propertyValue",
    "othersValue",
    "total"
  ]

  connect() {
    this.sync()
    if (this.masterTarget.checked && this.hasPricedSelectedItem()) this.recalculateTotal()
  }

  sync(event) {
    const enabled = this.masterTarget.checked

    this.setSectionState(this.configurationTarget, enabled)
    this.setVisible(this.inactiveHintTarget, !enabled)
    this.setSectionState(this.vehiclePanelTarget, enabled && this.vehicleToggleTarget.checked)
    this.setSectionState(this.propertyPanelTarget, enabled && this.propertyToggleTarget.checked)
    this.setSectionState(this.othersPanelTarget, enabled && this.othersToggleTarget.checked)

    if (event?.target !== this.masterTarget || (enabled && this.hasPricedSelectedItem())) {
      this.recalculateTotal()
    }
  }

  recalculateTotal() {
    if (!this.masterTarget.checked) return

    const total = [
      [this.vehicleToggleTarget, this.vehicleValueTarget],
      [this.propertyToggleTarget, this.propertyValueTarget],
      [this.othersToggleTarget, this.othersValueTarget]
    ].reduce((sum, [toggle, input]) => sum + (toggle.checked ? this.currencyToCents(input.value) : 0), 0)

    this.totalTarget.value = total > 0 ? this.formatCurrency(total) : ""
  }

  hasPricedSelectedItem() {
    if (this.vehicleToggleTarget.checked && this.currencyToCents(this.vehicleValueTarget.value) > 0) return true
    if (this.propertyToggleTarget.checked && this.currencyToCents(this.propertyValueTarget.value) > 0) return true
    if (this.othersToggleTarget.checked && this.currencyToCents(this.othersValueTarget.value) > 0) return true

    return false
  }

  setSectionState(section, enabled) {
    this.setVisible(section, enabled)
    section.querySelectorAll("input, select, textarea, button").forEach((field) => {
      field.disabled = !enabled
      if (field.dataset.exchangeRequired === "true") field.required = enabled
    })
  }

  setVisible(element, visible) {
    element.hidden = !visible
    element.classList.toggle("is-hidden", !visible)
  }

  currencyToCents(value) {
    const digits = value.toString().replace(/\D/g, "")
    return digits.length > 0 ? Number.parseInt(digits, 10) : 0
  }

  formatCurrency(cents) {
    return (cents / 100).toLocaleString("pt-BR", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })
  }
}
