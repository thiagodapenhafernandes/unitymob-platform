import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "dialog"]
  open() { this.pendingIcon = this.inputTarget.value; this.updateSelection(); this.dialogTarget.showModal() }
  close() { this.dialogTarget.close() }
  choose(event) {
    this.pendingIcon = event.currentTarget.dataset.icon
    this.updateSelection()
  }
  updateSelection() {
    this.element.querySelectorAll("[data-icon]").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.icon === this.pendingIcon)))
  }
  apply() {
    this.inputTarget.value = this.pendingIcon
    this.previewTarget.className = `bi bi-${this.inputTarget.value || "slash-circle"}`
    this.close()
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }
  filter(event) {
    const query = event.target.value.toLocaleLowerCase("pt-BR")
    this.element.querySelectorAll("[data-icon]").forEach((button) => { button.hidden = !button.dataset.search.includes(query) })
  }
}
