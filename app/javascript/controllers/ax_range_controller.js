import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["range", "number"]
  connect() { this.sync({ target: this.numberTarget }) }
  sync(event) {
    const value = Math.max(Number(this.rangeTarget.min), Math.min(Number(this.rangeTarget.max), Number(event.target.value)))
    this.rangeTarget.value = value
    this.numberTarget.value = value
    if (event.target === this.rangeTarget) this.numberTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
