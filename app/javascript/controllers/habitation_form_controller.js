import { Controller } from "@hotwired/stimulus"
import { setConditionalFieldsVisible, enforceExclusiveChoice } from "lib/conditional_fields"

export default class extends Controller {
  static targets = [
    "cadastroType",
    "category",
    "tipo",
    "statusSelect",
    "suspensionReasonField",
    "suspensionReasonInput",
    "inactiveStatusHint",
    "rentedStatusPanel",
    "soldStatusPanel",
    "rentedClosedValue",
    "soldClosedValue",
    "statusNegotiationModal",
    "statusNegotiationHint",
    "statusNegotiationLabel",
    "statusNegotiationCurrencyField",
    "statusNegotiationReasonField",
    "statusNegotiationValue",
    "statusNegotiationReason",
    "statusNegotiationError",
    "unitOnly",
    "developmentSelect",
    "developmentName",
    "developmentNameLabel",
    "developmentEditLink",
    "proprietorSelect",
    "captadorSelect",
    "deliveryDate",
    "constructionYear",
    "buildingFloors",
    "unitsPerFloor",
    "constructionProfileSelect",
    "useDevelopmentPhotos",
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
    detailFields: Object,
    legacyCategoryFields: Object,
    tipoByType: Object,
    developments: Object,
    newRecord: Boolean,
    errorFields: Array,
    validationRules: Array
  }

  connect() {
    this.refreshValidationBadgesBound = this.refreshValidationBadges.bind(this)
    this.categoryDependencyChanged = (event) => {
      if (this.hasCategoryTarget && ["Galpão", "Galpão em Condomínio"].includes(this.categoryTarget.value)) enforceExclusiveChoice(event.target, this.element)
      if (event.target.name === "habitation[caracteristicas][]") this.applyCategoryBehavior()
      if (event.target.name === "habitation[caracteristicas][]" && event.target.checked) {
        const normalize = (value) => value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
        const choice = normalize(event.target.value)
        if (["mobiliado", "sem mobilia"].includes(choice)) {
          this.findInputsByName("habitation[caracteristicas]").forEach((field) => {
            if (["mobiliado", "sem mobilia"].includes(normalize(field.value)) && field !== event.target && field.checked && !field.disabled) {
              field.checked = false
              field.dispatchEvent(new Event("change", { bubbles: true }))
            }
          })
        }
      }
    }
    this.element.addEventListener("change", this.categoryDependencyChanged)
    this.element.addEventListener("input", this.refreshValidationBadgesBound)
    this.element.addEventListener("change", this.refreshValidationBadgesBound)
    this.element.addEventListener("trix-change", this.refreshValidationBadgesBound)

    this.activateTabFromHash()
    this.applyCadastroType()
    this.previousCategory = this.categoryTarget?.value
    this.applyCategoryBehavior()
    this.applySuspensionReasonVisibility()
    this.applyInactiveStatusVisibility()
    this.previousStatusValue = this.hasStatusSelectTarget ? this.statusSelectTarget.value : ""
    this.statusNegotiationConfirmed = false
    this.syncFromDevelopmentSelection()
    this.applyServerValidationErrors()
    this.refreshValidationBadges()
    this.resetWorkspaceHorizontalScroll()
  }

  resetWorkspaceHorizontalScroll() {
    const workspace = this.element.querySelector(".habitation-editor-workspace")
    if (!workspace) return

    window.requestAnimationFrame(() => {
      workspace.scrollLeft = 0
    })
  }

