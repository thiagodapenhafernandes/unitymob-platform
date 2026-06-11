import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image", "indicator"]
  static values = {
    currentIndex: { type: Number, default: 0 },
    images: Array
  }

  connect() {
    if (this.hasImageTarget) {
      this.showImage(0)
    }
  }

  next(event) {
    event.preventDefault()
    event.stopPropagation()

    const nextIndex = (this.currentIndexValue + 1) % this.imageTargets.length
    this.showImage(nextIndex)
  }

  previous(event) {
    event.preventDefault()
    event.stopPropagation()

    const prevIndex = this.currentIndexValue === 0
      ? this.imageTargets.length - 1
      : this.currentIndexValue - 1
    this.showImage(prevIndex)
  }

  goTo(event) {
    event.preventDefault()
    event.stopPropagation()

    const index = parseInt(event.currentTarget.dataset.index)
    this.showImage(index)
  }

  showImage(index) {
    // Hide all images
    this.imageTargets.forEach(img => {
      img.classList.remove('active')
    })

    // Show selected image
    if (this.imageTargets[index]) {
      this.imageTargets[index].classList.add('active')
      this.currentIndexValue = index

      // Update indicators
      if (this.hasIndicatorTarget) {
        this.indicatorTargets.forEach((indicator, i) => {
          indicator.classList.toggle('active', i === index)
        })
      }
    }
  }
}
