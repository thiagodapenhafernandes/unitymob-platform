import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["scroller", "item", "previous", "next"]

  connect() {
    this.update = this.update.bind(this)
    this.queuedUpdate()
  }

  previous(event) {
    event?.preventDefault()
    this.move(-1)
  }

  next(event) {
    event?.preventDefault()
    this.move(1)
  }

  update() {
    if (!this.hasScrollerTarget) return

    const scroller = this.scrollerTarget
    const maxScroll = Math.max(scroller.scrollWidth - scroller.clientWidth, 0)
    const hasOverflow = maxScroll > 2
    const atStart = scroller.scrollLeft <= 2
    const atEnd = scroller.scrollLeft >= maxScroll - 2

    this.toggleTargets(this.previousTargets, hasOverflow && !atStart)
    this.toggleTargets(this.nextTargets, hasOverflow && !atEnd)
    this.element.classList.toggle("is-overflowing", hasOverflow)
  }

  move(direction) {
    if (!this.hasScrollerTarget) return

    const scroller = this.scrollerTarget
    const currentLeft = scroller.scrollLeft
    const items = this.itemTargets.length ? this.itemTargets : Array.from(scroller.children)
    const visibleItems = items.filter((item) => item.offsetParent !== null)
    const nextItem = direction > 0
      ? visibleItems.find((item) => item.offsetLeft > currentLeft + 4)
      : visibleItems.reverse().find((item) => item.offsetLeft < currentLeft - 4)

    const left = nextItem ? nextItem.offsetLeft : currentLeft + (direction * scroller.clientWidth * 0.8)
    scroller.scrollTo({ left: Math.max(left, 0), behavior: "smooth" })
    window.setTimeout(this.update, 260)
  }

  queuedUpdate() {
    requestAnimationFrame(this.update)
    window.setTimeout(this.update, 80)
  }

  toggleTargets(targets, visible) {
    targets.forEach((target) => {
      target.hidden = !visible
      target.setAttribute("aria-disabled", visible ? "false" : "true")
    })
  }
}
