import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = {
    fallback: String
  }

  connect() {
    this.sync()
  }

  sync() {
    if (!this.hasInputTarget) return

    const hash = window.location.hash?.replace(/^#/, "")
    this.inputTarget.value = hash || this.fallbackValue || ""
  }
}
