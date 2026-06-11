import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "panel", "summary", "checkbox", "allCheckbox", "hiddenContainer"]

  connect() {
    this.boundClickOutside = this.clickOutside.bind(this)
    document.addEventListener("click", this.boundClickOutside)
    this.sync()
  }

  disconnect() {
    document.removeEventListener("click", this.boundClickOutside)
    this.unlockBodyScroll()
  }

  toggle(event) {
    event.preventDefault()
    if (this.panelTarget.classList.contains("hidden")) {
      this.openPanel()
    } else {
      this.closePanel()
    }
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.closePanel()
    }
  }

  toggleAll() {
    const shouldCheck = this.allCheckboxTarget.checked
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = shouldCheck
    })
    this.sync()
  }

  sync() {
    const selected = this.checkboxTargets
      .filter((checkbox) => checkbox.checked)
      .map((checkbox) => checkbox.value)

    const allSelected = selected.length === this.checkboxTargets.length && this.checkboxTargets.length > 0
    this.allCheckboxTarget.checked = allSelected
    this.allCheckboxTarget.indeterminate = selected.length > 0 && !allSelected

    if (selected.length === 0) {
      this.summaryTarget.textContent = "Tipos de imóveis"
    } else if (allSelected) {
      this.summaryTarget.textContent = "Todos"
    } else if (selected.length === 1) {
      this.summaryTarget.textContent = selected[0]
    } else {
      this.summaryTarget.textContent = `${selected[0]} +${selected.length - 1}`
    }

    this.hiddenContainerTarget.innerHTML = ""
    if (allSelected) return

    selected.forEach((value) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "category[]"
      input.value = value
      this.hiddenContainerTarget.appendChild(input)
    })
  }

  openPanel() {
    this.panelTarget.classList.remove("hidden")
    this.lockBodyScroll()
  }

  closePanel() {
    this.panelTarget.classList.add("hidden")
    this.unlockBodyScroll()
  }

  lockBodyScroll() {
    if (window.innerWidth < 768) {
      document.body.classList.add("overflow-hidden")
    }
  }

  unlockBodyScroll() {
    document.body.classList.remove("overflow-hidden")
  }
}
