import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rowCheckbox", "selectedIdsInput", "selectedCount"]

  connect() {
    this.allSelected = false
    this.syncSelection()
  }

  toggleAll() {
    this.allSelected = !this.allSelected
    this.rowCheckboxTargets.forEach((checkbox) => {
      checkbox.checked = this.allSelected
    })
    this.syncSelection()
  }

  selectAll() {
    this.allSelected = true
    this.rowCheckboxTargets.forEach((checkbox) => {
      checkbox.checked = true
    })
    this.syncSelection()
  }

  clearAll() {
    this.allSelected = false
    this.rowCheckboxTargets.forEach((checkbox) => {
      checkbox.checked = false
    })
    this.syncSelection()
  }

  syncSelection() {
    const ids = this.rowCheckboxTargets
      .filter((checkbox) => checkbox.checked)
      .map((checkbox) => checkbox.value)

    if (this.hasSelectedIdsInputTarget) {
      this.selectedIdsInputTargets.forEach((input) => {
        input.value = ids.join(",")
      })
    }

    if (this.hasSelectedCountTarget) {
      if (ids.length > 0) {
        this.selectedCountTarget.textContent = `${ids.length} selecionado(s): exportar somente selecionados.`
      } else {
        this.selectedCountTarget.textContent = "Exportando todos os resultados filtrados."
      }
    }
  }
}
