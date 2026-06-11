import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["template", "container"]

  connect() {
    this.updatePositions()
  }

  add(event) {
    event.preventDefault()
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime())
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
    const fields = this.containerTarget.querySelectorAll(".nested-fields:not([style*='display: none'])")
    fields.forEach((field, index) => {
      const positionLabel = field.querySelector("[data-position-label]")
      if (positionLabel) {
        positionLabel.textContent = index + 1
      }

      const positionInput = field.querySelector("input[name*='position']")
      if (positionInput) {
        positionInput.value = index + 1
      }
    })
  }
}
