import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "locationDropdown", "typeDropdown", "transactionDropdown",
    "priceDropdown", "roomsDropdown"
  ]

  connect() {
    // Close dropdowns when clicking outside
    this.boundCloseDropdowns = this.closeDropdowns.bind(this)
    document.addEventListener('click', this.boundCloseDropdowns)
  }

  disconnect() {
    document.removeEventListener('click', this.boundCloseDropdowns)
  }

  toggleDropdown(event) {
    event.stopPropagation()
    const button = event.currentTarget
    const target = button.dataset.target
    const dropdownName = `${target}Dropdown`

    // Close all other dropdowns
    this.closeAllDropdowns()

    // Toggle this dropdown
    if (this.hasTarget(dropdownName)) {
      const dropdown = this[`${dropdownName}Target`]
      dropdown.classList.toggle('show')
      button.classList.toggle('active')
    }
  }

  closeDropdowns(event) {
    // Don't close if clicking inside a dropdown
    if (event && event.target.closest('.filter-dropdown-menu')) {
      return
    }

    this.closeAllDropdowns()
  }

  closeAllDropdowns() {
    // Close all dropdown menus
    const allDropdowns = [
      'locationDropdown', 'typeDropdown', 'transactionDropdown',
      'priceDropdown', 'roomsDropdown'
    ]

    allDropdowns.forEach(name => {
      if (this.hasTarget(name)) {
        const dropdown = this[`${name}Target`]
        dropdown.classList.remove('show')
      }
    })

    // Remove active class from all buttons
    this.element.querySelectorAll('.filter-btn').forEach(btn => {
      btn.classList.remove('active')
    })
  }

  hasTarget(targetName) {
    return this.targets.find(targetName)
  }
}
