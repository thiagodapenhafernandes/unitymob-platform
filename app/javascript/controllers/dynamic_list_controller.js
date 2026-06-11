import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="dynamic-list"
export default class extends Controller {
  static targets = ["container", "input", "template"]
  static values = { paramName: String }

  add(event) {
    if (event) event.preventDefault()

    // If we have an input target (the "add new" input), use its value
    let value = ""
    if (this.hasInputTarget) {
      value = this.inputTarget.value
      if (!value) return // Don't add empty
      this.inputTarget.value = "" // Clear input
    }

    // Create the item
    const wrapper = document.createElement('div')
    wrapper.classList.add('input-group', 'mb-2')

    // Use template if exists, otherwise default simple input
    if (this.hasTemplateTarget) {
      const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime())
      wrapper.innerHTML = content
      // Set value if we have one
      const input = wrapper.querySelector('input')
      if (input && value) input.value = value
    } else {
      // Default implementation for simple strings (like video URLs)
      // Name attribute should be passed via data-dynamic-list-param-name-value
      const paramName = this.paramNameValue || 'items[]'
      wrapper.innerHTML = `
         <input type="text" name="${paramName}" value="${value}" class="form-control" placeholder="https://...">
         <button type="button" class="btn btn-outline-danger" data-action="dynamic-list#remove">
           <i class="bi bi-trash"></i>
         </button>
       `
    }

    this.containerTarget.appendChild(wrapper)
  }

  remove(event) {
    event.preventDefault()
    const item = event.target.closest('.input-group')
    if (item) item.remove()
  }
}
