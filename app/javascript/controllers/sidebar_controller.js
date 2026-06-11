import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["backdrop", "content"]

  connect() {
    // Optional: Close on escape key
    document.addEventListener('keydown', this.handleKeydown.bind(this))
  }

  disconnect() {
    document.removeEventListener('keydown', this.handleKeydown.bind(this))
  }

  toggle() {
    if (this.backdropTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.backdropTarget.classList.remove("hidden")
    // Small delay to allow display:block to apply before transition
    setTimeout(() => {
      this.contentTarget.classList.remove("translate-x-full")
    }, 10)
    document.body.style.overflow = "hidden"
  }

  close() {
    this.contentTarget.classList.add("translate-x-full")
    // Wait for transition to finish before hiding backdrop
    setTimeout(() => {
      this.backdropTarget.classList.add("hidden")
    }, 300)
    document.body.style.overflow = ""
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }
}
