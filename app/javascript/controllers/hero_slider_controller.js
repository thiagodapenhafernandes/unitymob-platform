import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "slide" ]
  static values = {
    interval: Number
  }

  connect() {
    this.index = 0
    if (this.slideTargets.length <= 1) return

    this.startInterval()
  }

  disconnect() {
    this.stopInterval()
  }

  startInterval() {
    this.timer = setInterval(() => {
      this.next()
    }, this.intervalValue || 8000)
  }

  stopInterval() {
    if (this.timer) clearInterval(this.timer)
  }

  next() {
    if (this.slideTargets.length <= 1) return

    this.slideTargets[this.index].classList.remove("active")
    this.index = (this.index + 1) % this.slideTargets.length
    this.slideTargets[this.index].classList.add("active")
  }
}
