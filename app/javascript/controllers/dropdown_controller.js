import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.closeBinding = this.closeExternal.bind(this)
    document.addEventListener("click", this.closeBinding)
  }

  disconnect() {
    document.removeEventListener("click", this.closeBinding)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    this.menuTarget.classList.toggle("show")
    this.element.querySelector('.dropdown-toggle').classList.toggle("show")

    const expanded = this.menuTarget.classList.contains("show")
    this.element.querySelector('.dropdown-toggle').setAttribute("aria-expanded", expanded)
  }

  closeExternal(event) {
    if (!this.element.contains(event.target)) {
      this.menuTarget.classList.remove("show")
      this.element.querySelector('.dropdown-toggle').classList.remove("show")
      this.element.querySelector('.dropdown-toggle').setAttribute("aria-expanded", "false")
    }
  }
}
