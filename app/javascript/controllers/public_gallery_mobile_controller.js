import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["primaryImage", "counter", "favorite", "status"]
  static values = { propertyId: Number }

  connect() {
    this.index = 0
    this.links = Array.from(this.element.querySelectorAll('a[data-fancybox="property-gallery"]'))
    this.pointerStart = null
    this.preventNextClick = false
    this.onPointerDown = this.handlePointerDown.bind(this)
    this.onPointerUp = this.handlePointerUp.bind(this)
    this.onClick = this.handleClick.bind(this)
    this.element.addEventListener("pointerdown", this.onPointerDown, { passive: true })
    this.element.addEventListener("pointerup", this.onPointerUp)
    this.element.addEventListener("pointercancel", this.onPointerUp)
    this.element.addEventListener("click", this.onClick, true)
    this.restoreFavorite()
    this.updateControls()
  }

  disconnect() {
    this.element.removeEventListener("pointerdown", this.onPointerDown)
    this.element.removeEventListener("pointerup", this.onPointerUp)
    this.element.removeEventListener("pointercancel", this.onPointerUp)
    this.element.removeEventListener("click", this.onClick, true)
  }

  handlePointerDown(event) {
    if (!event.isPrimary || event.pointerType === "mouse") return

    this.pointerStart = { x: event.clientX, y: event.clientY }
  }

  handlePointerUp(event) {
    if (!this.pointerStart || !event.isPrimary) return

    const deltaX = event.clientX - this.pointerStart.x
    const deltaY = event.clientY - this.pointerStart.y
    this.pointerStart = null

    if (Math.abs(deltaX) < 40 || Math.abs(deltaX) <= Math.abs(deltaY)) return

    this.preventNextClick = true
    if (deltaX < 0) {
      this.next()
    } else {
      this.previous()
    }
  }

  handleClick(event) {
    if (!this.preventNextClick) return

    this.preventNextClick = false
    event.preventDefault()
    event.stopPropagation()
  }

  previous() {
    this.index = (this.index - 1 + this.links.length) % this.links.length
    this.updatePrimaryImage()
  }

  next() {
    this.index = (this.index + 1) % this.links.length
    this.updatePrimaryImage()
  }

  updatePrimaryImage() {
    const link = this.links[this.index]
    if (!link || !this.hasPrimaryImageTarget) return

    const imageSrc = link.dataset.publicGalleryMobileSrc || link.href
    const imageSrcset = link.dataset.publicGalleryMobileSrcset
    const imageSizes = link.dataset.publicGalleryMobileSizes
    const imageClass = link.dataset.publicGalleryMobileClass
    const imageStyle = link.dataset.publicGalleryMobileStyle

    if (imageSrcset) {
      this.primaryImageTarget.srcset = imageSrcset
    } else {
      this.primaryImageTarget.removeAttribute("srcset")
    }

    if (imageSizes) {
      this.primaryImageTarget.sizes = imageSizes
    } else {
      this.primaryImageTarget.removeAttribute("sizes")
    }

    this.primaryImageTarget.src = imageSrc
    this.primaryImageTarget.alt = link.dataset.caption || this.primaryImageTarget.alt
    this.applyPrimaryImageClass(imageClass)
    this.applyPrimaryImageStyle(imageStyle)
    this.updateControls()
  }

  applyPrimaryImageClass(imageClass) {
    if (!imageClass) return

    Array.from(this.primaryImageTarget.classList)
      .filter((className) => className.startsWith("public-habitations-show__gallery-image"))
      .forEach((className) => this.primaryImageTarget.classList.remove(className))

    imageClass.split(/\s+/).filter(Boolean).forEach((className) => {
      this.primaryImageTarget.classList.add(className)
    })
  }

  applyPrimaryImageStyle(imageStyle) {
    this.primaryImageTarget.style.removeProperty("--public-gallery-object-position-y")
    if (!imageStyle) return

    const match = imageStyle.match(/--public-gallery-object-position-y\s*:\s*([^;]+)/)
    if (match) this.primaryImageTarget.style.setProperty("--public-gallery-object-position-y", match[1].trim())
  }

  updateControls() {
    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `${this.index + 1} / ${this.links.length}`
    }
  }

  toggleFavorite() {
    const favorites = this.readFavorites()
    const property = this.propertyData()
    const index = favorites.findIndex((favorite) => favorite.id === property.id)
    const active = index >= 0

    if (active) {
      favorites.splice(index, 1)
    } else {
      favorites.unshift(property)
    }

    localStorage.setItem("salute:favorite-properties", JSON.stringify(favorites))
    this.setFavoriteState(!active)
    window.dispatchEvent(new CustomEvent("salute:favorites-changed"))
  }

  share() {
    const shareData = { title: document.title, url: window.location.href }
    if (navigator.share) {
      navigator.share(shareData).catch(() => {})
      return
    }

    if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(window.location.href)
        .then(() => this.showStatus("Link copiado"))
        .catch(() => this.copyWithFallback())
      return
    }

    this.copyWithFallback()
  }

  restoreFavorite() {
    const propertyId = this.propertyData().id
    this.setFavoriteState(this.readFavorites().some((favorite) => favorite.id === propertyId))
  }

  setFavoriteState(active) {
    if (!this.hasFavoriteTarget) return

    this.favoriteTarget.setAttribute("aria-pressed", String(active))
    this.favoriteTarget.classList.toggle("is-active", active)
    this.favoriteTarget.querySelector("i")?.classList.toggle("bi-bookmark-fill", active)
    this.favoriteTarget.querySelector("i")?.classList.toggle("bi-bookmark", !active)
  }

  propertyData() {
    const dataset = this.element.dataset
    return {
      id: dataset.publicGalleryMobilePropertyIdValue,
      url: dataset.publicGalleryMobilePropertyUrlValue,
      title: dataset.publicGalleryMobilePropertyTitleValue,
      imageUrl: dataset.publicGalleryMobilePropertyImageUrlValue,
      price: dataset.publicGalleryMobilePropertyPriceValue,
      location: dataset.publicGalleryMobilePropertyLocationValue
    }
  }

  readFavorites() {
    try {
      const favorites = JSON.parse(localStorage.getItem("salute:favorite-properties") || "[]")
      return Array.isArray(favorites) ? favorites : []
    } catch (_error) {
      return []
    }
  }

  showStatus(message) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
    window.clearTimeout(this.statusTimeout)
    this.statusTimeout = window.setTimeout(() => {
      this.statusTarget.textContent = ""
    }, 1800)
  }

  copyWithFallback() {
    const input = document.createElement("textarea")
    input.value = window.location.href
    input.setAttribute("readonly", "")
    input.style.position = "fixed"
    input.style.opacity = "0"
    document.body.appendChild(input)
    input.select()

    let copied = false
    try {
      copied = document.execCommand("copy")
    } catch (_error) {
      copied = false
    }

    input.remove()
    this.showStatus(copied ? "Link copiado" : "Copie o link desta página")
  }
}
