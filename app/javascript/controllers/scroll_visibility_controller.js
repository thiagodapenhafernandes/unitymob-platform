import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="scroll-visibility"
export default class extends Controller {
  static classes = ["hidden"]

  connect() {
    this.onScroll = this.onScroll.bind(this)
    window.addEventListener("scroll", this.onScroll)
    this.onScroll() // Initial check
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
  }

  onScroll() {
    // Show button after scrolling down 200px (approx height of header + filter bar)
    if (window.scrollY > 200) {
      this.element.classList.remove(...this.hiddenClasses)
    } else {
      this.element.classList.add(...this.hiddenClasses)
    }
  }
}
