import { Controller } from "@hotwired/stimulus"

const CHOICE_TYPES = new Set(["select", "radio", "checkbox"])
const MASKABLE_TYPES = new Set(["text", "tel", "number", "currency"])
const TYPE_LABELS = {
  text: "Texto",
  email: "E-mail",
  tel: "Telefone",
  url: "URL",
  search: "Busca",
  number: "Número",
  currency: "Valor",
  date: "Data",
  time: "Hora",
  "datetime-local": "Data e hora",
  month: "Mês",
  week: "Semana",
  color: "Cor",
  range: "Faixa",
  textarea: "Texto longo",
  select: "Seleção",
  radio: "Múltipla escolha",
  checkbox: "Checkbox",
  file: "Anexo",
  hidden: "Campo oculto"
}
const PLACEHOLDERS = {
  text: "Digite o texto",
  email: "email@exemplo.com",
  tel: "WhatsApp / Telefone",
  url: "https://",
  search: "Digite a busca",
  number: "Digite um número",
  currency: "R$ 0,00",
  date: "Selecione a data",
  time: "",
  "datetime-local": "",
  month: "",
  week: "",
  color: "",
  range: "",
  textarea: "Digite os detalhes",
  select: "Selecione",
  file: "",
  hidden: ""
}
const DEFAULT_OPTIONS = {
  select: "Opção 1|opcao_1\nOpção 2|opcao_2",
  radio: "Opção 1|opcao_1\nOpção 2|opcao_2",
  checkbox: "Aceito|aceito"
}
const FIELD_TYPES = new Set(Object.keys(TYPE_LABELS))

export default class extends Controller {
  static targets = ["list", "template", "empty", "counter", "bulkInput"]

  connect() {
    this.refresh()
  }

  add(event) {
    const type = event.currentTarget.dataset.fieldType || "text"
    const field = this.buildField(type)

    this.listTarget.appendChild(field)
    this.refresh()
    this.labelInput(field)?.focus()
  }

  addBulk() {
    if (!this.hasBulkInputTarget) return

    const rows = this.bulkInputTarget.value
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)

    rows.forEach((row) => {
      const [rawLabel, rawType, rawName, rawRequired, rawOptions] = row.split(";").map((part) => part?.trim())
      const normalizedType = (rawType || "").toLowerCase()
      const type = FIELD_TYPES.has(normalizedType) ? normalizedType : "text"
      const label = rawLabel || TYPE_LABELS[type] || "Campo"
      const options = rawOptions
        ? rawOptions.split(",").map((option) => option.trim()).filter(Boolean).join("\n")
        : undefined
      const field = this.buildField(type, {
        label,
        name: rawName,
        required: /^(1|sim|s|true|obrigatorio|required)$/i.test(rawRequired || ""),
        options
      })

      this.listTarget.appendChild(field)
    })

