import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

export default class extends Controller {
  static targets = ["pageSelect", "formSelect", "autoSync", "formCountLabel", "exclusionSelect"]
  static values = {
    structure: Object, // { page_id: { forms: [{id: 1, name: "Name"}] } }
    syncUrl: String,
    allParentsWhenEmpty: Boolean
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
      dropdownParent: "body",
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
    const selected = this.selectedPageIds()
    const selectedPages = selected.length === 0 && this.allParentsWhenEmptyValue ? Object.keys(this.structureValue) : selected
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

    this.refreshExclusionOptions(selectedPages)
    this.formSelectInstance.refreshOptions(false)
    this.formSelectInstance.refreshItems()
    if (this.autoSyncEnabled()) {
      this.selectAllForms()
    }
    this.syncAutoSummary()
  }

  excludedFormIds() {
    if (!this.hasExclusionSelectTarget) return []
    const select = this.exclusionSelectTarget
    return select.tomselect ? Array.from(select.tomselect.items) : Array.from(select.selectedOptions, option => option.value).filter(Boolean)
  }

  refreshExclusionOptions(pageIds) {
    if (!this.hasExclusionSelectTarget) return
    const select = this.exclusionSelectTarget
    const instance = select.tomselect || new TomSelect(select, {
      dropdownParent: "body", plugins: ["remove_button"], maxOptions: null,
      create: false, onChange: () => this.updateExclusions()
    })
    const selected = this.excludedFormIds()
    const retained = selected.map(id => instance.options[id]).filter(Boolean)
    instance.clear(true)
    instance.clearOptions()
    instance.addOptions(retained)
    pageIds.forEach(id => {
      const page = this.structureValue[id]
      page?.forms.forEach(form => instance.addOption({ value: form.id, text: `${form.name} (${page.name})` }))
    })
    instance.setValue(selected, true)
    instance.refreshOptions(false)
  }

  updateExclusions() {
    if (this.autoSyncEnabled()) this.selectAllForms()
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

  // Dispara a sincronização REAL (MetaSyncJob em background via sync_forms).
  // Antes era um setTimeout com toast de sucesso falso.
  async syncNow(event) {
    const btn = event.currentTarget
    const icon = btn.querySelector("i")
    if (!this.hasSyncUrlValue || !this.syncUrlValue) {
      window.axToast({ message: "Sincronização indisponível: conecte a conta Meta em Integrações.", type: "error" })
      return
    }

    btn.disabled = true
    icon?.classList.add("ax-spinner")

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const response = await fetch(this.syncUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": token, "Accept": "application/json" },
        credentials: "same-origin"
      })
      const payload = await response.json().catch(() => null)
      if (!response.ok || !payload?.ok) {
        throw new Error(payload?.message || `HTTP ${response.status}`)
      }
      window.axToast({
        message: `${payload.message} Recarregue a página em instantes para ver formulários novos.`,
        type: "success"
      })
    } catch (error) {
      window.axToast({ message: error.message || "Falha ao iniciar a sincronização. Verifique a conexão Meta em Integrações.", type: "error" })
    } finally {
      btn.disabled = false
      icon?.classList.remove("ax-spinner")
    }
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

    const exclusions = new Set(this.excludedFormIds())
    const allOptions = Object.keys(this.formSelectInstance.options).filter(id => !exclusions.has(id))
    this.formSelectInstance.clear(true)
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
        summary.className = "meta-auto-summary ax-badge ax-badge--blue"
        control.prepend(summary)
      }
      summary.textContent = this.excludedFormIds().length ? "Forms da Meta selecionados automaticamente, exceto as exclusões" : "Todos os forms da Meta selecionados automaticamente"
      if (this.hasFormCountLabelTarget) {
        this.formCountLabelTarget.textContent = summary.textContent
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

    const exclusions = new Set(this.excludedFormIds())
    const selected = new Set(this.formSelectInstance.items)
    return allOptions.every((option) => exclusions.has(option) || selected.has(option))
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
