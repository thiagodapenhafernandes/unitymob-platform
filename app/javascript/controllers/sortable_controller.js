import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static values = {
    handle: String,
    animation: { type: Number, default: 150 }
  }

  connect() {
    this.sortable = new Sortable(this.element, {
      handle: this.handleValue,
      animation: this.animationValue,
      onEnd: this.updatePositions.bind(this)
    })
    this.updatePositions()
  }

  disconnect() {
    this.sortable.destroy()
  }

  updatePositions() {
    this.element.querySelectorAll(".nested-form-wrapper").forEach((item, index) => {
      const positionField = item.querySelector(".position-field")
      const positionDisplay = item.querySelector(".position-display")
      if (positionField) positionField.value = index + 1
      if (positionDisplay) positionDisplay.textContent = index + 1
    })
  }
}
