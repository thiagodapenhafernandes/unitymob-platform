import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["vertical", "horizontal"]

  connect() {
    this.horizontalOptionData = this.captureHorizontalOptions()
    this.sync()
  }

  sync() {
    if (!this.hasVerticalTarget || !this.hasHorizontalTarget) return

    const selectedVerticalId = this.verticalTarget.value
    const currentValue = this.horizontalTarget.value
    let selectedOptionStillAvailable = currentValue === ""

    this.horizontalOptions.forEach((option) => {
      const verticalId = option.dataset.verticalProfileId
      const available = selectedVerticalId === "" || verticalId === selectedVerticalId

      option.hidden = !available
      option.disabled = !available
      if (available && option.value === currentValue) selectedOptionStillAvailable = true
    })

    this.horizontalOptgroups.forEach((group) => {
      const visibleOptions = Array.from(group.querySelectorAll("option")).some((option) => !option.hidden)
      group.hidden = !visibleOptions
      group.disabled = !visibleOptions
    })

    if (!selectedOptionStillAvailable) this.horizontalTarget.value = ""
    this.syncTomSelect(selectedVerticalId, currentValue, selectedOptionStillAvailable)
  }

  syncTomSelect(selectedVerticalId, currentValue, selectedOptionStillAvailable) {
    const tomSelect = this.horizontalTarget.tomselect
    if (!tomSelect) return

    const availableOptions = this.horizontalOptionData.filter((option) => {
      return option.blank || selectedVerticalId === "" || option.verticalProfileId === selectedVerticalId
    })
    const nextValue = selectedOptionStillAvailable ? currentValue : ""

    tomSelect.clear(true)
    tomSelect.clearOptions()

    availableOptions.forEach((option) => {
      tomSelect.addOption({
        value: option.value,
        text: option.text,
        optgroup: option.optgroup || undefined
      })
    })

    tomSelect.refreshOptions(false)
    tomSelect.setValue(nextValue, true)
  }

  captureHorizontalOptions() {
    return Array.from(this.horizontalTarget.querySelectorAll("option")).map((option) => ({
      value: option.value,
      text: option.textContent.trim(),
      verticalProfileId: option.dataset.verticalProfileId || "",
      optgroup: option.closest("optgroup")?.label || "",
      blank: option.value === ""
    }))
  }

  get horizontalOptions() {
    return Array.from(this.horizontalTarget.querySelectorAll("option[data-vertical-profile-id]"))
  }

  get horizontalOptgroups() {
    return Array.from(this.horizontalTarget.querySelectorAll("optgroup"))
  }
}
