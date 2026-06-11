import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "panel", "summary", "checkbox", "allCheckbox", "hiddenContainer", "search", "count"]

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
    const visible = this.visibleCheckboxes()
    const shouldCheck = this.allCheckboxTarget.checked
    visible.forEach((checkbox) => {
      checkbox.checked = shouldCheck
    })
    this.sync()
  }

  clear(event) {
    if (event) event.preventDefault()
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = false
    })
    if (this.hasSearchTarget) {
      this.searchTarget.value = ""
    }
    this.checkboxTargets.forEach((checkbox) => {
      const row = checkbox.closest("[data-location-filter-row]")
      if (row) row.classList.remove("hidden")
    })
    this.sync()
  }

  filter() {
    const term = (this.searchTarget.value || "").toLowerCase().trim()
    this.checkboxTargets.forEach((checkbox) => {
      const label = checkbox.dataset.label || ""
      const row = checkbox.closest("[data-location-filter-row]")
      const visible = term === "" || label.includes(term)
      row.classList.toggle("hidden", !visible)
    })
    this.refreshAllState()
  }

  sync() {
    const selected = this.checkboxTargets
      .filter((checkbox) => checkbox.checked)
      .map((checkbox) => checkbox.value)

    const allSelected = selected.length === this.checkboxTargets.length && this.checkboxTargets.length > 0

    if (selected.length === 0) {
      this.summaryTarget.textContent = "Selecione bairros ou cidades"
    } else if (allSelected) {
      this.summaryTarget.textContent = "Todas localizações"
    } else if (selected.length === 1) {
      this.summaryTarget.textContent = selected[0]
    } else {
      this.summaryTarget.textContent = `${selected[0]} +${selected.length - 1}`
    }

    this.hiddenContainerTarget.innerHTML = ""
    if (allSelected) {
      if (this.hasCountTarget) {
        this.countTarget.textContent = "Todos selecionados"
      }
      this.refreshAllState()
      return
    }

    selected.forEach((value) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "city[]"
      input.value = value
      this.hiddenContainerTarget.appendChild(input)
    })

    if (this.hasCountTarget) {
      this.countTarget.textContent = `${selected.length} selecionado${selected.length === 1 ? "" : "s"}`
    }

    this.refreshAllState()
  }

  refreshAllState() {
    const visible = this.visibleCheckboxes()
    if (visible.length === 0) {
      this.allCheckboxTarget.checked = false
      this.allCheckboxTarget.indeterminate = false
      return
    }

    const checkedVisible = visible.filter((checkbox) => checkbox.checked).length
    this.allCheckboxTarget.checked = checkedVisible === visible.length
    this.allCheckboxTarget.indeterminate = checkedVisible > 0 && checkedVisible < visible.length
  }

  visibleCheckboxes() {
    return this.checkboxTargets.filter((checkbox) => {
      const row = checkbox.closest("[data-location-filter-row]")
      return row && !row.classList.contains("hidden")
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
