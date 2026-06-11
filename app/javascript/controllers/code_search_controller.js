import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  connect() {
    // Listen for global event to open modal
    document.addEventListener('open-code-search', this.open.bind(this))
  }

  disconnect() {
    document.removeEventListener('open-code-search', this.open.bind(this))
  }

  open(e) {
    if (e) e.preventDefault()
    this.element.classList.remove('hidden')
    this.inputTarget.focus()
  }

  close(e) {
    if (e) e.preventDefault()
    this.element.classList.add('hidden')
  }
}
