import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["axis", "verticalProfileField", "insertAfterField"]

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
  }
}
