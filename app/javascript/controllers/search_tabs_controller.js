import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "input", "priceSelect", "advancedPanel", "advancedLabel", "advancedIcon"]
  static values = {
    salePriceOptions: Array,
    rentPriceOptions: Array
  }

  connect() {
    // Set initial state based on input value or default
    this.updateTabs(this.inputTarget.value || 'venda')
    this.advancedOpen = false
  }

  switch(event) {
    const value = event.currentTarget.dataset.value
    this.inputTarget.value = value
    this.updateTabs(value)
    this.updatePriceOptions(value)
  }

  updateTabs(activeValue) {
    this.tabTargets.forEach(tab => {
      if (tab.dataset.value === activeValue) {
        tab.classList.remove('text-gray-600', 'hover:text-blue-three', 'bg-transparent')
        tab.classList.add('bg-hero-button', 'text-hero-button-text', 'shadow-sm')
      } else {
        tab.classList.add('text-gray-600', 'hover:text-blue-three', 'bg-transparent')
        tab.classList.remove('bg-hero-button', 'text-hero-button-text', 'shadow-sm')
      }
    })
  }

  updatePriceOptions(activeValue) {
    if (!this.hasPriceSelectTarget) return

    const currentValue = this.priceSelectTarget.value
    const options = activeValue === "aluguel" ? this.rentPriceOptionsValue : this.salePriceOptionsValue
    const values = options.map((option) => option[1])

    this.priceSelectTarget.innerHTML = ""
    options.forEach(([label, value]) => {
      const option = document.createElement("option")
      option.value = value
      option.textContent = label
      this.priceSelectTarget.appendChild(option)
    })

    this.priceSelectTarget.value = values.includes(currentValue) ? currentValue : ""
  }

  toggleAdvanced(event) {
    event.preventDefault()
    this.advancedOpen = !this.advancedOpen

    if (this.advancedOpen) {
      this.advancedPanelTarget.classList.remove("max-h-0", "opacity-0", "pointer-events-none")
      this.advancedPanelTarget.classList.add("max-h-[900px]", "opacity-100")
      this.advancedLabelTarget.textContent = "Simples"
      this.advancedIconTarget.classList.remove("bi-list")
      this.advancedIconTarget.classList.add("bi-chevron-up")
    } else {
      this.advancedPanelTarget.classList.add("max-h-0", "opacity-0", "pointer-events-none")
      this.advancedPanelTarget.classList.remove("max-h-[900px]", "opacity-100")
      this.advancedLabelTarget.textContent = "Avançado"
      this.advancedIconTarget.classList.add("bi-list")
      this.advancedIconTarget.classList.remove("bi-chevron-up")
    }
  }

  openAdvanced() {
    // Dispatch event to open advanced filters (likely sidebar in Habitation index)
    // Or if we are on Home, we might need a different logic or redirect to search with modal open
    const sidebar = document.querySelector('[data-controller="advanced-filters"]')
    if (sidebar) {
      this.dispatch("open-advanced") // Custom integration
      // If the controller is already on the page:
      const controller = this.application.getControllerForElementAndIdentifier(sidebar, "advanced-filters")
      if (controller) controller.open()
    } else {
      // Fallback: redirect to habitations with a flag
      window.location.href = "/imoveis?open_filters=true"
    }
  }
}
