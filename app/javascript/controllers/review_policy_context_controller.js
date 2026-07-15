import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["registrationType", "category"]
  static values = { categoriesByType: Object }

  sync() {
    if (!this.hasRegistrationTypeTarget || !this.hasCategoryTarget) return

    const categories = this.categoriesByTypeValue[this.registrationTypeTarget.value] || []
    const currentValues = this.currentCategoryValues()

    if (this.categoryTarget.tomselect) {
      this.syncTomSelectCategories(categories, currentValues)
      return
    }

    this.categoryTarget.innerHTML = ""

    categories.forEach((category) => {
      const option = document.createElement("option")
      option.value = category
      option.textContent = category
      option.selected = currentValues.includes(category)
      this.categoryTarget.appendChild(option)
    })

    if (!currentValues.some((value) => categories.includes(value)) && categories.length > 0) {
      this.categoryTarget.value = categories[0]
    }
  }

  currentCategoryValues() {
    if (this.categoryTarget.tomselect) {
      return this.categoryTarget.tomselect.getValue()
    }

    return Array.from(this.categoryTarget.selectedOptions || [])
      .map((option) => option.value)
      .filter(Boolean)
  }

  syncTomSelectCategories(categories, currentValues) {
    const tomSelect = this.categoryTarget.tomselect
    const nextValues = currentValues.filter((value) => categories.includes(value))
    const selectedValues = nextValues.length > 0 ? nextValues : categories.slice(0, 1)

    tomSelect.clear(true)
    tomSelect.clearOptions()

    categories.forEach((category) => {
      tomSelect.addOption({ value: category, text: category })
    })

    tomSelect.refreshOptions(false)
    tomSelect.setValue(selectedValues, true)
  }
}
