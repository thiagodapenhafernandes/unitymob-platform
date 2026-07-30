import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "hiddenInput",
    "name",
    "phonePrimary",
    "phoneSecondary",
    "email",
    "city",
    "empty",
    "directAction",
    "menuAction",
    "editAction",
    "query",
    "results",
    "noResults",
    "createPanel",
    "createForm",
    "editPanel",
    "editForm",
    "error",
    "createName",
    "createPhone",
    "createEmail",
    "createCity",
    "editName",
    "editPhone",
    "editEmail",
    "editCity",
    "legacyName",
    "legacyCode",
    "legacyPhonePrimary",
    "legacyPhoneSecondary",
    "legacyPhoneResidential",
    "legacyEmail",
    "legacyCity"
  ]

  static values = {
    searchUrl: String,
    createUrl: String,
    updateUrlTemplate: String,
    canEdit: Boolean
  }

  connect() {
    this.searchTimeout = null
    this.selectedProprietor = this.currentPayload()
    this.editingProprietor = null
  }

  search() {
    window.clearTimeout(this.searchTimeout)
    this.searchTimeout = window.setTimeout(() => this.fetchResults(), 250)
  }

  prepareExchange(event) {
    event?.preventDefault()
    this.clearError()
    this.hidePanels()
    if (this.hasQueryTarget) this.queryTarget.value = ""
    if (this.hasResultsTarget) this.resultsTarget.innerHTML = ""
    if (this.hasNoResultsTarget) this.noResultsTarget.hidden = true
  }

  async fetchResults() {
    const query = this.queryTarget.value.trim()
    this.clearError()
    this.hidePanels()

    if (query.length < 2) {
      this.resultsTarget.innerHTML = ""
      this.noResultsTarget.hidden = true
      return
    }

    try {
      const url = new URL(this.searchUrlValue, window.location.origin)
      url.searchParams.set("q", query)
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      const payload = await response.json()
      if (!response.ok) throw new Error(this.errorMessage(payload))

      const proprietors = Array.isArray(payload.proprietors) ? payload.proprietors : []
      this.renderResults(proprietors)
      this.noResultsTarget.hidden = proprietors.length > 0
    } catch (error) {
      this.showError(error.message || "Erro ao buscar proprietários.")
    }
  }

  select(event) {
    const payload = this.payloadFromElement(event.currentTarget)
    if (this.needsContactCompletion(payload)) {
      this.editingProprietor = payload
      this.showEditPanel(payload, { focusFirstMissing: true, clearSearchResults: true })
      return
    }

    this.applyProprietor(payload)
    this.closeModal()
  }

  showCreate(event) {
    event?.preventDefault()
    this.clearError()
    this.editPanelTarget.hidden = true
    this.createPanelTarget.hidden = false
    this.createNameTarget.value = this.queryTarget.value.trim()
    this.createPhoneTarget.focus()
  }

  async create(event) {
    event?.preventDefault()
    await this.submitForm(this.createFormTarget, this.createUrlValue, "POST", (payload) => {
      this.applyProprietor(payload)
      this.resetFields(this.createFormTarget)
      this.closeModal()
    })
  }

  showEdit(event) {
    event?.preventDefault()
    if (!this.canEditValue || !this.selectedProprietor?.id) return

    this.editingProprietor = this.selectedProprietor
    this.showEditPanel(this.selectedProprietor)
  }

  showEditPanel(proprietor, options = {}) {
    this.clearError()
    this.createPanelTarget.hidden = true
    this.editPanelTarget.hidden = false
    if (options.clearSearchResults) {
      if (this.hasResultsTarget) this.resultsTarget.innerHTML = ""
      if (this.hasNoResultsTarget) this.noResultsTarget.hidden = true
    }
    this.editNameTarget.value = proprietor.name || ""
    this.editPhoneTarget.value = proprietor.phone_primary || proprietor.phone_primary_display || ""
    this.editEmailTarget.value = proprietor.email || ""
    this.editCityTarget.value = proprietor.city || ""
    this.focusEditField(options)
  }

  async update(event) {
    event?.preventDefault()
    const proprietor = this.editingProprietor || this.selectedProprietor
    if (!proprietor?.id) return

    await this.submitForm(this.editFormTarget, this.updateUrlFor(proprietor.id), "PATCH", (payload) => {
      this.applyProprietor(payload)
      this.editPanelTarget.hidden = true
      this.editingProprietor = null
      this.closeModal()
    })
  }

  remove(event) {
    event?.preventDefault()
    this.clearError()
    this.hidePanels()
    if (this.hasQueryTarget) this.queryTarget.value = ""
    if (this.hasResultsTarget) this.resultsTarget.innerHTML = ""
    if (this.hasNoResultsTarget) this.noResultsTarget.hidden = true

    this.applyProprietor({
      id: "",
      name: "Proprietário não vinculado",
      phone_primary: "",
      phone_primary_display: "",
      phone_secondary: "",
      phone_secondary_display: "",
      email: "",
      city: ""
    })
    this.clearLegacyOwnerFields()
  }

  renderResults(proprietors) {
    this.resultsTarget.innerHTML = proprietors.map((proprietor) => this.resultTemplate(proprietor)).join("")
  }

  resultTemplate(proprietor) {
    const payload = this.escapeAttribute(JSON.stringify(proprietor))
    const phone = this.escapeHtml(proprietor.phone_primary_display || proprietor.phone_primary || "")
    const email = this.escapeHtml(proprietor.email || "")
    const city = this.escapeHtml(proprietor.city || "")
    const secondary = [phone, email, city].filter(Boolean).join(" · ")

    return `
      <button type="button"
              class="habitation-owner-result"
              data-action="habitation-owner-selector#select"
              data-proprietor-payload="${payload}">
        <span class="habitation-owner-result__name">${this.escapeHtml(proprietor.name || "Proprietário")}</span>
        <span class="habitation-owner-result__meta">${secondary || "Sem contatos cadastrados"}</span>
      </button>
    `
  }

  async submitForm(form, url, method, onSuccess) {
    this.clearError()

    try {
      const response = await fetch(url, {
        method,
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: this.formDataFrom(form)
      })
      const payload = await response.json()
      if (!response.ok) throw new Error(this.errorMessage(payload))

      onSuccess(payload)
    } catch (error) {
      this.showError(error.message || "Erro ao salvar proprietário.")
    }
  }

  applyProprietor(proprietor) {
    this.selectedProprietor = proprietor
    this.hiddenInputTarget.value = proprietor.id || ""
    this.hiddenInputTarget.dispatchEvent(new Event("change", { bubbles: true }))

    this.nameTarget.textContent = proprietor.name || "Proprietário não vinculado"
    this.phonePrimaryTarget.textContent = proprietor.phone_primary_display || proprietor.phone_primary || "-"
    this.phoneSecondaryTarget.textContent = proprietor.phone_secondary_display || proprietor.phone_secondary || ""
    this.phoneSecondaryTarget.parentElement.hidden = !(proprietor.phone_secondary_display || proprietor.phone_secondary)
    this.emailTarget.textContent = proprietor.email || "-"
    this.cityTarget.textContent = proprietor.city || "-"
    this.syncOwnerState(proprietor)
  }

  currentPayload() {
    return {
      id: this.hiddenInputTarget.value,
      name: this.nameTarget.textContent.trim(),
      phone_primary_display: this.phonePrimaryTarget.textContent.trim(),
      phone_secondary_display: this.phoneSecondaryTarget.textContent.trim(),
      email: this.emailTarget.textContent.trim(),
      city: this.cityTarget.textContent.trim()
    }
  }

  payloadFromElement(element) {
    try {
      return JSON.parse(element.dataset.proprietorPayload || "{}")
    } catch (_error) {
      return {}
    }
  }

  updateUrlFor(id) {
    return this.updateUrlTemplateValue.replace(":id", id)
  }

  needsContactCompletion(proprietor) {
    return !this.hasText(proprietor.phone_primary || proprietor.phone_primary_display) ||
      !this.hasText(proprietor.email) ||
      !this.hasText(proprietor.city)
  }

  hasText(value) {
    const text = String(value || "").trim()
    return text.length > 0 && text !== "-"
  }

  focusEditField(options = {}) {
    if (!options.focusFirstMissing) {
      this.editNameTarget.focus()
      return
    }

    const target = [
      this.editPhoneTarget,
      this.editEmailTarget,
      this.editCityTarget
    ].find((field) => !this.hasText(field.value))

    ;(target || this.editNameTarget).focus()
  }

  hidePanels() {
    if (this.hasCreatePanelTarget) this.createPanelTarget.hidden = true
    if (this.hasEditPanelTarget) this.editPanelTarget.hidden = true
  }

  formDataFrom(container) {
    if (container instanceof HTMLFormElement) return new FormData(container)

    const formData = new FormData()
    container.querySelectorAll("input[name], select[name], textarea[name]").forEach((field) => {
      if (field.disabled) return
      if ((field.type === "checkbox" || field.type === "radio") && !field.checked) return

      formData.append(field.name, field.value)
    })
    return formData
  }

  resetFields(container) {
    container.querySelectorAll("input, select, textarea").forEach((field) => {
      if (field.type === "hidden") return
      if (field.type === "checkbox" || field.type === "radio") {
        field.checked = false
      } else {
        field.value = ""
      }
    })
  }

  clearLegacyOwnerFields() {
    [
      "legacyName",
      "legacyCode",
      "legacyPhonePrimary",
      "legacyPhoneSecondary",
      "legacyPhoneResidential",
      "legacyEmail",
      "legacyCity"
    ].forEach((targetName) => {
      if (!this[`has${this.capitalize(targetName)}Target`]) return

      this[`${targetName}Target`].value = ""
    })
  }

  syncOwnerState(proprietor) {
    const hasOwner = this.hasOwner(proprietor)
    if (this.hasEmptyTarget) this.emptyTarget.hidden = hasOwner
    if (this.hasDirectActionTarget) this.directActionTarget.hidden = hasOwner
    if (this.hasMenuActionTarget) this.menuActionTarget.hidden = !hasOwner
    if (this.hasEditActionTarget) this.editActionTarget.hidden = !hasOwner || !proprietor?.id
  }

  hasOwner(proprietor) {
    return Boolean(proprietor?.id || (proprietor?.name && proprietor.name !== "Proprietário não vinculado"))
  }

  capitalize(value) {
    return value.charAt(0).toUpperCase() + value.slice(1)
  }

  closeModal() {
    const modal = document.getElementById("quickProprietorModal")
    modal?.dispatchEvent(new CustomEvent("ax-modal:close", { bubbles: true }))
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.hidden = true
  }

  errorMessage(payload) {
    const errors = Array.isArray(payload.errors) ? payload.errors : ["Não foi possível salvar o proprietário."]
    return errors.join(" ")
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;")
  }

  escapeAttribute(value) {
    return this.escapeHtml(value)
  }
}
