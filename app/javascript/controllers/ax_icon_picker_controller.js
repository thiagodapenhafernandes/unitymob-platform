import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview"]
  choose(event) {
    this.inputTarget.value = event.currentTarget.dataset.icon
    this.previewTarget.className = `bi bi-${this.inputTarget.value || "slash-circle"}`
    this.element.querySelector("details").open = false
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }
  filter(event) {
    const query = event.target.value.toLocaleLowerCase("pt-BR")
    this.element.querySelectorAll("[data-icon]").forEach((button) => { button.hidden = !button.dataset.search.includes(query) })
  }
}
