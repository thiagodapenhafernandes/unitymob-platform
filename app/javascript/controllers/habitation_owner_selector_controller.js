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
    "ownerCard",
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
    canEdit: Boolean,
    canEditName: Boolean,
    inline: Boolean,
    requireEmail: { type: Boolean, default: true }
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
    if (this.inlineValue || this.needsContactCompletion(payload)) {
      this.editingProprietor = payload
      this.showEditPanel(payload, { focusFirstMissing: true, clearSearchResults: true })
      return
    }

    this.applyProprietor(payload)
    this.finishSelection()
  }

  showCreate(event) {
    event?.preventDefault()
    this.clearError()
    this.editPanelTarget.hidden = true
    this.createPanelTarget.hidden = false
    this.prefillCreateFields(this.queryTarget.value.trim())
    this.firstMissingQuickField("create")?.focus()
  }

  async create(event) {
    event?.preventDefault()
    if (!this.validateQuickFields("create")) return

    await this.submitForm(this.createFormTarget, this.createUrlValue, "POST", (payload) => {
      this.applyProprietor(payload)
      this.resetFields(this.createFormTarget)
      this.finishSelection()
    }, (payload) => {
      this.redirectDuplicateToSearch(payload, this.createPhoneTarget)
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
    this.syncEditNamePermission()
    this.syncEditPhonePermission(proprietor)
    this.dispatchPhoneMask(this.editPhoneTarget)
    this.focusEditField(options)
  }

  async update(event) {
    event?.preventDefault()
    const proprietor = this.editingProprietor || this.selectedProprietor
    if (!proprietor?.id) return
    if (!this.validateQuickFields("edit")) return

    await this.submitForm(this.editFormTarget, this.updateUrlFor(proprietor.id), "PATCH", (payload) => {
      this.applyProprietor(payload)
      this.editPanelTarget.hidden = true
      this.editingProprietor = null
      this.finishSelection()
    }, (payload) => {
      this.redirectDuplicateToSearch(payload, this.editPhoneTarget)
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

  async submitForm(form, url, method, onSuccess, onConflict = null) {
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
      if (!response.ok) {
        if (response.status === 409 && payload.proprietor && onConflict) {
          this.showError(this.errorMessage(payload))
          onConflict(payload)
          return
        }

        throw new Error(this.errorMessage(payload))
      }

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
    this.syncLegacyOwnerFields(proprietor)
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
    const missingRequired = !this.hasText(proprietor.phone_primary || proprietor.phone_primary_display) ||
      !this.hasText(proprietor.city)
    const missingEmail = this.requireEmailValue && !this.hasText(proprietor.email)

    return missingRequired || missingEmail
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

    const fields = [
      this.editPhoneTarget,
      this.editCityTarget,
      ...(this.requireEmailValue ? [this.editEmailTarget] : [])
    ]
    const target = fields.find((field) => !this.hasText(field.value))

    ;(target || this.editNameTarget).focus()
  }

  syncEditPhonePermission(proprietor) {
    if (!this.hasEditPhoneTarget) return

    const canEditPhone = this.canEditNameValue || !this.hasText(proprietor.phone_primary || proprietor.phone_primary_display)
    this.editPhoneTarget.readOnly = !canEditPhone
    this.editPhoneTarget.classList.toggle("ax-readonly-input", !canEditPhone)
    if (canEditPhone) {
      this.editPhoneTarget.removeAttribute("aria-readonly")
    } else {
      this.editPhoneTarget.setAttribute("aria-readonly", "true")
    }
  }

  dispatchPhoneMask(field) {
    field?.dispatchEvent(new Event("input", { bubbles: true }))
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

      const value = field.type === "tel" ? this.normalizedPhoneValue(field) : field.value
      formData.append(field.name, value)
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

  prefillCreateFields(query) {
    this.createNameTarget.value = ""
    this.createPhoneTarget.value = ""
    this.createEmailTarget.value = ""
    this.createCityTarget.value = ""

    if (!query) return

    if (/^[\d\s()+.-]+$/.test(query)) {
      this.createPhoneTarget.value = query
      this.dispatchPhoneMask(this.createPhoneTarget)
    } else if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(query)) {
      this.createEmailTarget.value = query
    } else {
      this.createNameTarget.value = query
    }
  }

  validateQuickFields(prefix) {
    const missing = this.firstMissingQuickField(prefix)
    if (missing) {
      this.showError(this.requireEmailValue ? "Informe nome, telefone, e-mail e cidade." : "Informe nome, telefone e cidade.")
      missing.focus()
      return false
    }

    const phoneField = prefix === "edit" ? this.editPhoneTarget : this.createPhoneTarget
    const phoneError = this.phoneValidationError(phoneField)
    if (phoneError) {
      this.showError(phoneError)
      phoneField.focus()
      return false
    }

    this.clearError()
    return true
  }

  firstMissingQuickField(prefix) {
    const fields = prefix === "edit"
      ? [this.editNameTarget, this.editPhoneTarget, this.editCityTarget, ...(this.requireEmailValue ? [this.editEmailTarget] : [])]
      : [this.createNameTarget, this.createPhoneTarget, this.createCityTarget, ...(this.requireEmailValue ? [this.createEmailTarget] : [])]

    return fields.find((field) => !this.hasText(field.value))
  }

  phoneValidationError(field) {
    const metadata = this.phoneMetadata(field)
    const rawDigits = String(metadata.rawValue || field.value || "").replace(/\D/g, "")
    if (!rawDigits) return "Informe um telefone válido."

    if (String(metadata.rawValue || field.value || "").trim().startsWith("+") && !rawDigits.startsWith("55")) {
      if (metadata.isValidNumber || (rawDigits.length >= 8 && rawDigits.length <= 15)) return null
      return "Telefone inválido. Números internacionais devem ter entre 8 e 15 dígitos."
    }

    if (metadata.countryIso2 && metadata.countryIso2 !== "br") {
      if (metadata.isValidNumber) return null
      return "Telefone inválido. Selecione o país correto e informe um número válido."
    }

    const nationalDigits = this.brazilianNationalDigits(rawDigits)
    if (nationalDigits.length === 11 && nationalDigits[2] === "9") return null

    return "Telefone inválido para WhatsApp no Brasil. Informe DDD + número com 9 dígitos, exemplo: (47) 98851-6745."
  }

  normalizedPhoneValue(field) {
    const detail = { value: field.value }
    field.dispatchEvent(new CustomEvent("phone-input:normalize", { detail, bubbles: true }))
    return detail.value || field.value
  }

  phoneMetadata(field) {
    const detail = { rawValue: field.value }
    field.dispatchEvent(new CustomEvent("phone-input:metadata", { detail, bubbles: true }))
    return detail
  }

  brazilianNationalDigits(digits) {
    return digits.startsWith("55") ? digits.slice(2) : digits
  }

  redirectDuplicateToSearch(payload, phoneField) {
    this.hidePanels()
    this.editingProprietor = null

    const phone = this.searchablePhoneValue(payload, phoneField)
    if (this.hasQueryTarget && phone) {
      this.queryTarget.value = phone
      this.queryTarget.focus()
      const message = this.errorMessage(payload)
      this.fetchResults().finally(() => this.showError(message))
    }
  }

  searchablePhoneValue(payload, phoneField) {
    const proprietor = payload?.proprietor || {}
    const phone = proprietor.phone_primary_display ||
      proprietor.phone_primary ||
      this.normalizedPhoneValue(phoneField) ||
      phoneField?.value

    return String(phone || "").trim()
  }

  syncEditNamePermission() {
    if (!this.hasEditNameTarget) return

    this.editNameTarget.readOnly = !this.canEditNameValue
    this.editNameTarget.classList.toggle("ax-readonly-input", !this.canEditNameValue)
    if (this.canEditNameValue) {
      this.editNameTarget.removeAttribute("aria-readonly")
    } else {
      this.editNameTarget.setAttribute("aria-readonly", "true")
    }
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

  syncLegacyOwnerFields(proprietor) {
    if (this.hasLegacyNameTarget) this.legacyNameTarget.value = this.legacyValue(proprietor.name)
    if (this.hasLegacyCodeTarget) this.legacyCodeTarget.value = this.legacyValue(proprietor.code || proprietor.vista_code)
    if (this.hasLegacyPhonePrimaryTarget) this.legacyPhonePrimaryTarget.value = this.legacyValue(proprietor.phone_primary || proprietor.phone_primary_display)
    if (this.hasLegacyPhoneSecondaryTarget) this.legacyPhoneSecondaryTarget.value = this.legacyValue(proprietor.phone_secondary || proprietor.phone_secondary_display)
    if (this.hasLegacyPhoneResidentialTarget) this.legacyPhoneResidentialTarget.value = this.legacyValue(proprietor.phone_residential || proprietor.residential_phone)
    if (this.hasLegacyEmailTarget) this.legacyEmailTarget.value = this.legacyValue(proprietor.email)
    if (this.hasLegacyCityTarget) this.legacyCityTarget.value = this.legacyValue(proprietor.city)
  }

  legacyValue(value) {
    const text = String(value || "").trim()
    return text === "-" ? "" : text
  }

  syncOwnerState(proprietor) {
    const hasOwner = this.hasOwner(proprietor)
    if (this.hasEmptyTarget) this.emptyTarget.hidden = hasOwner
    if (this.hasOwnerCardTarget) this.ownerCardTarget.hidden = !hasOwner
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
    if (this.inlineValue) return

    const modal = document.getElementById("quickProprietorModal")
    modal?.dispatchEvent(new CustomEvent("ax-modal:close", { bubbles: true }))
  }

  finishSelection() {
    if (this.inlineValue) {
      this.hidePanels()
      if (this.hasQueryTarget) this.queryTarget.value = ""
      if (this.hasResultsTarget) this.resultsTarget.innerHTML = ""
      if (this.hasNoResultsTarget) this.noResultsTarget.hidden = true
      return
    }

    this.closeModal()
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