    if (rows.length > 0) {
      this.bulkInputTarget.value = ""
      this.refresh()
    }
  }

  // Atalho de formato: preenche a máscara do campo (e zera o seletor).
  maskPreset(event) {
    const select = event.currentTarget
    const input = this.fieldFromEvent(event)?.querySelector("[data-public-form-builder-target~='maskInput']")
    if (!input || !select.value) return

    input.value = select.value
    select.value = ""
    input.dispatchEvent(new Event("input", { bubbles: true }))
  }

  toggle(event) {
    const field = this.fieldFromEvent(event)
    if (!field) return

    const open = field.classList.toggle("is-open")
    event.currentTarget.setAttribute("aria-expanded", open)
  }

  dragStart(event) {
    this.dragged = this.fieldFromEvent(event)
    if (!this.dragged) return

    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", "")
    event.dataTransfer.setDragImage(this.dragged, 20, 20)
    this.dragged.classList.add("is-dragging")
  }

  dragOver(event) {
    if (!this.dragged) return

    event.preventDefault()
    const before = this.visibleFields()
      .filter((field) => field !== this.dragged)
      .find((field) => {
        const rect = field.getBoundingClientRect()
        return event.clientY < rect.top + rect.height / 2
      })

    if (before) this.listTarget.insertBefore(this.dragged, before)
    else this.listTarget.appendChild(this.dragged)
  }

  dragEnd() {
    this.dragged?.classList.remove("is-dragging")
    this.dragged = null
    this.refresh()
  }

  duplicate(event) {
    const source = this.fieldFromEvent(event)
    if (!source) return

    const type = this.typeInput(source)?.value || "text"
    const field = this.buildField(type)

    this.labelInput(field).value = `${this.labelInput(source)?.value || TYPE_LABELS[type] || "Campo"} cópia`
    this.nameInput(field).value = this.uniqueName(this.slugify(this.labelInput(field).value))
    this.nameInput(field).dataset.autoName = "true"
    this.placeholderInput(field).value = this.placeholderInput(source)?.value || ""
    this.optionsInput(field).value = this.optionsInput(source)?.value || DEFAULT_OPTIONS[type] || ""
    this.requiredInput(field).checked = Boolean(this.requiredInput(source)?.checked)
    source.querySelectorAll("[data-file-setting], [data-config-setting]").forEach((input) => {
      const setting = input.dataset.fileSetting ? `[data-file-setting='${input.dataset.fileSetting}']` : `[data-config-setting='${input.dataset.configSetting}']`
      const copy = field.querySelector(setting)
      if (!copy) return
      if (input.type === "checkbox") copy.checked = input.checked
      else copy.value = input.value
    })

    source.insertAdjacentElement("afterend", field)
    this.refresh()
  }

  remove(event) {
    const field = this.fieldFromEvent(event)
    if (!field) return

    const destroyInput = this.destroyInput(field)
    const persisted = Boolean(field.querySelector("input[name$='[id]']"))

    if (persisted && destroyInput) {
      destroyInput.value = "1"
      field.hidden = true
    } else {
      field.remove()
    }

    this.refresh()
  }

  moveUp(event) {
    const field = this.fieldFromEvent(event)
    const previous = this.visibleFieldBefore(field)
    if (!field || !previous) return

    this.listTarget.insertBefore(field, previous)
    this.refresh()
  }

  moveDown(event) {
    const field = this.fieldFromEvent(event)
    const next = this.visibleFieldAfter(field)
    if (!field || !next) return

    this.listTarget.insertBefore(next, field)
    this.refresh()
  }

  fieldTypeChanged(event) {
    const field = this.fieldFromEvent(event)
    if (!field) return

    const type = event.currentTarget.value
    field.dataset.fieldType = type
    const optionsInput = this.optionsInput(field)

    if (CHOICE_TYPES.has(type) && optionsInput && optionsInput.value.trim() === "") {
      optionsInput.value = DEFAULT_OPTIONS[type] || ""
    }

    if (this.placeholderInput(field) && this.placeholderInput(field).value.trim() === "") {
      this.placeholderInput(field).value = PLACEHOLDERS[type] || ""
    }

    this.syncChoiceState(field)
    this.refresh()
  }

  labelChanged(event) {
    const field = this.fieldFromEvent(event)
    const labelInput = event.currentTarget
    const nameInput = this.nameInput(field)
    if (!nameInput) return

    if (nameInput.dataset.autoName !== "false") {
      nameInput.value = this.uniqueName(this.slugify(labelInput.value), field)
      nameInput.dataset.autoName = "true"
    }

    this.refresh()
  }

  nameChanged(event) {
    event.currentTarget.dataset.autoName = event.currentTarget.value.trim() === "" ? "true" : "false"
  }

  buildField(type, overrides = {}) {
    const token = `${Date.now()}${Math.floor(Math.random() * 100000)}`
    const wrapper = document.createElement("div")
    wrapper.innerHTML = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, token).trim()
    const field = wrapper.firstElementChild

    const label = overrides.label || TYPE_LABELS[type] || "Campo"
    this.typeInput(field).value = type
    this.labelInput(field).value = label
    this.nameInput(field).value = this.uniqueName(this.slugify(overrides.name || label))
    this.nameInput(field).dataset.autoName = "true"
    this.placeholderInput(field).value = overrides.placeholder ?? PLACEHOLDERS[type] ?? ""
    this.optionsInput(field).value = overrides.options ?? DEFAULT_OPTIONS[type] ?? ""
    this.requiredInput(field).checked = Boolean(overrides.required)
    field.dataset.fieldType = type
    field.classList.add("is-open")
    this.syncChoiceState(field)

    return field
  }

  refresh() {
    const fields = this.visibleFields()

    fields.forEach((field, index) => {
      const position = (index + 1) * 10
      const positionInput = this.positionInput(field)
      if (positionInput) positionInput.value = position

      const title = field.querySelector("[data-public-form-builder-target~='fieldTitle']")
      const meta = field.querySelector("[data-public-form-builder-target~='fieldMeta']")
      const label = this.labelInput(field)?.value.trim()
      const type = this.typeInput(field)?.value || "text"

      if (title) title.textContent = label || "Novo campo"
      const required = this.requiredInput(field)?.checked
      if (meta) meta.textContent = `${position}. ${TYPE_LABELS[type] || type}${required ? " · obrigatório" : ""}`
      this.syncChoiceState(field)
    })

    if (this.hasEmptyTarget) this.emptyTarget.hidden = fields.length > 0
    if (this.hasCounterTarget) this.counterTarget.textContent = `${fields.length} ${fields.length === 1 ? "campo" : "campos"}`
    this.element.dispatchEvent(new CustomEvent("public-form-builder:changed"))
  }

  syncChoiceState(field) {
    const type = this.typeInput(field)?.value || "text"
    const block = field.querySelector("[data-public-form-builder-target~='optionsBlock']")
    if (block) block.classList.toggle("is-hidden", !CHOICE_TYPES.has(type))

    // Campos desabilitados não são enviados: a config de arquivo só vale para o tipo "file".
    // Máscara só para tipos de texto/número/telefone/moeda; desabilitado não é enviado.
    const maskBlock = field.querySelector("[data-public-form-builder-target~='maskBlock']")
    if (maskBlock) {
      const maskable = MASKABLE_TYPES.has(type)
      maskBlock.classList.toggle("is-hidden", !maskable)
      maskBlock.querySelectorAll("[data-public-form-builder-target~='maskInput']").forEach((input) => { input.disabled = !maskable })
    }

    const fileBlock = field.querySelector("[data-public-form-builder-target~='fileBlock']")
    if (fileBlock) {
      const isFile = type === "file"
      fileBlock.classList.toggle("is-hidden", !isFile)
      fileBlock.querySelectorAll("[data-public-form-builder-target~='fileInput']").forEach((input) => { input.disabled = !isFile })
    }
  }

  visibleFields() {
    return Array.from(this.listTarget.querySelectorAll("[data-public-form-builder-target~='field']")).filter((field) => !field.hidden)
  }

  visibleFieldBefore(field) {
    const fields = this.visibleFields()
    return fields[fields.indexOf(field) - 1]
  }

  visibleFieldAfter(field) {
    const fields = this.visibleFields()
    return fields[fields.indexOf(field) + 1]
  }

  fieldFromEvent(event) {
    return event.currentTarget.closest("[data-public-form-builder-target~='field']")
  }

  typeInput(field) {
    return field?.querySelector("[data-public-form-builder-target~='typeInput']")
  }

  labelInput(field) {
    return field?.querySelector("[data-public-form-builder-target~='labelInput']")
  }

  nameInput(field) {
    return field?.querySelector("[data-public-form-builder-target~='nameInput']")
  }

  placeholderInput(field) {
    return field?.querySelector("[data-public-form-builder-target~='placeholderInput']")
  }

  optionsInput(field) {
    return field?.querySelector("[data-public-form-builder-target~='optionsInput']")
  }

  requiredInput(field) {
    return field?.querySelector("[data-public-form-builder-target~='requiredInput']")
  }

  positionInput(field) {
    return field?.querySelector("[data-public-form-builder-target~='positionInput']")
  }

  destroyInput(field) {
    return field?.querySelector("[data-public-form-builder-target~='destroyInput']")
  }

  uniqueName(baseName, currentField = null) {
    const base = baseName || "campo"
    const used = new Set(
      this.visibleFields()
        .filter((field) => field !== currentField)
        .map((field) => this.nameInput(field)?.value.trim())
        .filter(Boolean)
    )

    if (!used.has(base)) return base

    let index = 2
    while (used.has(`${base}_${index}`)) index += 1
    return `${base}_${index}`
  }

  slugify(value) {
    const normalized = value
      .toString()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "_")
      .replace(/^_+|_+$/g, "")

    return /^[a-z]/.test(normalized) ? normalized : `campo_${normalized || "1"}`
  }
}
