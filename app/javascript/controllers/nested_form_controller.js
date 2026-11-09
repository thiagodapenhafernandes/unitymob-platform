import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["template", "container"]
  static values = { placeholder: { type: String, default: "NEW_RECORD" } }

  connect() {
    this.updatePositions()
  }

  add(event) {
    event.preventDefault()
    const content = this.templateTarget.innerHTML.split(this.placeholderValue).join(new Date().getTime())
    this.containerTarget.insertAdjacentHTML('beforeend', content)
    this.updatePositions()
  }

  remove(event) {
    event.preventDefault()
    const wrapper = event.currentTarget.closest(".nested-fields")
    if (!wrapper) return

    if (wrapper.dataset.newRecord === "true") {
      wrapper.remove()
    } else {
      const destroyInput = wrapper.querySelector("input[name*='_destroy']")
      if (destroyInput) destroyInput.value = "1"
      wrapper.style.display = "none"
    }
    this.updatePositions()
  }

  moveUp(event) {
    event.preventDefault()
    const wrapper = event.currentTarget.closest(".nested-fields")
    const previous = wrapper.previousElementSibling
    if (previous) {
      wrapper.parentNode.insertBefore(wrapper, previous)
      this.updatePositions()
    }
  }

  moveDown(event) {
    event.preventDefault()
    const wrapper = event.currentTarget.closest(".nested-fields")
    const next = wrapper.nextElementSibling
    if (next) {
      wrapper.parentNode.insertBefore(next, wrapper)
      this.updatePositions()
    }
  }

  updatePositions() {
    const fields = Array.from(this.containerTarget.querySelectorAll(".nested-fields:not([style*='display: none'])"))
      .filter(field => field.closest('[data-controller~="nested-form"]') === this.element)
    fields.forEach((field, index) => {
      const positionLabel = field.querySelector("[data-position-label]")
      if (positionLabel) {
        positionLabel.textContent = index + 1
      }

      const positionInput = Array.from(field.querySelectorAll("input[name*='position'], input[name*='display_order']"))
        .find(input => input.closest(".nested-fields") === field)
      if (positionInput) {
        positionInput.value = index + 1
      }
    })
  }
}
