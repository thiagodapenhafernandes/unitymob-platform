import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["track", "previousButton", "nextButton", "indicator"]
  static values = { index: Number }

  connect() {
    this.reposition = this.reposition.bind(this)
    window.addEventListener("resize", this.reposition)
    this.show(this.indexValue || 0)
  }

  disconnect() {
    window.removeEventListener("resize", this.reposition)
  }

  next(event) {
    this.keepInside(event)
    this.show(this.indexValue + 1)
  }

  previous(event) {
    this.keepInside(event)
    this.show(this.indexValue - 1)
  }

  show(index) {
    if (!this.hasTrackTarget) return

    const pageCount = this.pageCount
    const nextIndex = Math.max(0, Math.min(index, pageCount - 1))

    this.indexValue = nextIndex
    this.moveTo(nextIndex)
    this.loadPageMedia(nextIndex)

    if (this.hasPreviousButtonTarget) this.previousButtonTarget.disabled = nextIndex === 0
    if (this.hasNextButtonTarget) this.nextButtonTarget.disabled = nextIndex >= pageCount - 1
    if (this.hasIndicatorTarget) this.indicatorTarget.textContent = `${nextIndex + 1}/${pageCount}`
  }

  get pageCount() {
    return this.trackTarget.children.length || 1
  }

  moveTo(index) {
    const page = this.trackTarget.children[index]
    const offset = page?.offsetLeft || 0

    this.trackTarget.style.transform = `translate3d(-${offset}px, 0, 0)`
  }

  reposition() {
    this.moveTo(this.indexValue || 0)
  }

  keepInside(event) {
    if (!event) return

    event.preventDefault()
    event.stopPropagation()
  }

  loadPageMedia(index) {
    const page = this.trackTarget.children[index]
    if (!page) return

    page.querySelectorAll("[data-public-deferred='true']").forEach((image) => {
      if (image.dataset.loaded === "true") return

      if (image.dataset.srcset) image.srcset = image.dataset.srcset
      if (image.dataset.src) image.src = image.dataset.src
      image.dataset.loaded = "true"
    })
  }
}
