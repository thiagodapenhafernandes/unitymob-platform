import { Controller } from "@hotwired/stimulus"

// Native scrolling stays usable with touch/keyboard and without JavaScript.
export default class extends Controller {
  static targets = ["track"]

  move(event) {
    const direction = Number(event.currentTarget.dataset.direction)
    this.trackTarget.scrollBy({
      left: direction * this.trackTarget.clientWidth,
      behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"
    })
  }
}
