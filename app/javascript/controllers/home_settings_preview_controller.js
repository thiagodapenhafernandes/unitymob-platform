import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlayColorPicker", "overlayColorText", "overlayOpacity", "overlayPreview"]

  connect() {
    this.updateOverlay()
  }

  syncOverlay(event) {
    const source = event.params.source

    if (source === "picker" && this.hasOverlayColorTextTarget) {
      this.overlayColorTextTarget.value = event.currentTarget.value
    }

    if (source === "text" && this.hasOverlayColorPickerTarget && this.validHex(event.currentTarget.value)) {
      this.overlayColorPickerTarget.value = event.currentTarget.value
    }

    this.updateOverlay()
  }

  updateOverlay() {
    if (!this.hasOverlayPreviewTarget) return

    const color = this.hasOverlayColorTextTarget ? this.overlayColorTextTarget.value : "#000000"
    const opacity = this.hasOverlayOpacityTarget ? this.overlayOpacityTarget.value : "0.7"
    this.overlayPreviewTarget.style.backgroundColor = color
    this.overlayPreviewTarget.style.opacity = opacity
  }

  syncPair(event) {
    const pair = event.params.pair
    const source = event.params.source
    if (!pair) return

    const picker = this.element.querySelector(`[data-home-settings-preview-pair="${pair}"][data-home-settings-preview-source="picker"]`)
    const text = this.element.querySelector(`[data-home-settings-preview-pair="${pair}"][data-home-settings-preview-source="text"]`)

    if (source === "picker" && text) text.value = event.currentTarget.value
    if (source === "text" && picker && this.validHex(event.currentTarget.value)) picker.value = event.currentTarget.value
  }

  validHex(value) {
    return /^#[0-9A-F]{6}$/i.test(value || "")
  }
}
