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
    "editCity"
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
  }

  search() {
    window.clearTimeout(this.searchTimeout)
    this.searchTimeout = window.setTimeout(() => this.fetchResults(), 250)
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

    this.clearError()
    this.createPanelTarget.hidden = true
    this.editPanelTarget.hidden = false
    this.editNameTarget.value = this.selectedProprietor.name || ""
    this.editPhoneTarget.value = this.selectedProprietor.phone_primary || this.selectedProprietor.phone_primary_display || ""
    this.editEmailTarget.value = this.selectedProprietor.email || ""
    this.editCityTarget.value = this.selectedProprietor.city || ""
    this.editNameTarget.focus()
  }

  async update(event) {
    event?.preventDefault()
    if (!this.selectedProprietor?.id) return

    await this.submitForm(this.editFormTarget, this.updateUrlFor(this.selectedProprietor.id), "PATCH", (payload) => {
      this.applyProprietor(payload)
      this.editPanelTarget.hidden = true
    })
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
    if (this.hasEmptyTarget) this.emptyTarget.hidden = true
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
