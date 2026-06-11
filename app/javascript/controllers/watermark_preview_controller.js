import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "fileInput",
    "frame",
    "logo",
    "opacityInput",
    "opacityValue",
    "placeholder",
    "positionInput",
    "sizeInput",
    "sizeValue"
  ]

  connect() {
    this.update()
  }

  disconnect() {
    this.revokePreviewUrl()
  }

  update() {
    this.updatePosition()
    this.updateSize()
    this.updateOpacity()
  }

  loadFile() {
    if (!this.hasFileInputTarget || !this.hasLogoTarget) return

    const file = this.fileInputTarget.files[0]
    if (!file) return

    this.revokePreviewUrl()
    this.previewUrl = URL.createObjectURL(file)
    this.logoTarget.src = this.previewUrl
    this.logoTarget.classList.remove("d-none")

    if (this.hasPlaceholderTarget) {
      this.placeholderTarget.classList.add("d-none")
    }

    this.update()
  }

  updatePosition() {
    if (!this.hasLogoTarget) return

    const selected = this.positionInputTargets.find((input) => input.checked)
    if (!selected) return

    this.logoTarget.classList.remove(
      "watermark-position-bottom_left",
      "watermark-position-bottom_right",
      "watermark-position-center"
    )
    this.logoTarget.classList.add(`watermark-position-${selected.value}`)
  }

  updateSize() {
    if (!this.hasSizeInputTarget || !this.hasFrameTarget) return

    const size = this.sizeInputTarget.value
    this.frameTarget.style.setProperty("--watermark-size", `${size}%`)

    if (this.hasLogoTarget) {
      this.logoTarget.style.width = `${size}%`
    }

    if (this.hasSizeValueTarget) {
      this.sizeValueTarget.textContent = `${size}%`
    }
  }

  updateOpacity() {
    if (!this.hasOpacityInputTarget || !this.hasFrameTarget) return

    const opacity = this.opacityInputTarget.value
    this.frameTarget.style.setProperty("--watermark-opacity", opacity / 100)

    if (this.hasLogoTarget) {
      this.logoTarget.style.opacity = opacity / 100
    }

    if (this.hasOpacityValueTarget) {
      this.opacityValueTarget.textContent = `${opacity}%`
    }
  }

  revokePreviewUrl() {
    if (!this.previewUrl) return

    URL.revokeObjectURL(this.previewUrl)
    this.previewUrl = null
  }
}
