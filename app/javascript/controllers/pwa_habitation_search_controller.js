import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { delay: { type: Number, default: 650 } }

  connect() {
    this.timeout = null
    this.lastSubmittedValue = this.inputValue
  }

  disconnect() {
    this.clearTimer()
  }

  schedule() {
    this.clearTimer()
    this.timeout = window.setTimeout(() => this.submit(), this.delayValue)
  }

  submitOnEnter(event) {
    if (event.key !== "Enter") return

    event.preventDefault()
    this.clearTimer()
    this.submit()
  }

  submit() {
    const value = this.inputValue
    if (value === this.lastSubmittedValue) return

    this.lastSubmittedValue = value
    if (typeof this.element.requestSubmit === "function") {
      this.element.requestSubmit()
    } else {
      this.element.submit()
    }
  }

  clearTimer() {
    if (!this.timeout) return

    window.clearTimeout(this.timeout)
    this.timeout = null
  }

  get inputValue() {
    return this.hasInputTarget ? this.inputTarget.value.trim() : ""
  }
}
