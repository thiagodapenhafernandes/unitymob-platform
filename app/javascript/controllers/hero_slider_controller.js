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

    const nextIndex = (this.index + 1) % this.slideTargets.length
    const nextSlide = this.slideTargets[nextIndex]
    const image = nextSlide.querySelector("[data-hero-slider-image]")

    if (image?.dataset.src) {
      const activate = () => this.activate(nextIndex)
      image.addEventListener("load", activate, { once: true })
      image.src = image.dataset.src
      image.srcset = image.dataset.srcset
      delete image.dataset.src
      delete image.dataset.srcset
      if (image.complete) activate()
      return
    }

    this.activate(nextIndex)
  }

  activate(nextIndex) {
    this.slideTargets[this.index].classList.remove("active")
    this.index = nextIndex
    this.slideTargets[this.index].classList.add("active")
  }
}
