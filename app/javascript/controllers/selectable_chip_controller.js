import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  sync(event) {
    this.element.classList.toggle("selected", event.target.checked)
  }
}
