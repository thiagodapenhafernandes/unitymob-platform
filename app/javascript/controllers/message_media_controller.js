import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["media"]
  static values = { auto: Boolean }

  connect() {
    if (!this.hasMediaTarget) return
    const media = this.mediaTarget
    if ((media.tagName === "IMG" && media.complete && !media.naturalWidth) || media.error) {
      this.failed({ currentTarget: media })
    }
  }

  failed({ currentTarget: media }) {
    if (this.autoValue && media.tagName === "IMG") {
      // Story URLs do not identify whether the media is an image or a video.
      const video = document.createElement("video")
      video.className = media.className
      video.controls = true
      video.playsInline = true
      video.preload = "metadata"
      video.dataset.messageMediaTarget = "media"
      video.addEventListener("error", () => this.unavailable(video), { once: true })
      video.src = media.currentSrc || media.src
      media.replaceWith(video)
      return
    }
    this.unavailable(media)
  }

  unavailable(media) {
    media.hidden = true
    this.element.classList.add("is-image-missing")
  }
}
