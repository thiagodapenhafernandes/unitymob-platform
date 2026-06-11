import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "button"]

  toggle(event) {
    event.preventDefault()
    this.contentTarget.classList.toggle("show")

    const expanded = this.contentTarget.classList.contains("show")

    this.buttonTargets.forEach((button) => {
      button.classList.toggle("collapsed", !expanded)
      button.setAttribute("aria-expanded", expanded)
    })
  }
}
