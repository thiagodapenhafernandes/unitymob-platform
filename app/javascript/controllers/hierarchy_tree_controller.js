import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle(event) {
    const button = event.target.closest("[data-hier-toggle]")
    if (!button || !this.element.contains(button)) return

    event.preventDefault()
    this.setBranch(button, !this.branchOpen(button))
  }

  expandAll(event) {
    event.preventDefault()
    this.toggleButtons.forEach((button) => this.setBranch(button, true))
  }

  collapseAll(event) {
    event.preventDefault()
    this.toggleButtons.forEach((button) => this.setBranch(button, false))
  }

  setBranch(button, open) {
    if (button.hasAttribute("data-hier-leaf")) return

    const children = button.closest("[data-hierarchy-node]")?.querySelector(":scope > .hier-children")
    if (!children || children.children.length === 0) return

    children.hidden = !open
    button.setAttribute("aria-expanded", String(open))
  }

  branchOpen(button) {
    const children = button.closest("[data-hierarchy-node]")?.querySelector(":scope > .hier-children")
    return children ? !children.hidden : false
  }

  get toggleButtons() {
    return Array.from(this.element.querySelectorAll("[data-hier-toggle]:not([data-hier-leaf])"))
  }
}
