import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["registrationType", "category"]
  static values = { categoriesByType: Object }

  sync() {
    if (!this.hasRegistrationTypeTarget || !this.hasCategoryTarget) return

    const categories = this.categoriesByTypeValue[this.registrationTypeTarget.value] || []
    const current = this.categoryTarget.value
    this.categoryTarget.innerHTML = ""

    categories.forEach((category) => {
      const option = document.createElement("option")
      option.value = category
      option.textContent = category
      option.selected = category === current
      this.categoryTarget.appendChild(option)
    })

    if (!categories.includes(current) && categories.length > 0) {
      this.categoryTarget.value = categories[0]
    }
  }
}
