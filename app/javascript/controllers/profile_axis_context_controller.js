import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["axis", "verticalProfileField", "insertAfterField", "scope"]

  connect() {
    this.sync()
  }

  sync() {
    const axis = this.axisTarget.value
    const horizontal = axis === "horizontal"

    if (this.hasVerticalProfileFieldTarget) {
      this.verticalProfileFieldTarget.hidden = !horizontal
    }

    if (this.hasInsertAfterFieldTarget) {
      this.insertAfterFieldTarget.hidden = horizontal
    }

    this.scopeTargets.forEach((select) => {
      const teamOption = select.querySelector('option[value="team"]')
      if (!teamOption) return

      teamOption.disabled = horizontal
      teamOption.hidden = horizontal
      if (horizontal && select.value === "team") select.value = "all"
    })
  }
}
