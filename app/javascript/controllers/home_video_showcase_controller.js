import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card", "chip", "dialog", "media", "progress", "title", "location", "price", "propertyLink"]

  connect() {
    this.currentIndex = 0
    this.activeCity = ""
    this.onKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.onKeydown)
    this.dialogTarget.addEventListener("close", () => this.clearMedia())
    this.dialogTarget.addEventListener("click", (event) => {
      if (event.target === this.dialogTarget) this.dialogTarget.close()
    })
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    this.clearMedia()
  }

  filter(event) {
    this.activeCity = event.params.city || ""

    this.chipTargets.forEach((chip) => {
      chip.classList.toggle("is-active", (chip.dataset.homeVideoShowcaseCityParam || "") === this.activeCity)
    })

    this.cardTargets.forEach((card) => {
      card.hidden = this.activeCity !== "" && card.dataset.city !== this.activeCity
    })
  }

  open(event) {
    this.show(Number.parseInt(event.params.index, 10) || 0)
  }

  next() {
    this.showRelative(1)
  }

  previous() {
    this.showRelative(-1)
  }

  handleKeydown(event) {
    if (!this.dialogTarget.open) return

    if (event.key === "ArrowRight") {
      event.preventDefault()
      this.next()
    } else if (event.key === "ArrowLeft") {
      event.preventDefault()
      this.previous()
    }
  }

  showRelative(step) {
    const indexes = this.visibleIndexes()
    if (indexes.length === 0) return

    const currentPosition = indexes.indexOf(this.currentIndex)
    const nextPosition = currentPosition === -1 ? 0 : (currentPosition + step + indexes.length) % indexes.length
    this.show(indexes[nextPosition])
  }

  show(index) {
    const trigger = this.cardTargets[index]?.querySelector(".home-video-card__trigger")
    if (!trigger) return

    this.currentIndex = index
    this.titleTarget.textContent = trigger.dataset.title || "Vídeo do imóvel"
    this.locationTarget.textContent = trigger.dataset.location || ""
    this.priceTarget.textContent = trigger.dataset.price || ""
    this.propertyLinkTarget.hidden = !trigger.dataset.propertyUrl
    this.propertyLinkTarget.href = trigger.dataset.propertyUrl || "#"
    this.renderProgress(!trigger.dataset.directUrl)
    this.renderMedia(trigger)

    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  visibleIndexes() {
    return this.cardTargets
      .map((card, index) => card.hidden ? null : index)
      .filter((index) => index !== null)
  }

  renderMedia(trigger) {
    this.clearMedia()

    if (trigger.dataset.embedUrl) {
      if (trigger.dataset.poster) this.mediaTarget.appendChild(this.posterFor(trigger))
      const iframe = document.createElement("iframe")
      iframe.src = this.autoplayUrl(trigger.dataset.embedUrl, trigger.dataset.provider)
      iframe.title = trigger.dataset.title || "Vídeo do imóvel"
      iframe.allow = "autoplay; fullscreen; picture-in-picture"
      iframe.allowFullscreen = true
      this.mediaTarget.appendChild(iframe)
      return
    }

    if (trigger.dataset.directUrl) {
      const video = document.createElement("video")
      video.controls = false
      video.autoplay = true
      video.muted = false
      video.playsInline = true
      video.preload = "auto"
      if (trigger.dataset.poster) video.poster = trigger.dataset.poster
      video.addEventListener("timeupdate", () => this.updateCurrentProgress(video))
      video.addEventListener("ended", () => this.next())

      const source = document.createElement("source")
      source.src = trigger.dataset.directUrl
      if (trigger.dataset.contentType) source.type = trigger.dataset.contentType
      video.appendChild(source)
      this.mediaTarget.appendChild(video)
      video.play().catch(() => {})
    }
  }

  clearMedia() {
    if (this.hasMediaTarget) this.mediaTarget.replaceChildren()
  }

  renderProgress(completeCurrent = false) {
    if (!this.hasProgressTarget) return

    const indexes = this.visibleIndexes()
    this.progressTarget.replaceChildren(...indexes.map((index) => {
      const track = document.createElement("span")
      if (index < this.currentIndex) track.classList.add("is-complete")
      if (index === this.currentIndex) track.classList.add("is-current")
      const fill = document.createElement("i")
      if (index === this.currentIndex && completeCurrent) fill.style.setProperty("--progress", "100%")
      track.appendChild(fill)
      return track
    }))
  }

  updateCurrentProgress(video) {
    const bar = this.progressTarget?.querySelector(".is-current i")
    if (!bar || !Number.isFinite(video.duration) || video.duration <= 0) return

    bar.style.setProperty("--progress", `${Math.min(100, (video.currentTime / video.duration) * 100)}%`)
  }

  autoplayUrl(url, provider) {
    const parsedUrl = new URL(url, window.location.href)
    parsedUrl.searchParams.set("autoplay", "1")
    parsedUrl.searchParams.set("playsinline", "1")
    if (provider === "youtube") {
      parsedUrl.searchParams.set("controls", "0")
      parsedUrl.searchParams.set("rel", "0")
    } else if (provider === "vimeo") {
      parsedUrl.searchParams.set("controls", "0")
    }
    return parsedUrl.toString()
  }

  posterFor(trigger) {
    const poster = document.createElement("img")
    poster.src = trigger.dataset.poster
    poster.alt = ""
    poster.className = "home-video-modal__poster"
    poster.setAttribute("aria-hidden", "true")
    return poster
  }
}
