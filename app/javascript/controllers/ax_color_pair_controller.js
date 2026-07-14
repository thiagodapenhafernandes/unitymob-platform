import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["swatch", "text"]

  sync(event) {
    if (!this.hasSwatchTarget || !this.hasTextTarget) return

    if (event.currentTarget === this.swatchTarget) {
      this.textTarget.value = this.swatchTarget.value.toUpperCase()
      return
    }

    const value = this.textTarget.value.trim()
    if (/^#[0-9a-f]{6}$/i.test(value)) this.swatchTarget.value = value
  }
}
