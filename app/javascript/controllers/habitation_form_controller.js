import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "cadastroType",
    "category",
    "tipo",
    "unitOnly",
    "developmentSelect",
    "developmentName",
    "developmentNameLabel",
    "developmentEditLink",
    "constructorSelect",
    "missingConstructorAlert",
    "constructorName",
    "constructorWebsite",
    "constructorSubmit",
    "constructorFeedback"
  ]

  static values = {
    categoriesByType: Object,
    tipoByType: Object,
    developments: Object,
    errorFields: Array
  }

  connect() {
    this.tabClickHandler = (event) => this.activateClickedTab(event)
    this.element.addEventListener("click", this.tabClickHandler)
    this.activateTabFromHash()
    this.applyCadastroType()
    this.syncFromDevelopmentSelection()
    this.applyServerValidationErrors()
  }

  disconnect() {
    if (this.tabClickHandler) {
      this.element.removeEventListener("click", this.tabClickHandler)
    }
  }

  activateTabFromHash() {
    const tabId = window.location.hash?.replace("#", "")
    if (!tabId) return

    const trigger = document.querySelector(`[data-bs-target="#${CSS.escape(tabId)}"]`)
    if (trigger && window.bootstrap?.Tab) {
      window.bootstrap.Tab.getOrCreateInstance(trigger).show()
    } else if (trigger) {
      this.showTab(trigger)
    }
  }

  activateClickedTab(event) {
    const trigger = event.target.closest('[data-bs-toggle="tab"][data-bs-target]')
    if (!trigger || !this.element.contains(trigger)) return

    requestAnimationFrame(() => this.ensureTabPaneVisible(trigger))
  }

  ensureTabPaneVisible(trigger) {
    const targetSelector = trigger.getAttribute("data-bs-target")
    if (!targetSelector) return

    const pane = this.element.querySelector(targetSelector)
    if (pane?.classList.contains("show") && pane.classList.contains("active")) return

    this.showTab(trigger)
  }

  showTab(trigger) {
    const targetSelector = trigger.getAttribute("data-bs-target")
    if (!targetSelector) return

    const pane = this.element.querySelector(targetSelector)
    if (!pane) return

    const tabList = trigger.closest('[role="tablist"]')
    tabList?.querySelectorAll('[data-bs-toggle="tab"][data-bs-target]').forEach((tab) => {
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

    const tabButton = this.element.querySelector(`[data-bs-target="#${tabPane.id}"]`)
    if (!tabButton) {
      callback()
      return
    }

    const onShown = () => {
      tabButton.removeEventListener("shown.bs.tab", onShown)
      requestAnimationFrame(callback)
    }

    tabButton.addEventListener("shown.bs.tab", onShown)

    if (window.bootstrap?.Tab?.getOrCreateInstance) {
      window.bootstrap.Tab.getOrCreateInstance(tabButton).show()
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
    this.toggleMissingConstructorAlert(false)

    if (!developmentCode || !developmentData) return

    if (this.hasDevelopmentNameTarget && developmentData.nome_empreendimento) {
      this.developmentNameTarget.value = developmentData.nome_empreendimento
    }

    this.syncDevelopmentEditLink(developmentData.edit_url)
    this.toggleMissingConstructorAlert(!developmentData.constructor_id)

    // Só sobrescreve a construtora se o empreendimento tiver construtora definida.
    if (developmentData.constructor_id && this.hasConstructorSelectTarget) {
      this.setSelectValue(this.constructorSelectTarget, developmentData.constructor_id)
    } else if (fromUser) {
      // Não limpa uma seleção manual existente quando o empreendimento não tiver construtora.
    }
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

  setSelectValue(select, value) {
    const finalValue = String(value)
    if (select.tomselect) {
      select.tomselect.setValue(finalValue, true)
      return
    }

    select.value = finalValue
  }

  toggleMissingConstructorAlert(visible) {
    if (!this.hasMissingConstructorAlertTarget) return
    this.missingConstructorAlertTarget.classList.toggle("d-none", !visible)
    if (!visible) this.syncDevelopmentEditLink(null)
  }

  async createConstructor(event) {
    event.preventDefault()
    if (!this.hasConstructorSelectTarget || !this.hasConstructorNameTarget) return

    const name = this.constructorNameTarget.value.trim()
    const websiteUrl = this.hasConstructorWebsiteTarget ? this.constructorWebsiteTarget.value.trim() : ""

    if (!name) {
      this.showConstructorFeedback("Informe o nome da construtora.", "danger")
      return
    }

    this.setConstructorSubmitting(true)

    try {
      const response = await fetch("/admin/constructors.json", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        credentials: "same-origin",
        body: JSON.stringify({
          constructor: { name: name, website_url: websiteUrl }
        })
      })

      const payload = await response.json().catch(() => ({}))

      if (!response.ok) {
        const msg = payload?.errors?.join(", ") || `Erro ao salvar construtora (HTTP ${response.status}).`
        this.showConstructorFeedback(msg, "danger")
        return
      }

      this.appendConstructorOption(payload)
      this.showConstructorFeedback("Construtora cadastrada e selecionada.", "success")
      this.constructorNameTarget.value = ""
      if (this.hasConstructorWebsiteTarget) this.constructorWebsiteTarget.value = ""
      this.closeConstructorModal()
    } catch (_error) {
      this.showConstructorFeedback("Falha de conexão ao cadastrar construtora.", "danger")
    } finally {
      this.setConstructorSubmitting(false)
    }
  }

  appendConstructorOption(constructor) {
    const select = this.constructorSelectTarget
    if (select.tomselect) {
      select.tomselect.addOption({ value: String(constructor.id), text: constructor.name })
      select.tomselect.addItem(String(constructor.id), true)
    } else {
      const option = new Option(constructor.name, constructor.id, true, true)
      select.add(option)
      select.value = String(constructor.id)
    }
  }

  setConstructorSubmitting(isSubmitting) {
    if (!this.hasConstructorSubmitTarget) return
    this.constructorSubmitTarget.disabled = isSubmitting
    this.constructorSubmitTarget.innerHTML = isSubmitting
      ? '<span class="spinner-border spinner-border-sm me-1" role="status"></span>Salvando...'
      : '<i class="bi bi-check2 me-1"></i>Salvar construtora'
  }

  showConstructorFeedback(message, type) {
    if (!this.hasConstructorFeedbackTarget) return
    this.constructorFeedbackTarget.className = `alert alert-${type} py-2 px-3 small mb-0`
    this.constructorFeedbackTarget.textContent = message
    this.constructorFeedbackTarget.classList.remove("d-none")
  }

  closeConstructorModal() {
    const modalElement = document.getElementById("quickAddConstructorModal")
    if (!modalElement || typeof bootstrap === "undefined" || !bootstrap.Modal) return
    const modal = bootstrap.Modal.getInstance(modalElement) || new bootstrap.Modal(modalElement)
    modal.hide()
  }
}
