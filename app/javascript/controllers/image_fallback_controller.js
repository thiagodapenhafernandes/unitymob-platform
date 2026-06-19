import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    containerSelector: String
  }

  hide(event) {
    const image = event.currentTarget
    image.hidden = true

    const container = this.hasContainerSelectorValue ? image.closest(this.containerSelectorValue) : image.parentElement
    container?.classList.add("is-image-missing")
  }
}
