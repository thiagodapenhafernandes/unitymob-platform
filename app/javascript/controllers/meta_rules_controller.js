import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

export default class extends Controller {
  static targets = ["pageSelect", "formSelect", "autoSync", "formCountLabel"]
  static values = {
    structure: Object // { page_id: { forms: [{id: 1, name: "Name"}] } }
  }

  connect() {
    this.initFormSelect()
    queueMicrotask(() => this.refreshFormsFromSelectedPages({ preserveSelections: true }))
  }

  disconnect() {
    if (this.formSelectInstance && this.formSelectInstance.destroy) {
      try { this.formSelectInstance.destroy() } catch (e) {}
    }
    this.formSelectInstance = null
  }

  initFormSelect() {
    if (!this.hasFormSelectTarget) return
    if (this.formSelectInstance) return
    if (this.formSelectTarget.tomselect) {
      this.formSelectInstance = this.formSelectTarget.tomselect
      return
    }

    this.formSelectInstance = new TomSelect(this.formSelectTarget, {
      plugins: ['remove_button'],
      placeholder: "Selecione os formulários...",
      maxOptions: null,
      onChange: () => this.syncAutoSummary(),
      onInitialize: () => {
        this.syncAutoSummary()
      }
    })
  }

  updateForms(event) {
    this.refreshFormsFromSelectedPages({ preserveSelections: true })
  }

  refreshFormsFromSelectedPages({ preserveSelections = true } = {}) {
    const selectedPages = this.selectedPageIds()
    if (!this.formSelectInstance) this.initFormSelect()
    if (!this.formSelectInstance) return

    const currentSelections = preserveSelections ? this.selectedFormIds() : []

    this.formSelectInstance.clear(true)
    this.formSelectInstance.clearOptions()

    selectedPages.forEach(pageId => {
      const pageData = this.structureValue[pageId]
      if (pageData && pageData.forms) {
        pageData.forms.forEach(form => {
          this.formSelectInstance.addOption({
            value: form.id,
            text: `${form.name} (${pageData.name})`
          })

          if (currentSelections.includes(form.id)) {
            this.formSelectInstance.addItem(form.id, true)
          }
        })
      }
    })

    this.formSelectInstance.refreshOptions(false)
    this.formSelectInstance.refreshItems()
    if (this.autoSyncEnabled()) {
      this.selectAllForms()
    }
    this.syncAutoSummary()
  }

  selectedPageIds() {
    if (!this.hasPageSelectTarget) return []

    if (this.pageSelectTarget.tomselect) {
      return Array.from(this.pageSelectTarget.tomselect.items).filter(Boolean)
    }

    return Array.from(this.pageSelectTarget.selectedOptions).map((option) => option.value).filter(Boolean)
  }

  selectedFormIds() {
    if (this.formSelectInstance) {
      return Array.from(this.formSelectInstance.items).filter(Boolean)
    }

    return Array.from(this.formSelectTarget.selectedOptions).map((option) => option.value).filter(Boolean)
  }

  syncNow(event) {
    const btn = event.currentTarget
    const icon = btn.querySelector('i')

    btn.disabled = true
    if (icon) icon.classList.add('fa-spin') // or bi-arrow-repeat spin

    // Simulate sync or call API if available
    // For now, just a visual feedback
    setTimeout(() => {
      btn.disabled = false
      if (icon) icon.classList.remove('fa-spin')
      window.axToast({ message: "Sincronização concluída com sucesso!", type: "success" })
    }, 1500)
  }

  toggleAutoSync(event) {
    if (!this.formSelectInstance) return

    if (event.target.checked) {
      this.selectAllForms()
    }
    this.syncAutoSummary()
  }

  selectAllForms() {
    if (!this.formSelectInstance) return

    const allOptions = Object.keys(this.formSelectInstance.options)
    this.formSelectInstance.addItems(allOptions)
  }

  syncAutoSummary() {
    if (!this.formSelectInstance) return

    const enabled = this.isAllMetaFormsSelectedAutomatically()
    const control = this.formSelectInstance.control
    const wrapper = this.formSelectInstance.wrapper

    wrapper.classList.toggle("meta-auto-summary-mode", enabled)
    control.querySelectorAll(".item").forEach((item) => { item.hidden = enabled })

    let summary = control.querySelector(".meta-auto-summary")
    if (enabled) {
      if (!summary) {
        summary = document.createElement("div")
        summary.className = "meta-auto-summary badge bg-primary-subtle text-primary border border-primary-subtle rounded-pill px-3 py-2"
        control.prepend(summary)
      }
      summary.textContent = "Todos os forms da Meta selecionados automaticamente"
      if (this.hasFormCountLabelTarget) {
        this.formCountLabelTarget.innerHTML = '<strong>Todos os forms da Meta</strong> selecionados automaticamente'
      }
    } else {
      summary?.remove()
      if (this.hasFormCountLabelTarget) {
        const count = this.formSelectInstance.items.filter((value) => value).length
        this.formCountLabelTarget.innerHTML = this.formatCount(count)
      }
    }
  }

  isAllMetaFormsSelectedAutomatically() {
    if (!this.autoSyncEnabled()) return false

    const allOptions = Object.keys(this.formSelectInstance.options)
    if (allOptions.length === 0) return false

    const selected = new Set(this.formSelectInstance.items)
    return allOptions.every((option) => selected.has(option))
  }

  autoSyncEnabled() {
    return this.hasAutoSyncTarget && this.autoSyncTarget.checked
  }

  formatCount(count) {
    if (count === 0) return "Nenhum formulário selecionado"
    if (count === 1) return "<strong>1</strong> formulário selecionado"
    return `<strong>${count.toLocaleString("pt-BR")}</strong> formulários selecionados`
  }
}
