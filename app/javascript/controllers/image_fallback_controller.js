import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    containerSelector: String,
    fallbackUrls: Array,
    index: { type: Number, default: 0 }
  }

  hide(event) {
    const image = event.currentTarget
    const nextUrl = this.nextFallbackUrl(image)

    if (nextUrl) {
      image.hidden = false
      image.src = nextUrl
      this.container?.classList.remove("is-image-missing")
      return
    }

    image.hidden = true

    this.container?.classList.add("is-image-missing")
  }

  nextFallbackUrl(image) {
    if (!this.hasFallbackUrlsValue) return null

    const currentUrl = image.currentSrc || image.src
    const urls = this.fallbackUrlsValue.filter((url) => url)

    while (this.indexValue < urls.length && urls[this.indexValue] === currentUrl) {
      this.indexValue += 1
    }

    if (this.indexValue >= urls.length) return null
    const nextUrl = urls[this.indexValue]
    this.indexValue += 1
    return nextUrl
  }

  get container() {
    return this.hasContainerSelectorValue ? this.element.closest(this.containerSelectorValue) : this.element.parentElement
  }
}
