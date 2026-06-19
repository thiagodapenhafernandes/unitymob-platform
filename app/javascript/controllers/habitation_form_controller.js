import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "cadastroType",
    "category",
    "tipo",
    "statusSelect",
    "suspensionReasonField",
    "suspensionReasonInput",
    "unitOnly",
    "developmentSelect",
    "developmentName",
    "developmentNameLabel",
    "developmentEditLink",
    "proprietorSelect",
    "captadorSelect",
    "deliveryDate",
    "constructionProfileSelect",
    "streetTypeSelect",
    "street",
    "streetNumber",
    "stateSelect",
    "zipCode",
    "neighborhoodSelect",
    "commercialNeighborhoodSelect",
    "citySelect"
  ]

  static values = {
    categoriesByType: Object,
    tipoByType: Object,
    developments: Object,
    errorFields: Array
  }

  connect() {
    this.activateTabFromHash()
    this.applyCadastroType()
    this.applySuspensionReasonVisibility()
    this.syncFromDevelopmentSelection()
    this.applyServerValidationErrors()
  }

  activateTabFromHash() {
    const tabId = window.location.hash?.replace("#", "")
    if (!tabId) return

    const trigger = this.tabTriggerForId(tabId)
    if (trigger) this.showTab(trigger)
  }

  showTab(trigger) {
    const targetSelector = this.targetSelectorForTab(trigger)
    if (!targetSelector) return

    const pane = this.element.querySelector(targetSelector)
    if (!pane) return

    const tabList = trigger.closest('[role="tablist"]')
    tabList?.querySelectorAll("[data-ax-tabs-target-param], [data-bs-target]").forEach((tab) => {
      const isCurrent = tab === trigger
      tab.classList.toggle("active", isCurrent)
      tab.setAttribute("aria-selected", isCurrent ? "true" : "false")
    })

    const tabContent = pane.closest(".tab-content")
    tabContent?.querySelectorAll(".tab-pane").forEach((tabPane) => {
      const isCurrent = tabPane === pane
      tabPane.classList.toggle("active", isCurrent)
      tabPane.classList.toggle("show", isCurrent)
    })

    pane.dispatchEvent(new CustomEvent("ax:tab-shown", {
      bubbles: true,
      detail: { trigger, target: pane }
    }))
  }

  targetSelectorForTab(trigger) {
    return trigger?.dataset?.axTabsTargetParam || trigger?.dataset?.bsTarget || null
  }

  tabTriggerForId(tabId) {
    const escapedId = CSS.escape(tabId)
    return this.element.querySelector(`[data-ax-tabs-target-param="#${escapedId}"], [data-bs-target="#${escapedId}"]`)
  }

  applyServerValidationErrors() {
    this.clearServerValidationErrors()
    if (!this.hasErrorFieldsValue || !Array.isArray(this.errorFieldsValue)) return

    const uniqueAttributes = [...new Set(this.errorFieldsValue.map((field) => String(field)))]
    uniqueAttributes.forEach((attribute) => this.highlightAttributeFields(attribute))
    this.focusFirstInvalidField()
  }

  clearServerValidationErrors() {
    this.element.querySelectorAll(".server-invalid").forEach((node) => {
      node.classList.remove("server-invalid", "is-invalid")
      node.removeAttribute("aria-invalid")
    })
  }

  highlightAttributeFields(attribute) {
    this.paramNamesForAttribute(attribute).forEach((paramName) => {
      this.findInputsByName(paramName).forEach((field) => this.markFieldInvalid(field))
    })
  }

  paramNamesForAttribute(attribute) {
    const attr = String(attribute).trim()
    if (!attr) return []

    if (attr.startsWith("address.")) {
      const addressField = attr.split(".").slice(1).join(".")
      return [`habitation[address_attributes][${addressField}]`]
    }

    return [`habitation[${attr}]`]
  }

  findInputsByName(paramName) {
    const escapedName = this.escapeAttributeValue(paramName)
    const escapedArrayName = this.escapeAttributeValue(`${paramName}[]`)
    const selector = `[name="${escapedName}"], [name="${escapedArrayName}"]`
    return Array.from(this.element.querySelectorAll(selector))
  }

  markFieldInvalid(field) {
    field.classList.add("is-invalid", "server-invalid")
    field.setAttribute("aria-invalid", "true")

    if (field.tagName === "SELECT") {
      const wrapper = field.tomselect?.wrapper || field.closest(".ts-wrapper")
      if (wrapper) {
        wrapper.classList.add("is-invalid", "server-invalid")
        wrapper.setAttribute("aria-invalid", "true")
      }
    }
  }

  focusFirstInvalidField() {
    const firstField =
      this.element.querySelector("input.server-invalid, select.server-invalid, textarea.server-invalid") ||
      this.element.querySelector(".ts-wrapper.server-invalid select")

    if (!firstField) return

    const tabPane = firstField.closest(".tab-pane")
    if (tabPane && !tabPane.classList.contains("active")) {
      this.openTabForPane(tabPane, () => this.scrollAndFocusField(firstField))
      return
    }

    this.scrollAndFocusField(firstField)
  }

  openTabForPane(tabPane, callback) {
    if (!tabPane?.id) {
      callback()
      return
    }

    const tabButton = this.tabTriggerForId(tabPane.id)
    if (!tabButton) {
      callback()
      return
    }

    const onShown = () => {
      tabButton.removeEventListener("ax:tab-shown", onShown)
      tabButton.removeEventListener("shown.bs.tab", onShown)
      requestAnimationFrame(callback)
    }

    tabButton.addEventListener("ax:tab-shown", onShown)
    tabButton.addEventListener("shown.bs.tab", onShown)

    // Ativa a aba via ax-tabs (clique no gatilho) ou fallback interno.
    if (tabButton.dataset.axTabsTargetParam) {
      tabButton.click()
      return
    }

    this.showTab(tabButton)
    requestAnimationFrame(callback)
  }

  scrollAndFocusField(field) {
    const focusTarget = field.tomselect?.wrapper || field.closest(".ts-wrapper") || field
    focusTarget.scrollIntoView({ behavior: "smooth", block: "center" })

    if (field.tomselect) {
      field.tomselect.focus()
      return
    }

    if (typeof field.focus === "function") {
      field.focus({ preventScroll: true })
    }
  }

  escapeAttributeValue(value) {
    return String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  }

  cadastroTypeChanged() {
    this.applyCadastroType(true)
  }

  statusChanged() {
    this.applySuspensionReasonVisibility(true)
  }

  applySuspensionReasonVisibility(fromUser = false) {
    if (!this.hasSuspensionReasonFieldTarget || !this.hasSuspensionReasonInputTarget || !this.hasStatusSelectTarget) return

    const visible = this.normalizedStatusValue() === "suspenso"
    this.suspensionReasonFieldTarget.classList.toggle("d-none", !visible)
    this.suspensionReasonInputTarget.disabled = !visible

    if (!visible && fromUser) {
      this.suspensionReasonInputTarget.value = ""
      this.suspensionReasonInputTarget.dispatchEvent(new Event("input", { bubbles: true }))
      this.suspensionReasonInputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }

  normalizedStatusValue() {
    return this.statusSelectTarget.value
      .toString()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .trim()
      .toLowerCase()
  }

  applyCadastroType(fromUser = false) {
    if (!this.hasCadastroTypeTarget || !this.hasCategoryTarget || !this.hasTipoTarget) return

    const typeKey = this.selectedCadastroTypeValue()
    const allowedCategories = this.categoriesByTypeValue[typeKey] || []
    const tipoValue = this.tipoByTypeValue[typeKey] || "Unitário"

    this.tipoTarget.value = tipoValue
    this.toggleUnitOnly(typeKey !== "empreendimento")
    this.syncDevelopmentNameLabel(typeKey)
    this.syncCategoryOptions(allowedCategories, fromUser, typeKey)
  }

  selectedCadastroTypeValue() {
    const radio = this.cadastroTypeTargets.find((target) => target.type === "radio" && target.checked)
    return radio?.value || this.cadastroTypeTarget.value
  }

  toggleUnitOnly(visible) {
    this.unitOnlyTargets.forEach((element) => {
      element.classList.toggle("d-none", !visible)
    })
  }

  syncDevelopmentNameLabel(typeKey) {
    if (!this.hasDevelopmentNameLabelTarget) return

    this.developmentNameLabelTarget.textContent =
      typeKey === "empreendimento" ? "Nome do empreendimento:" : "Nome do condomínio:"
  }

  syncCategoryOptions(allowedCategories, fromUser, typeKey) {
    const select = this.categoryTarget
    const currentValue = select.value
    const includeBlank = true
    const finalOptions = includeBlank ? ["", ...allowedCategories] : [...allowedCategories]

    if (select.tomselect) {
      const ts = select.tomselect
      ts.clearOptions()
      finalOptions.forEach((value) => {
        ts.addOption({ value: value, text: value || "Selecione..." })
      })

      const preferredValue = this.pickCategoryValue(currentValue, allowedCategories, fromUser, typeKey)
      ts.setValue(preferredValue || "", true)
      return
    }

    select.innerHTML = ""
    finalOptions.forEach((value) => {
      const option = new Option(value || "Selecione...", value)
      select.add(option)
    })
    select.value = this.pickCategoryValue(currentValue, allowedCategories, fromUser, typeKey)
  }

  pickCategoryValue(currentValue, allowedCategories, fromUser, typeKey) {
    if (typeKey === "empreendimento") return "Empreendimento"
    if (allowedCategories.includes(currentValue)) return currentValue
    if (fromUser) return ""
    return currentValue || ""
  }

  developmentChanged() {
    this.syncFromDevelopmentSelection(true)
  }

  syncFromDevelopmentSelection(fromUser = false) {
    if (!this.hasDevelopmentSelectTarget) return

    const developmentCode = this.developmentSelectTarget.value
    const developmentData = this.developmentsValue?.[developmentCode]

    this.toggleDevelopmentNameReadonly(Boolean(developmentCode))

    if (!developmentCode || !developmentData) return

    if (this.hasDevelopmentNameTarget && developmentData.nome_empreendimento) {
      this.developmentNameTarget.value = developmentData.nome_empreendimento
    }

    this.syncDevelopmentEditLink(developmentData.edit_url)
    this.syncDevelopmentRelationshipFields(developmentData)
    this.syncDevelopmentAddressFields(developmentData.address)
  }

  syncDevelopmentRelationshipFields(developmentData) {
    this.setSelectTargetValue("proprietorSelect", developmentData.proprietor_id)
    this.setSelectTargetValue("captadorSelect", developmentData.admin_user_id)
    this.setInputTargetValue("deliveryDate", developmentData.data_entrega)
    this.setSelectTargetValue("constructionProfileSelect", developmentData.perfil_construcao)
  }

  syncDevelopmentAddressFields(address = {}) {
    if (!address) return

    this.setSelectTargetValue("streetTypeSelect", address.tipo_endereco, { onlyWhenBlank: true })
    this.setInputTargetValue("street", address.logradouro, { onlyWhenBlank: true })
    this.setInputTargetValue("streetNumber", address.numero, { onlyWhenBlank: true })
    this.setSelectTargetValue("stateSelect", address.uf, { onlyWhenBlank: true })
    this.setInputTargetValue("zipCode", address.cep, { onlyWhenBlank: true })
    this.setSelectTargetValue("neighborhoodSelect", address.bairro, { onlyWhenBlank: true, createOption: true })
    this.setSelectTargetValue("commercialNeighborhoodSelect", address.bairro_comercial, { onlyWhenBlank: true, createOption: true })
    this.setSelectTargetValue("citySelect", address.cidade, { onlyWhenBlank: true, createOption: true })
  }

  setInputTargetValue(targetName, value, options = {}) {
    const input = this.optionalTarget(targetName)
    if (!this.canWriteField(input, value, options)) return

    input.value = String(value)
    input.dispatchEvent(new Event("input", { bubbles: true }))
    input.dispatchEvent(new Event("change", { bubbles: true }))
  }

  setSelectTargetValue(targetName, value, options = {}) {
    const select = this.optionalTarget(targetName)
    if (!this.canWriteField(select, value, options)) return

    this.setSelectValue(select, value, { createOption: options.createOption })
  }

  optionalTarget(targetName) {
    const predicateName = `has${targetName.charAt(0).toUpperCase()}${targetName.slice(1)}Target`
    if (!this[predicateName]) return null

    return this[`${targetName}Target`]
  }

  canWriteField(field, value, options = {}) {
    if (!field || value === undefined || value === null || String(value).trim() === "") return false
    if (field.disabled || field.readOnly) return false
    if (options.onlyWhenBlank && String(field.value || "").trim() !== "") return false
    return true
  }

  toggleDevelopmentNameReadonly(shouldBeReadonly) {
    if (!this.hasDevelopmentNameTarget) return
    this.developmentNameTarget.readOnly = shouldBeReadonly
  }

  syncDevelopmentEditLink(url) {
    if (!this.hasDevelopmentEditLinkTarget) return

    if (url) {
      this.developmentEditLinkTarget.href = url
      this.developmentEditLinkTarget.classList.remove("d-none")
      return
    }

    this.developmentEditLinkTarget.href = "#"
    this.developmentEditLinkTarget.classList.add("d-none")
  }

  setSelectValue(select, value, options = {}) {
    const finalValue = String(value)
    if (select.tomselect) {
      if (options.createOption && !select.tomselect.options[finalValue]) {
        select.tomselect.addOption({ value: finalValue, text: finalValue })
      }
      select.tomselect.setValue(finalValue, true)
      select.dispatchEvent(new Event("change", { bubbles: true }))
      return
    }

    if (options.createOption && !Array.from(select.options).some((option) => option.value === finalValue)) {
      select.add(new Option(finalValue, finalValue))
    }
    select.value = finalValue
    select.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
