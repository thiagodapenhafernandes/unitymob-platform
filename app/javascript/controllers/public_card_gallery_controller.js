import { Controller } from "@hotwired/stimulus"

const PLACEHOLDER_SRC = "data:image/gif"
const SWIPE_THRESHOLD_PX = 34
const CLICK_GUARD_MS = 450

export default class extends Controller {
  static targets = ["frame", "image", "indicator"]
  static values = { index: Number }

  connect() {
    this.show(this.indexValue || 0)
    this.resetSwipe()
  }

  next(event) {
    this.keepInside(event)
    this.warm()
    this.show(this.indexValue + 1)
  }

  previous(event) {
    this.keepInside(event)
    this.warm()
    this.show(this.indexValue - 1)
  }

  startSwipe(event) {
    if (!this.canSwipe(event)) return

    const point = this.eventPoint(event)
    if (!point) return

    this.swipePointerId = this.eventIdentifier(event)
    this.swipeStartX = point.clientX
    this.swipeStartY = point.clientY
    this.swipeActive = true
    this.swipeHandled = false
  }

  moveSwipe(event) {
    if (!this.swipeActive || this.eventIdentifier(event) !== this.swipePointerId || this.swipeHandled) return

    const point = this.eventPoint(event)
    if (!point) return

    const deltaX = point.clientX - this.swipeStartX
    const deltaY = point.clientY - this.swipeStartY

    if (Math.abs(deltaX) < SWIPE_THRESHOLD_PX || Math.abs(deltaX) <= Math.abs(deltaY)) return

    event.preventDefault()
    this.markCarouselInteraction(event)
    this.warm()
    this.show(deltaX < 0 ? this.indexValue + 1 : this.indexValue - 1)
    this.swipeHandled = true
  }

  endSwipe(event) {
    if (this.swipeHandled) this.markCarouselInteraction(event)
    this.resetSwipe()
  }

  cancelSwipe() {
    this.resetSwipe()
  }

  warm() {
    this.imageTargets.forEach((image) => {
      if (image.dataset.loaded === "true") return

      const src = image.dataset.src
      const srcset = image.dataset.srcset

      if (srcset) image.srcset = srcset
      if (src && image.src.startsWith(PLACEHOLDER_SRC)) image.src = src

      image.dataset.loaded = "true"
    })
  }

  show(index) {
    if (!this.hasFrameTarget) return

    const total = this.frameTargets.length
    const nextIndex = (index + total) % total

    this.indexValue = nextIndex
    this.frameTargets.forEach((frame, frameIndex) => {
      const active = frameIndex === nextIndex
      frame.classList.toggle("is-active", active)
      frame.setAttribute("aria-hidden", active ? "false" : "true")
    })

    if (this.hasIndicatorTarget) {
      this.indicatorTargets.forEach((indicator, indicatorIndex) => {
        indicator.classList.toggle("is-active", indicatorIndex === nextIndex)
      })
    }
  }

  keepInside(event) {
    if (!event) return

    event.preventDefault()
    event.stopPropagation()

    this.markCarouselInteraction(event)
  }

  canSwipe(event) {
    if (event.pointerType && event.isPrimary === false) return false
    if (event.touches && event.touches.length !== 1) return false
    if (event.target.closest("a, button, input, select, textarea, label")) return false

    return this.frameTargets.length > 1
  }

  eventPoint(event) {
    return event.touches?.[0] || event.changedTouches?.[0] || event
  }

  eventIdentifier(event) {
    return event.pointerId || event.touches?.[0]?.identifier || event.changedTouches?.[0]?.identifier || "mouse"
  }

  markCarouselInteraction(event) {
    const card = event.target.closest("[data-clickable-card-target='card'], .clickable-card, article")
    if (!card) return

    card.dataset.clickableCardCarouselInteraction = "true"
    window.clearTimeout(card.publicCardGalleryClickGuardTimeout)
    card.publicCardGalleryClickGuardTimeout = window.setTimeout(() => {
      delete card.dataset.clickableCardCarouselInteraction
    }, CLICK_GUARD_MS)
  }

  resetSwipe() {
    this.swipePointerId = null
    this.swipeStartX = 0
    this.swipeStartY = 0
    this.swipeActive = false
    this.swipeHandled = false
  }
}
