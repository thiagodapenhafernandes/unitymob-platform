import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="tag-input"
export default class extends Controller {
  static targets = ["input", "container", "template"]

  // The 'input' target is the hidden field storing the JSON data
  // The 'container' is where the tag badges are rendered

  connect() {
    this.tags = new Set()

    // Load initial values
    try {
      const initialValue = JSON.parse(this.inputTarget.value || "{}")
      // We assume the JSON is something like { "0": "tag1", "1": "tag2" } or ["tag1", "tag2"]
      // Actually, for 'caracteristicas' it's usually just keys or values. 
      // Let's assume the Rails side stores it as a hash or array. 
      // If schema says default {}, it might be a key-value store.
      // But typically for "Tags", we might just want to store keys or values.
      // Let's support an Array-like structure or Object keys.

      const values = Array.isArray(initialValue) ? initialValue : Object.values(initialValue)
      values.forEach(tag => this.addTag(tag))
    } catch (e) {
      console.error("Error parsing tag input", e)
    }
  }

  add(event) {
    if (event.key === "Enter" || event.key === ",") {
      event.preventDefault()
      const value = event.target.value.trim()
      if (value) {
        this.addTag(value)
        event.target.value = ""
        this.updateInput()
      }
    }
  }

  addClick() {
    const input = this.element.querySelector('input[type="text"]')
    const value = input.value.trim()
    if (value) {
      this.addTag(value)
      input.value = ""
      this.updateInput()
    }
  }

  remove(event) {
    const tag = event.target.closest(".badge").dataset.tagValue
    this.deleteTag(tag)
    this.updateInput()
  }

  addTag(tag) {
    if (this.tags.has(tag)) return

    this.tags.add(tag)

    const badge = document.createElement("span")
    badge.className = "badge bg-light text-dark border me-1 mb-1 p-2 d-inline-flex align-items-center"
    badge.dataset.tagValue = tag
    badge.innerHTML = `
      ${tag}
      <i class="bi bi-x ms-2 cursor-pointer text-danger" data-action="click->tag-input#remove"></i>
    `
    this.containerTarget.appendChild(badge)
  }

  deleteTag(tag) {
    this.tags.delete(tag)
    // Remove element
    const badge = this.containerTarget.querySelector(`[data-tag-value="${tag}"]`)
    if (badge) badge.remove()
  }

  updateInput() {
    // Current requirement: Store as JSON object or Array?
    // Schema says default {}. Let's store as Object { "0": "val", "1": "val" } to be safe 
    // OR just an array if Rails handles casting seamlessly. 
    // Given the previous usage, it might be safer to store as Array and Rails casts to jsonb.
    this.inputTarget.value = JSON.stringify(Array.from(this.tags))
  }
}