  disconnect() {
    this.element.removeEventListener("change", this.categoryDependencyChanged)
    this.element.removeEventListener("input", this.refreshValidationBadgesBound)
    this.element.removeEventListener("change", this.refreshValidationBadgesBound)
    this.element.removeEventListener("trix-change", this.refreshValidationBadgesBound)
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

  refreshValidationBadges() {
    const counts = this.currentValidationCounts()
    const statuses = Array.from(this.element.querySelectorAll("[data-habitation-form-tab-status]")).filter((node) => !this.element.querySelector(`#${node.dataset.habitationFormTabStatus}`)?.hidden)

    statuses.forEach((status) => {
      const tab = status.dataset.habitationFormTabStatus
      const count = counts[tab] || 0
      status.innerHTML = count > 0 ? this.missingBadgeHtml(count) : this.completeIconHtml()
    })

    this.element.querySelectorAll("[data-habitation-form-tab-rail-status]").forEach((button) => {
      const tab = button.dataset.habitationFormTabRailStatus
      const count = counts[tab] || 0
      button.querySelectorAll(".ax-tab-missing, .ax-tab-error").forEach((badge) => badge.remove())
      if (count > 0) button.insertAdjacentHTML("beforeend", this.missingBadgeHtml(count))
    })

    this.refreshProgress(counts, statuses)
  }

  currentValidationCounts() {
    const counts = {}
    const rules = this.hasValidationRulesValue ? this.validationRulesValue : []

    rules.forEach((rule) => {
      if (this.ruleSatisfied(rule)) return

      const fields = (rule.names || rule.groups?.flat() || []).flatMap((name) => this.fieldsForName(name))
      if (fields.length && fields.every((field) => field.disabled)) return
      const tab = fields.find((field) => !field.disabled)?.closest(".tab-pane")?.id || String(rule.tab || "general")
      counts[tab] = (counts[tab] || 0) + 1
    })

    return counts
  }

  ruleSatisfied(rule) {
    const mode = String(rule.mode || "any_present")
    if (mode === "all_present") return (rule.names || []).every((name) => this.nameHasValue(name))
    if (mode === "checked_any") return (rule.names || []).some((name) => this.nameHasCheckedValue(name))
    if (mode === "positive_any") return (rule.names || []).some((name) => this.nameHasPositiveValue(name))
    if (mode === "file_present") return (rule.names || []).some((name) => this.nameHasFileValue(name))
    if (mode === "groups_present") {
      return (rule.groups || []).every((group) => group.some((name) => this.nameHasValue(name)))
    }

    return (rule.names || []).some((name) => this.nameHasValue(name))
  }

  nameHasValue(name) {
    return this.fieldsForName(name).some((field) => this.fieldValuePresent(field))
  }

  nameHasCheckedValue(name) {
    return this.fieldsForName(name).some((field) => field.checked && this.fieldValuePresent(field))
  }

  nameHasPositiveValue(name) {
    return this.fieldsForName(name).some((field) => this.numericValue(field) > 0)
  }

  nameHasFileValue(name) {
    return this.fieldsForName(name).some((field) => field.files && field.files.length > 0)
  }

  fieldsForName(name) {
    const exact = this.escapeAttributeValue(name)
    return Array.from(this.element.querySelectorAll(`[name="${exact}"]`))
  }

  fieldValuePresent(field) {
    if (!field || field.disabled) return false
    if (field.type === "checkbox" || field.type === "radio") return field.checked
    if (field.type === "file") return field.files && field.files.length > 0

    return String(field.value || "").replace(/<[^>]*>/g, "").trim() !== ""
  }

  numericValue(field) {
    const value = String(field?.value || "")
      .replace(/[^\d,.-]/g, "")
      .replace(/\./g, "")
      .replace(",", ".")

    return Number.parseFloat(value) || 0
  }

  missingBadgeHtml(count) {
    return `<span class="ax-tab-missing" title="${count} validação(ões) faltante(s)">${count}</span>`
  }

  completeIconHtml() {
    return '<i class="bi bi-check-circle-fill habitation-tabs-bar__ind habitation-tabs-bar__ind--success" title="Completo" aria-hidden="true"></i>'
  }

  refreshProgress(counts, statuses) {
    const total = statuses.length
    if (total === 0) return

    const completed = statuses.filter((status) => {
      const tab = status.dataset.habitationFormTabStatus
      return (counts[tab] || 0) === 0
    }).length
    const percent = Math.round((completed / total) * 100)

    this.element.querySelectorAll("[data-habitation-form-progress-count]").forEach((node) => {
      node.textContent = `${completed}/${total}`
    })
    this.element.querySelectorAll("[data-habitation-form-progress-bar]").forEach((node) => {
      node.value = percent
      node.textContent = `${percent}%`
      node.setAttribute("aria-label", `Progresso do cadastro: ${percent}%`)
    })
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

  fieldApplicable(name, category = this.categoryTarget.value) {
    const group = this.selectedCadastroTypeValue()
    const warehouse = ["Galpão", "Galpão em Condomínio"].includes(category)
    const config = this.detailFieldsValue?.[name]
    if (config) {
      if (config.group === "warehouse") return warehouse
      return group === "terrenos"
    }
    if (["dormitorios_qtd", "suites_qtd", "demi_suites_qtd", "varandas_qtd", "hidromassagem_qtd"].includes(name)) return group === "imoveis_residenciais"
    if (["salas_qtd", "banheiros_qtd", "vagas_qtd", "tipo_vaga", "numero_box", "andar"].includes(name)) return !["terrenos", "empreendimento"].includes(group)
    return true
  }

  categoryChanged() {
    if (this.categoryTarget.value === this.previousCategory) return
    const fields = Object.keys(this.detailFieldsValue || {}).filter((name) => !this.fieldApplicable(name))
    const populated = fields.filter((name) => this.findInputsByName(`habitation[${name}]`).some((field) => {
      return field.tagName === "SELECT" && field.multiple ? field.selectedOptions.length > 0 : String(field.value || "").trim() !== ""
    }))
    const incompatibleChecks = Array.from(this.element.querySelectorAll("[data-category-options]")).filter((node) => {
      if (JSON.parse(node.dataset.categoryOptions).includes(this.categoryTarget.value)) return false
      return Boolean(node.querySelector("input:checked") || Array.from(node.querySelectorAll("select")).some((field) => String(field.value || "").trim() !== ""))
    })
    const legacyLabels = Object.entries(this.legacyCategoryFieldsValue || {}).filter(([name]) => !this.fieldApplicable(name)).map(([, config]) => config.label)
    const labels = populated.map((name) => this.detailFieldsValue[name].label).concat(incompatibleChecks.map((node) => {
      const field = node.querySelector("input:checked") || Array.from(node.querySelectorAll("select")).find((select) => String(select.value || "").trim() !== "")
      return field.value
    }), legacyLabels)
    if (labels.length && !window.confirm("A categoria escolhida não utiliza: " + labels.join(", ") + ". Ao salvar, os valores anteriores ficarão no histórico. Continuar?")) {
      if (this.categoryTarget.tomselect) this.categoryTarget.tomselect.setValue(this.previousCategory, true)
      else this.categoryTarget.value = this.previousCategory
      return
    }
    const confirmation = this.element.querySelector('[name="habitation[confirm_category_change]"]')
    if (confirmation) confirmation.value = "1"
    this.previousCategory = this.categoryTarget.value
    this.applyCategoryBehavior()
  }

  applyCategoryBehavior() {
    if (!this.hasCategoryTarget) return
    const category = this.categoryTarget.value
    const commercialUnit = ["Sala Comercial", "Ponto Comercial", "Loja"].includes(category)
    const development = this.selectedCadastroTypeValue() === "empreendimento"
    this.element.querySelectorAll("[data-category-field]").forEach((wrapper) => {
      const name = wrapper.dataset.categoryField
      let visible = this.fieldApplicable(name)
      if (name === "outra_operacao_galpao") {
        visible = visible && Boolean(this.element.querySelector('input[name="habitation[caracteristicas][]"][value="Outra operação"]:checked'))
        const input = wrapper.querySelector("input")
        if (input) input.required = visible
      }
      setConditionalFieldsVisible(wrapper, visible)
    })
    const detailSection = this.element.querySelector("[data-category-details-section]")
    if (detailSection) this.setVisible(detailSection, Array.from(detailSection.querySelectorAll("[data-category-field]")).some((node) => !node.hidden))
    this.element.querySelectorAll("[data-category-options]").forEach((node) => {
      setConditionalFieldsVisible(node, JSON.parse(node.dataset.categoryOptions).includes(category))
    })
    this.element.querySelectorAll("[data-residential-land-field]").forEach((node) => {
      const field = node.querySelector("input, select")
      const apartment = ["Apartamento", "Cobertura", "Loft"].includes(category)
      setConditionalFieldsVisible(node, !apartment || Boolean(field?.value))
    })
    const builtArea = this.element.querySelector("[data-existing-built-area]")
    if (builtArea) {
      const warehouse = ["Galpão", "Galpão em Condomínio"].includes(category)
      setConditionalFieldsVisible(builtArea, warehouse || Boolean(builtArea.querySelector("input")?.value))
      const label = builtArea.querySelector("label")
      if (label) label.textContent = warehouse ? "Área construída" : "Área útil"
    }
    const roomsLabel = this.element.querySelector('label[for="habitation_salas_qtd"]')
    if (roomsLabel) roomsLabel.textContent = commercialUnit ? "Número de ambientes" : "Salas"
    this.moveCategorySection("[data-category-public-text]", development ? "[data-category-public-text-destination]" : null)
    this.moveCategorySection("[data-category-infrastructure]", commercialUnit ? "[data-category-infrastructure-destination]" : null)
    this.moveCategorySection("[data-category-floors]", commercialUnit ? "[data-category-floors-destination]" : null)
    const floorsDestination = this.element.querySelector("[data-category-floors-destination]")
    if (floorsDestination) this.setVisible(floorsDestination, commercialUnit)
    const floorsLabel = this.element.querySelector('label[for="habitation_andares_qtd"]')
    if (floorsLabel) floorsLabel.textContent = commercialUnit ? "Número de pavimentos" : "Nº andares"
    this.toggleCategoryTab("features", !development)
    this.toggleCategoryTab("infra", !commercialUnit)
    this.refreshValidationBadges()
  }

  moveCategorySection(selector, destinationSelector) {
    const node = this.element.querySelector(selector)
    if (!node) return
    if (!node.categoryHome) {
      node.categoryHome = document.createComment("category section")
      node.before(node.categoryHome)
    }
    const destination = destinationSelector && this.element.querySelector(destinationSelector)
    if (destination) destination.append(node)
    else node.categoryHome.after(node)
  }

  toggleCategoryTab(id, visible) {
    this.element.querySelectorAll(`[data-ax-tabs-target-param="#${id}"], [data-bs-target="#${id}"]`).forEach((trigger) => this.setVisible(trigger, visible))
    const pane = this.element.querySelector(`#${id}`)
    if (!visible && pane?.classList.contains("active")) this.showTab(this.tabTriggerForId("general"))
    // Text and infrastructure have already moved, so no duplicate input is submitted.
    setConditionalFieldsVisible(pane, visible)
  }

  cadastroTypeChanged() {
    this.applyCadastroType(true)
  }

  statusChanged() {
    this.applySuspensionReasonVisibility(true)
    this.applyInactiveStatusVisibility()
    this.maybeOpenStatusNegotiationModal()
  }

  applySuspensionReasonVisibility(fromUser = false) {
    if (!this.hasSuspensionReasonInputTarget || !this.hasStatusSelectTarget) return

    const visible = this.normalizedStatusValue() === "suspenso"
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

  applyInactiveStatusVisibility() {
    if (!this.hasStatusSelectTarget) return

    const status = this.normalizedStatusValue()
    const rented = this.statusKind(status) === "rented"
    const sold = this.statusKind(status) === "sold"

    if (this.hasRentedStatusPanelTarget) this.setConditionalSectionState(this.rentedStatusPanelTarget, rented)
    if (this.hasSoldStatusPanelTarget) this.setConditionalSectionState(this.soldStatusPanelTarget, sold)
    if (this.hasInactiveStatusHintTarget) this.setVisible(this.inactiveStatusHintTarget, !rented && !sold)
  }

  maybeOpenStatusNegotiationModal() {
    if (!this.hasStatusNegotiationModalTarget || !this.hasStatusNegotiationValueTarget) {
      this.previousStatusValue = this.statusSelectTarget.value
      return
    }

    const status = this.normalizedStatusValue()
    const kind = this.statusKind(status)
    if (!kind) {
      this.previousStatusValue = this.statusSelectTarget.value
      return
    }

    const target = this.statusNegotiationTargetFor(kind)
    if (String(target.value || "").trim().length > 0) {
      this.previousStatusValue = this.statusSelectTarget.value
      return
    }

    this.pendingStatusNegotiationKind = kind
    this.statusNegotiationConfirmed = false
    this.statusNegotiationValueTarget.value = ""
    if (this.hasStatusNegotiationReasonTarget) this.statusNegotiationReasonTarget.value = ""
    if (this.hasStatusNegotiationErrorTarget) this.statusNegotiationErrorTarget.hidden = true
    this.configureStatusNegotiationModal(kind)
    this.statusNegotiationModalTarget.dispatchEvent(new CustomEvent("ax-modal:open", { bubbles: true }))
  }

  statusKind(status = this.normalizedStatusValue()) {
    if (status.includes("alugado")) return "rented"
    if (status.includes("vendido")) return "sold"
    if (status.includes("suspenso")) return "suspended"

    return null
  }

  statusNegotiationTargetFor(kind) {
    if (kind === "rented") return this.rentedClosedValueTarget
    if (kind === "sold") return this.soldClosedValueTarget
    return this.suspensionReasonInputTarget
  }

  configureStatusNegotiationModal(kind) {
    const isSuspended = kind === "suspended"
    this.setVisible(this.statusNegotiationCurrencyFieldTarget, !isSuspended)
    this.setVisible(this.statusNegotiationReasonFieldTarget, isSuspended)

    if (this.hasStatusNegotiationLabelTarget) {
      this.statusNegotiationLabelTarget.textContent = kind === "rented" ? "Valor de aluguel:" : "Valor de venda:"
    }

    if (this.hasStatusNegotiationHintTarget) {
      if (kind === "rented") this.statusNegotiationHintTarget.textContent = "Informe o valor pelo qual a locação foi fechada."
      if (kind === "sold") this.statusNegotiationHintTarget.textContent = "Informe o valor pelo qual a venda foi fechada."
      if (kind === "suspended") this.statusNegotiationHintTarget.textContent = "Informe o motivo da suspensão para registrar no histórico do imóvel."
    }

    if (this.hasStatusNegotiationErrorTarget) {
      this.statusNegotiationErrorTarget.textContent = isSuspended
        ? "Informe o motivo para continuar."
        : "Informe o valor para continuar."
    }
  }

  confirmStatusNegotiation(event) {
    event?.preventDefault()
    const kind = this.pendingStatusNegotiationKind
    const input = kind === "suspended" ? this.statusNegotiationReasonTarget : this.statusNegotiationValueTarget
    const value = String(input?.value || "").trim()
    if (!value) {
      if (this.hasStatusNegotiationErrorTarget) this.statusNegotiationErrorTarget.hidden = false
      input?.focus()
      return
    }

    const target = this.statusNegotiationTargetFor(kind)
    target.value = value
    target.dispatchEvent(new Event("input", { bubbles: true }))
    target.dispatchEvent(new Event("change", { bubbles: true }))
    this.statusNegotiationConfirmed = true
    this.previousStatusValue = this.statusSelectTarget.value
    this.statusNegotiationModalTarget.dispatchEvent(new CustomEvent("ax-modal:close", { bubbles: true }))
    this.submitStatusNegotiation(event?.currentTarget?.dataset?.saveChoice || "stay")
  }

  cancelStatusNegotiation(event) {
    event?.preventDefault()
    this.revertPendingStatusNegotiation()
    this.statusNegotiationConfirmed = true
    this.statusNegotiationModalTarget.dispatchEvent(new CustomEvent("ax-modal:close", { bubbles: true }))
  }

  statusNegotiationClosed() {
    if (this.statusNegotiationConfirmed) return

    this.revertPendingStatusNegotiation()
  }

  revertPendingStatusNegotiation() {
    if (!this.hasStatusSelectTarget) return

    if (this.statusSelectTarget.tomselect) {
      this.statusSelectTarget.tomselect.setValue(this.previousStatusValue || "", true)
    } else {
      this.statusSelectTarget.value = this.previousStatusValue || ""
    }
    this.applySuspensionReasonVisibility(false)
    this.applyInactiveStatusVisibility()
  }

  submitStatusNegotiation(choice) {
    const form = this.element.querySelector("#admin_habitation_form")
    if (!form) return

    const submitter = Array.from(form.querySelectorAll('button[name="save_navigation"]'))
      .find((button) => button.value === choice) ||
      form.querySelector('button[name="save_navigation"][value="stay"]')
    const choiceInput = form.querySelector('input[name="save_navigation"]')
    if (choiceInput) choiceInput.value = choice

    if (submitter) {
      form.requestSubmit(submitter)
    } else {
      form.requestSubmit()
    }
  }

  setConditionalSectionState(section, enabled) {
    this.setVisible(section, enabled)
    section.querySelectorAll("input, select, textarea, button").forEach((field) => {
      field.disabled = !enabled
      if (field.dataset.conditionalRequired === "true") field.required = enabled

      if (field.tomselect) {
        enabled ? field.tomselect.enable() : field.tomselect.disable()
      }
    })
  }

  applyCadastroType(fromUser = false) {
    if (!this.hasCadastroTypeTarget || !this.hasCategoryTarget || !this.hasTipoTarget) return

    const typeKey = this.selectedCadastroTypeValue()
    const allowedCategories = [...(this.categoriesByTypeValue[typeKey] || [])]
    if (!fromUser && !this.newRecordValue && this.categoryTarget.value && !allowedCategories.includes(this.categoryTarget.value)) allowedCategories.push(this.categoryTarget.value)
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
      this.setVisible(element, visible)
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
    if (allowedCategories.includes(currentValue)) return currentValue
    if (typeKey === "empreendimento") return "Empreendimento"
    if (fromUser) return ""
    return currentValue || ""
  }

  developmentChanged() {
    this.syncFromDevelopmentSelection(true)
    this.applyCategoryBehavior()
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
    this.syncDevelopmentRelationshipFields(developmentData, { overwrite: fromUser })
    this.syncDevelopmentAddressFields(developmentData.address, { overwrite: fromUser })
    if (fromUser || this.newRecordValue) this.syncDevelopmentInfrastructure(developmentData.infra_estrutura)
    if (fromUser) this.enableDevelopmentPhotosFallback()
  }

  syncDevelopmentInfrastructure(values = []) {
    const selected = new Set(values)
    this.element.querySelectorAll('input[name="habitation[infra_estrutura][]"]').forEach((input) => {
      if (input.disabled || input.checked || !selected.has(input.value)) return

      input.checked = true
      input.dispatchEvent(new Event("change", { bubbles: true }))
    })
  }

  syncDevelopmentRelationshipFields(developmentData, { overwrite = false } = {}) {
    const options = { onlyWhenBlank: !overwrite }
    this.setInputTargetValue("constructionYear", developmentData.ano_construcao, options)
    this.setInputTargetValue("buildingFloors", developmentData.andares_qtd, options)
    this.setInputTargetValue("unitsPerFloor", developmentData.aptos_andar, options)
    this.setInputTargetValue("deliveryDate", developmentData.data_entrega)
    this.setSelectTargetValue("constructionProfileSelect", developmentData.perfil_construcao)
  }

  enableDevelopmentPhotosFallback() {
    const input = this.optionalTarget("useDevelopmentPhotos")
    if (!input || input.checked) return

    input.checked = true
    input.dispatchEvent(new Event("change", { bubbles: true }))
  }

  syncDevelopmentAddressFields(address = {}, options = {}) {
    if (!address) return

    const fieldOptions = { onlyWhenBlank: !options.overwrite }
    this.setSelectTargetValue("streetTypeSelect", address.tipo_endereco, fieldOptions)
    this.setInputTargetValue("street", address.logradouro, fieldOptions)
    this.setInputTargetValue("streetNumber", address.numero, fieldOptions)
    this.setSelectTargetValue("stateSelect", address.uf, fieldOptions)
    this.setInputTargetValue("zipCode", address.cep, fieldOptions)
    this.setSelectTargetValue("neighborhoodSelect", address.bairro, { ...fieldOptions, createOption: true })
    this.setSelectTargetValue("commercialNeighborhoodSelect", address.bairro_comercial, { ...fieldOptions, createOption: true })
    this.setSelectTargetValue("citySelect", address.cidade, { ...fieldOptions, createOption: true })
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

    if (select.tagName !== "SELECT") {
      select.value = String(value)
      select.dispatchEvent(new Event("input", { bubbles: true }))
      select.dispatchEvent(new Event("change", { bubbles: true }))
      return
    }

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
      this.setVisible(this.developmentEditLinkTarget, true)
      return
    }

    this.developmentEditLinkTarget.href = "#"
    this.setVisible(this.developmentEditLinkTarget, false)
  }

  setVisible(element, visible) {
    element.hidden = !visible
    element.classList.toggle("tw-hidden", !visible)
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
