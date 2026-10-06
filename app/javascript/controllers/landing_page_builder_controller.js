import { applyFAQFilters } from "controllers/public_faq_controller"
import { previewStyle } from "controllers/landing_page_preview_style"
import { Controller } from "@hotwired/stimulus"
import { focusStep, goToStep, renderProgress } from "controllers/ax_guided"

// Editor visual de páginas por blocos.
// O servidor renderiza a página real (mesmo tema do site) com o que está no editor; o iframe é da mesma origem,
// então aqui ligamos a edição por cima dele: clicar num texto edita ali mesmo, passar o mouse num bloco mostra
// as ferramentas (mover, alinhar, duplicar, ocultar, remover), o + entre blocos insere e o ⠿ arrasta.
// Inputs são a fonte única. Texto e estilo atualizam no navegador; Salvar persiste no servidor.
const DESKTOP_WIDTH = 1280
const MOBILE_WIDTH = 390
const BLOCK = "[data-landing-page-builder-target='block']"
const POSITION = "[data-landing-page-builder-target='position']"

// Elemento da prévia -> campo do cartão do bloco. rich = texto formatado (editor com barra própria).
const FIELD_FOR_CLASS = {
  cover: { "public-theme-block-cover__title": "title", "public-theme-block-cover__subtitle": "subtitle", "public-theme-block-cover__button": "button_label" },
  callout: { "public-theme-content-callout__heading": "heading", "public-theme-content-callout__text": { field: "text", rich: true } },
  text: { "public-theme-block-text__heading": "heading", "public-theme-block-text__body": { field: "body", rich: true } },
  button: { "public-theme-block-button__link": "label" },
  property_showcase: { "public-theme-block-showcase__title": "heading", "public-theme-block-showcase__lead": "subtitle" },
  image: { "public-theme-block-image__caption": "caption" },
  video: { "public-theme-block-video__caption": "caption" }
}

const SAMPLE = {
  button: { label: "Fale conosco", url: "/contato" },
  text: { heading: "Título da seção", body: "<div>Escreva aqui o texto (exemplo, edite).</div>" },
  video: { click_to_play: true },
  cover: { title: "Título da sua página" }
}

export default class extends Controller {
  static targets = [
    "list", "empty", "template", "preset", "block", "position", "destroy", "summary", "title", "slug", "frame", "stage", "device",
    "inspectorTitle", "openPreview", "status", "saveStatus", "file", "tools", "richbar", "menu", "dropline", "shield", "addMenu", "addMenuList"
  ]
  // Status persistido; alterações só são consolidadas pelo submit.
  static values = { previewUrl: String, savedStatus: String }

  connect() {
    this.device = "desktop"
    this.frameReady = false
    this.srcdocSet = false
    this.selectedPosition = null
    this.hoverPosition = null
    this.editing = null
    this.dragging = null
    this.scale = 1
    this.observer = new ResizeObserver(() => { this.fit(); this.positionTools() })
    this.observer.observe(this.stageTarget)
    // Só vale o load do nosso srcdoc: navegando pelo Turbo o iframe dispara um load do about:blank antes dele,
    // e trocar só o corpo desse documento vazio deixaria a prévia sem as folhas de estilo.
    this.onFrameLoad = () => {
      if (!this.srcdocSet) return

      this.frameReady = true
      this.bindPreview()
      this.afterRender()
    }
    this.frameTarget.addEventListener("load", this.onFrameLoad)
    this.onDocMouseDown = (event) => {
      if (!this.menuTarget.hidden && !this.menuTarget.contains(event.target)) this.menuTarget.hidden = true
    }
    document.addEventListener("mousedown", this.onDocMouseDown)
    this.onDocPointer = (event) => {
      if (this.element.dataset.inspectorMode !== "add" && !this.addMenuTarget.contains(event.target)) this.closeAddMenu()
    }
    this.onDocKey = (event) => {
      if (event.key === "Escape" && !document.querySelector(".ax-quick-modal:not(dialog):not([hidden]), dialog[open]")) { this.closeAddMenu(); this.menuTarget.hidden = true; this.closeInspector() }
    }
    document.addEventListener("click", this.onDocPointer)
    document.addEventListener("keydown", this.onDocKey)
    // Página nova: o endereço acompanha o título até a pessoa editá-lo (ou a página ser salva).
    this.autoSlug = this.savedStatusValue === "new" && (this.slugTarget.value === "" || this.slugTarget.value === this.slugify(this.titleTarget.value))
    this.onBeforeUnload = event => { if (this.dirty && !this.submitting) { event.preventDefault(); event.returnValue = "" } }
    window.addEventListener("beforeunload", this.onBeforeUnload)
    this.reindex()
    this.refreshProgress()
    this.render()
  }

  disconnect() {
    window.removeEventListener("beforeunload", this.onBeforeUnload)
    this.resizeCleanup?.()
    clearTimeout(this.previewClickTimer)
    this.inlineRichHost?.remove()
    this.observer?.disconnect()
    this.frameTarget.removeEventListener("load", this.onFrameLoad)
    document.removeEventListener("mousedown", this.onDocMouseDown)
    document.removeEventListener("click", this.onDocPointer)
    document.removeEventListener("keydown", this.onDocKey)
    this.abort?.abort()
    clearTimeout(this.timer)
    clearTimeout(this.hideTimer)
  }

  get doc() {
    return this.frameTarget.contentDocument
  }

  // ---- Blocos (cartões do editor) ----

  liveBlocks() {
    return this.blockTargets.filter((block) => block.querySelector("[name$='[_destroy]']")?.value !== "1")
  }

  positionOf(block) {
    return block.querySelector(POSITION).value
  }

  cardAt(position) {
    return this.liveBlocks().find((block) => this.positionOf(block) === String(position))
  }

  // Menu "Adicionar bloco" (dropdown próprio) no fim da lista.
  toggleAddMenu(event) {
    event.stopPropagation()
    const open = this.addMenuListTarget.hidden
    if (open) {
      const rect = event.currentTarget.getBoundingClientRect()
      const above = rect.top - 16
      const below = window.innerHeight - rect.bottom - 16
      this.addMenuListTarget.classList.toggle("is-below", below > above)
      this.addMenuListTarget.style.setProperty("--lp-menu-space", `${Math.max(0, Math.max(above, below))}px`)
    }
    this.addMenuListTarget.hidden = !open
    event.currentTarget.setAttribute("aria-expanded", open)
  }

  closeAddMenu() {
    this.addMenuListTarget.hidden = true
    this.addMenuTarget.querySelectorAll("[aria-expanded]").forEach((button) => button.setAttribute("aria-expanded", "false"))
  }

  addPreset(event) {
    const source = this.presetTargets.find((item) => item.dataset.presetKey === event.currentTarget.dataset.presetKey)
    if (!source) return
    const holder = document.createElement("template")
    const indexes = new Map()
    holder.innerHTML = source.innerHTML.replace(/__PRESET_(\d+)__/g, (_, key) => {
      if (!indexes.has(key)) {
        this.nextBlockIndex = Math.max(Date.now(), (this.nextBlockIndex || 0) + 1)
        indexes.set(key, this.nextBlockIndex)
      }
      return String(indexes.get(key))
    })
    this.listTarget.append(holder.content)
    document.dispatchEvent(new Event("rich-text:load"))
    this.reindex()
    this.changed()
  }

  add(event) {
    this.closeAddMenu()
    const card = this.addBlock(event.currentTarget.dataset.blockType, null)
    if (card) this.selectedPosition = this.positionOf(card)
  }

  // ---- Reordenar os cartões arrastando (alça ⠿) ----

  stopToggle(event) {
    event.preventDefault() // a alça fica dentro do <summary>: clicar nela não abre o cartão
  }

  cardDragStart(event) {
    const card = event.currentTarget.closest(BLOCK)
    this.dragCard = card
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.positionOf(card))
    event.dataTransfer.setDragImage(card.querySelector("summary"), 24, 24)
    requestAnimationFrame(() => card.classList.add("is-dragging"))
  }

  cardDragOver(event) {
    if (!this.dragCard) return

    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    const { card, before } = this.dropTarget(event.clientY)
    this.clearDropMarks()
    card?.classList.add(before ? "is-drop-before" : "is-drop-after")
  }

  cardDrop(event) {
    if (!this.dragCard) return

    event.preventDefault()
    const dragged = this.dragCard
    const { card, before } = this.dropTarget(event.clientY)
    this.cardDragEnd()
    if (!card || card === dragged) return

    this.placeBlock(dragged, card, before)
    this.reindex()
    this.selectedPosition = this.positionOf(dragged)
    this.changed()
  }

  cardDragEnd() {
    this.dragCard?.classList.remove("is-dragging")
    this.dragCard = null
    this.clearDropMarks()
  }

  // Antes do primeiro cartão cujo meio está abaixo do cursor; senão, depois do último.
  dropTarget(y) {
    const members = this.sectionMembers(this.dragCard)
    const others = this.liveBlocks().filter((block) => !members.includes(block))
    const before = others.find((block) => {
      const rect = block.getBoundingClientRect()
      return y < rect.top + rect.height / 2
    })
    return before ? { card: before, before: true } : { card: others.at(-1), before: false }
  }

  clearDropMarks() {
    this.blockTargets.forEach((block) => block.classList.remove("is-drop-before", "is-drop-after"))
  }

  // Cria o cartão a partir do molde do tipo. Antes de o inserir já preenche os valores (o Trix lê o valor ao iniciar).
  addBlock(type, before, values) {
    const template = this.templateTargets.find((item) => item.dataset.blockType === type)
    if (!template) return null

    const holder = document.createElement("template")
    this.nextBlockIndex = Math.max(Date.now(), (this.nextBlockIndex || 0) + 1)
    holder.innerHTML = template.innerHTML.replaceAll("__INDEX__", String(this.nextBlockIndex)) // Rails nested attributes require numeric keys
    const card = holder.content.querySelector(BLOCK)
    if (values) this.copyValues(values, card)
    else this.fillSample(type, card)
    before ? before.before(card) : this.listTarget.append(card)
    if (card.querySelector("trix-editor")) document.dispatchEvent(new Event("rich-text:load"))
    if (type === "section" && !values) {
      card.querySelector("[name$='[data][heading]']").value = "Conheça nossa empresa"
      card.querySelector("[name$='[data][columns]']").value = "3"
    }
    this.reindex()
    this.changed()
    return card
  }

  // Bloco novo nasce com um texto de exemplo (um botão ou texto vazio nem salvaria).
  fillSample(type, card) {
    Object.entries(SAMPLE[type] || {}).forEach(([field, value]) => {
      const input = card.querySelector(`[name$='[data][${field}]']`)
      if (input?.type === "checkbox") input.checked = value
      else if (input && !input.value) input.value = value
    })
  }

  // Copia os campos [data] de um cartão para outro (duplicar).
  copyValues(from, to) {
    const sourceItems = from.querySelector(".ax-dynamic-list__items")
    const targetItems = to.querySelector(".ax-dynamic-list__items")
    if (sourceItems && targetItems) {
      const sourcePrefix = from.querySelector(POSITION).name.replace(/\[position\]$/, "")
      const targetPrefix = to.querySelector(POSITION).name.replace(/\[position\]$/, "")
      targetItems.innerHTML = sourceItems.innerHTML.replaceAll(sourcePrefix, targetPrefix)
    }
    const sourceId = from.querySelector("input[name$='[id]']")?.value
    if (sourceId) {
      const name = to.querySelector(POSITION).name.replace(/\[position\]$/, "[copy_images_from]")
      to.append(Object.assign(document.createElement("input"), { type: "hidden", name, value: sourceId }))
    }
    from.querySelectorAll("input[type='file']").forEach((input) => {
      const suffix = input.name.match(/\[blocks_attributes\]\[[^\]]+\](.*)$/)?.[1]
      const target = [...to.querySelectorAll("input[type='file']")].find((item) => item.name.endsWith(suffix))
      if (!target || !input.files.length) return

      const transfer = new DataTransfer()
      Array.from(input.files).forEach((file) => transfer.items.add(file))
      target.files = transfer.files
    })
    from.querySelectorAll("[name*='[data]']").forEach((input) => {
      const suffix = input.name.slice(input.name.indexOf("[data]"))
      const match = [...to.querySelectorAll("[name*='[data]']")].find((item) => item.name.endsWith(suffix) && item.type === input.type)
      if (!match) return
      if (input.type === "checkbox" || input.type === "radio") match.checked = input.checked
      else match.value = input.value
    })
    const visible = from.querySelector("input[type='checkbox'][name$='[visible]']")
    const target = to.querySelector("input[type='checkbox'][name$='[visible]']")
    if (visible && target) target.checked = visible.checked
  }

  remove(event) {
    event.preventDefault()
    this.removeCard(event.currentTarget.closest(BLOCK))
  }

  sectionMembers(card) {
    if (card?.dataset.blockType !== "section") return card ? [card] : []
    const blocks = this.liveBlocks()
    const rest = blocks.slice(blocks.indexOf(card) + 1)
    const next = rest.findIndex((block) => block.dataset.blockType === "section")
    return [card, ...rest.slice(0, next < 0 ? rest.length : next)]
  }

  placeBlock(card, target, before) {
    const members = this.sectionMembers(card)
    if (members.includes(target)) return
    if (!target) return this.listTarget.append(...members)

    if (card.dataset.blockType === "section") {
      const blocks = this.liveBlocks()
      const owner = blocks.slice(0, blocks.indexOf(target) + 1).findLast((block) => block.dataset.blockType === "section")
      if (owner) target = before ? owner : this.sectionMembers(owner).at(-1)
      else {
        target = blocks.slice(0, blocks.findIndex((block) => block.dataset.blockType === "section")).at(-1)
        before = false
      }
    }
    if (!target || members.includes(target)) return
    before ? target.before(...members) : target.after(...members)
  }

  removeCard(block) {
    if (!block) return
    const message = block.dataset.blockType === "section" ? "Remover esta seção e todos os seus blocos?" : "Remover este bloco da página?"
    if (!window.confirm(message)) return

    this.sectionMembers(block).forEach((member) => {
      if (member.querySelector("input[name$='[id]']")) {
        member.querySelector("[data-landing-page-builder-target='destroy']").value = "1"
        member.hidden = true
      } else member.remove()
    })
    this.selectedPosition = null
    this.reindex()
    this.changed()
  }

  up(event) { event.preventDefault(); this.moveCard(event.currentTarget.closest(BLOCK), -1) }

  down(event) { event.preventDefault(); this.moveCard(event.currentTarget.closest(BLOCK), 1) }

  moveCard(block, delta) {
    const blocks = this.liveBlocks()
    const members = this.sectionMembers(block)
    const owner = blocks.slice(0, blocks.indexOf(block)).findLast((item) => item.dataset.blockType === "section")
    const siblings = owner && block.dataset.blockType !== "section" ? this.sectionMembers(owner).slice(1).filter((item) => item.querySelector("[name$='[data][column]']")?.value === block.querySelector("[name$='[data][column]']")?.value) : blocks
    const target = siblings === blocks ? blocks[delta < 0 ? blocks.indexOf(block) - 1 : blocks.indexOf(members.at(-1)) + 1] : siblings[siblings.indexOf(block) + delta]
    if (!target) return

    this.placeBlock(block, target, delta < 0)
    this.reindex()
    this.selectedPosition = this.positionOf(block)
    this.changed()
  }

  // Abre a etapa (recolhida por padrão) que contém o cartão, para o campo ficar visível.
  revealCard(card) {
    const step = card.closest("[data-guided-step]")
    if (step?.matches(".is-collapsible:not(.is-open)")) step.querySelector("[data-ax-disclosure-target~='trigger']")?.click()
    card.open = true
    if (this.element.classList.contains("lp-canvas-editor")) this.inspectCard(card)
  }

  resizeInspector(event) {
    event.preventDefault()
    this.finishEditing()
    const move = (pointer) => this.element.style.setProperty("--lp-inspector-width", `${Math.max(300, Math.min(window.innerWidth * .6, this.element.getBoundingClientRect().right - pointer.clientX))}px`)
    const end = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", end); this.resizeCleanup = null }
    this.resizeCleanup?.()
    this.resizeCleanup = end
    window.addEventListener("pointermove", move)
    window.addEventListener("pointerup", end)
  }

  resizeInspectorKey(event) {
    if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return
    event.preventDefault()
    const width = this.element.querySelector(".ax-guided-steps").getBoundingClientRect().width
    this.element.style.setProperty("--lp-inspector-width", `${Math.max(300, Math.min(window.innerWidth * .6, width + (event.key === "ArrowLeft" ? 20 : -20)))}px`)
  }

  selectPreviewElement(el) {
    this.doc.querySelectorAll(".lp-selected-element").forEach((node) => node.classList.remove("lp-selected-element"))
    el.classList.add("lp-selected-element")
    if (el.dataset.elementField) this.readElementStyle(el, `element_${el.dataset.elementField}_`)
    if (this.inspectedRow) this.readElementStyle(el, this.inspectedItemKeys ? `element_${this.inspectedItemKeys[0]}_` : "", this.inspectedRow)
    const faq = el.closest("[data-faq-row-index]")
    if (el.dataset.elementField || el.dataset.labelIndex || el.dataset.elementGroup) {
      this.selectedElementSelector = el.dataset.elementField ? `[data-element-field="${el.dataset.elementField}"]` : el.dataset.labelIndex ? `[data-label-index="${el.dataset.labelIndex}"]` : `[data-element-group="${el.dataset.elementGroup}"]`
      return
    }
    const item = el.closest("[data-item-row-key]")
    const className = Array.from(el.classList).find((name) => name.startsWith("public-theme-"))
    this.selectedElementSelector = faq ? `[data-faq-row-index='${faq.dataset.faqRowIndex}'] ${el.tagName === "SUMMARY" ? "summary" : `.${className}`}` : item && className ? `[data-item-row-key='${item.dataset.itemRowKey}'] .${className}` : className ? `.${className}` : null
  }

  readElementStyle(el, prefix, scope = null) {
    const card = scope || this.cardAt(this.selectedPosition)
    if (!card) return
    const computed = this.doc.defaultView.getComputedStyle(el)
    const input = key => card.querySelector(`input[name$='[${prefix}${key}]'], select[name$='[${prefix}${key}]']`)
    const hex = value => {
      const channels = value.match(/\d+/g)
      if (!channels || channels.length < 3 || (channels.length > 3 && Number(channels[3]) === 0)) return null
      return `#${channels.slice(0, 3).map(channel => Number(channel).toString(16).padStart(2, "0")).join("")}`
    }
    const write = (key, value) => {
      if (value == null) return
      card.querySelectorAll(`input[name$='[${prefix}${key}]'], select[name$='[${prefix}${key}]']`).forEach(control => {
        control.value = value
        const range = control.closest("[data-controller='ax-range']")?.querySelector("input[type='range']")
        if (range) range.value = value
      })
    }
    if (input("custom_colors")?.value !== "true") {
      let background = hex(computed.backgroundColor)
      for (let parent = el.parentElement; !background && parent; parent = parent.parentElement) background = hex(this.doc.defaultView.getComputedStyle(parent).backgroundColor)
      write("background_color", background || "#ffffff")
      if (input("background_color")) input("background_color").dataset.transparentBackground = String(!hex(computed.backgroundColor))
      write("text_color", hex(computed.color))
    }
    if (input("custom_border")?.value !== "true") {
      write("border_color", hex(computed.borderColor))
      write("border_width", Math.min(12, parseFloat(computed.borderWidth) || 0))
      write("border_radius", Math.min(64, parseFloat(computed.borderRadius) || 0))
      write("border_style", ["none", "solid", "dashed"].includes(computed.borderStyle) ? computed.borderStyle : "solid")
    }
  }

  closeInspector() {
    this.element.removeAttribute("data-inspector-mode")
    this.inspectedFields = null
    this.parentInspector = false
    this.inspectedRow = null
    this.inspectedItemKeys = null
    delete this.element.dataset.parentInspector
    delete this.element.dataset.elementPanel
    this.element.querySelector(".lp-element-panel")?.remove()
    this.element.querySelector(".lp-element-breadcrumb")?.remove()
    this.element.querySelector(".lp-element-hierarchy")?.remove()
    this.element.querySelectorAll("[data-inspector-group-heading]").forEach(node => node.remove())
    this.element.querySelectorAll("[data-inspector-row]").forEach((row) => { row.hidden = false; delete row.dataset.inspectorRow })
    this.element.querySelectorAll("[data-inspector-item-field]").forEach((field) => { field.hidden = false; delete field.dataset.inspectorItemField })
    this.element.querySelectorAll(".lp-layout-controls").forEach((group) => { group.style.removeProperty("display") })
    this.element.querySelectorAll(".is-inspected").forEach((card) => card.classList.remove("is-inspected"))
    this.element.querySelectorAll("[data-inspector-filtered]").forEach((field) => {
      field.hidden = false
      delete field.dataset.inspectorFiltered
    })
  }

  openInspector(event) {
    event.stopPropagation()
    this.closeInspector()
    const mode = event.currentTarget.dataset.inspector
    this.element.dataset.inspectorMode = mode
    this.inspectorTitleTarget.textContent = { page: "Configurações da página", seo: "Como o Google vê", structure: "Estrutura da página", add: "Adicionar conteúdo" }[mode]
    if (mode === "add") {
      this.addMenuListTarget.hidden = false
      this.emptyTarget.setAttribute("aria-expanded", "true")
    }
    const steps = this.element.querySelectorAll(".ax-guided-steps [data-guided-step]")
    const step = steps[{ page: 0, structure: 1, add: 1, seo: 2 }[mode]]
    if (step?.matches(".is-collapsible:not(.is-open)")) step.querySelector("[data-ax-disclosure-target~='trigger']")?.click()
  }

  inspectItemRow(card, selected, keys = null) {
    if (!selected) return
    this.inspectedRow = selected
    this.inspectedItemKeys = keys
    card.querySelectorAll(".ax-dynamic-list__item").forEach(row => {
      row.hidden = row !== selected
      row.dataset.inspectorRow = "true"
    })
    this.inspectorAppearance({ currentTarget: this.element.querySelector(".lp-inspector-tabs [data-panel='content']") })
  }

  styleField(name) {
    return /color|border|custom_|background_|text_opacity|gradient|backdrop|surface|density|typography|motion/.test(name)
  }

  fieldEffectVisible(name, scope) {
    const leaf = name.replace(/^(?:element_(?:title|heading|text|body|subtitle|eyebrow|badge|labels|label|caption|alt|initials)|block|button|secondary)_/, "")
    const prefix = name.slice(0, name.length - leaf.length)
    const setting = suffix => {
      const controls = [...scope.querySelectorAll("input, select")].filter(control => control.name?.endsWith(`[${prefix}${suffix}]`))
      const control = controls.find(control => control.type !== "hidden") || controls[0]
      return control?.type === "checkbox" ? String(control.checked) : control?.value
    }
    if (leaf === "text_gradient_color") return ["true", "1"].includes(setting("text_gradient"))
    if (["backdrop_blur", "backdrop_saturation"].includes(leaf)) return ["true", "1"].includes(setting("backdrop_enabled"))
    if (["gradient_color", "gradient_kind"].includes(leaf)) return setting("background_mode") === "gradient"
    if (leaf === "gradient_angle") return setting("background_mode") === "gradient" || ["true", "1"].includes(setting("text_gradient"))
    if (leaf === "background_opacity") return ["solid", "gradient"].includes(setting("background_mode"))
    return true
  }

  organizeInspectorFields(card) {
    card.querySelectorAll("[data-inspector-group-heading]").forEach(node => node.remove())
    const groups = new Map()
    const fields = this.inspectedRow ? this.inspectedRow.querySelectorAll(".ax-repeatable-rows__field") : card.querySelectorAll("[data-block-field]")
    for (const field of fields) {
      if (field.hidden) continue
      const name = field.dataset.blockField || field.querySelector("[name]")?.name?.match(/\[([^\]]+)\]$/)?.[1] || ""
      const group = /font_|text_(align|decoration|transform)|line_height|letter_spacing/.test(name) ? "Tipografia" : /border/.test(name) ? "Borda" : /backdrop/.test(name) ? "Vidro" : /text_color|text_opacity|text_gradient/.test(name) ? "Cor do texto" : /background_|gradient_/.test(name) ? "Fundo" : "Conteúdo"
      const parent = field.parentElement
      if (!groups.has(parent)) groups.set(parent, [])
      groups.get(parent).push({ field, name, group })
    }
    const order = ["Conteúdo", "Tipografia", "Fundo", "Cor do texto", "Borda", "Vidro"]
    groups.forEach((fields, parent) => {
      let previous
      fields.sort((a, b) => order.indexOf(a.group) - order.indexOf(b.group) || Number(b.name.endsWith("background_mode")) - Number(a.name.endsWith("background_mode"))).forEach(({ field, group }) => {
        if (previous !== group) {
          const heading = document.createElement("div")
          heading.className = "ax-field-group__header ax-span-12"
          heading.dataset.inspectorGroupHeading = "true"
          const label = document.createElement("h6")
          label.className = "ax-field-group__title"
          label.textContent = group
          heading.append(label)
          parent.append(heading)
          previous = group
        }
        parent.append(field)
      })
      const actions = parent.querySelector(":scope > .ax-repeatable-rows__actions")
      if (actions) parent.append(actions)
    })
  }

  inspectorAppearance(event) {
    const card = this.element.querySelector(".is-inspected")
    if (!card) return
    const appearance = event.currentTarget.dataset.panel === "appearance"
    this.element.dataset.inspectorTab = appearance ? "appearance" : "content"
    this.element.querySelectorAll(".lp-inspector-tabs button").forEach((button) => button.setAttribute("aria-pressed", String(button === event.currentTarget)))
    card.querySelectorAll("[data-block-field]").forEach((field) => {
      const name = field.dataset.blockField
      const allowed = this.inspectedFields ? this.inspectedFields.includes(name) : !name.startsWith("element_")
      const styling = this.styleField(name)
      const repeatedScope = this.inspectedRow?.closest("[data-block-field]") === field
      const layoutOnly = this.inspectedFields && field.closest(".lp-layout-controls") && !styling
      if (this.parentInspector) {
        const configuration = /^(block_|design$|align$|height$|focus$|overlay$|width$|spacing$|columns$|ratio$|background$|content_width$|density$|typography$|motion$|layout_|mobile_|offset_|layer$|surface$|anchor$|image_desktop$|image_mobile$|heading_rule$|mobile_order$)/.test(name)
        field.hidden = this.element.dataset.elementPanel !== "configuration" || !configuration || /custom_/.test(name) || !this.fieldEffectVisible(name, card)
        field.dataset.inspectorFiltered = "true"
        return
      }
      field.hidden = /(?:^|_)custom_(?:colors|border)$/.test(name) || Boolean(layoutOnly) || !allowed || (appearance ? !styling && !repeatedScope : styling) || !this.fieldEffectVisible(name, card)
      field.dataset.inspectorFiltered = "true"
    })
    if (this.inspectedRow) {
      this.inspectedRow.querySelectorAll(".ax-repeatable-rows__field").forEach(field => {
        const control = field.querySelector("input[name], textarea[name], select[name]")
        if (!control) return
        const name = control.name.match(/\[([^\]]+)\]$/)?.[1] || ""
        const keys = this.inspectedItemKeys
        const allowed = keys ? keys.some(key => name === key || name.startsWith(`element_${key}_`)) : !name.startsWith("element_")
        field.hidden = control.type === "hidden" && !field.querySelector("trix-editor") || !allowed || (appearance ? !this.styleField(name) : this.styleField(name)) || !this.fieldEffectVisible(name, this.inspectedRow)
        field.dataset.inspectorItemField = "true"
      })
    }
    this.organizeInspectorFields(card)
    this.showInspectedGroups(card)
  }

  inspectCard(card, fields = null, title = null) {
    this.closeInspector()
    this.element.dataset.inspectorMode = "element"
    if (fields && title === "Editar botão") {
      const prefix = fields.includes("label") ? "" : fields.includes("secondary_label") ? "secondary_" : "button_"
      fields = fields.concat([...card.querySelectorAll("[data-block-field]")].map(node => node.dataset.blockField).filter(name => prefix ? name.startsWith(prefix) : !name.startsWith("block_") && (this.styleField(name) || /font_|text_(align|decoration|transform)|line_height|letter_spacing/.test(name))))
    }
    this.inspectedFields = fields
    this.parentInspector = !fields
    this.element.dataset.elementPanel = "elements"
    card.classList.add("is-inspected")
    this.inspectorTitleTarget.textContent = title || `Editar ${card.querySelector(".lp-block__title strong")?.textContent || "elemento"}`
    card.open = true
    if (fields) card.querySelectorAll("[data-block-field]").forEach((field) => {
      field.hidden = !fields.includes(field.dataset.blockField)
      field.dataset.inspectorFiltered = "true"
    })
    this.inspectorAppearance({ currentTarget: this.element.querySelector(".lp-inspector-tabs [data-panel='content']") })
    this.renderElementPanel(card)
  }

  showInspectedGroups(card) {
    card.querySelectorAll(".lp-layout-controls").forEach((group) => {
      const visible = Array.from(group.querySelectorAll("[data-block-field]")).some((field) => !field.hidden)
      group.style.display = visible ? "block" : "none"
      group.open = visible
    })
  }

  // Posição = ordem na tela; resumo = primeiro texto do bloco; estado vazio.
  reindex() {
    const blocks = this.liveBlocks()
    let section = null
    blocks.forEach((block, index) => {
      if (block.dataset.blockType === "section") section = block
      const column = block.querySelector("[name$='[data][column]']")
      const span = block.querySelector("[name$='[data][span]']")
      const isSection = block.dataset.blockType === "section"
      const mobile = block.querySelector("input[type='checkbox'][name$='[data][mobile_layout]']")?.checked
      block.querySelectorAll("[data-block-field='mobile_offset_x'],[data-block-field='mobile_offset_y'],[data-block-field='mobile_min_height']").forEach((field) => { field.hidden = !mobile })
      block.querySelector("[data-block-field='layout_min_height']").hidden = block.querySelector("[name$='[data][layout_height]']").value !== "custom"
      block.classList.toggle("is-section-child", Boolean(section) && !isSection)
      block.hidden = Boolean(section?.dataset.collapsed === "true") && !isSection
      const badge = block.querySelector("[data-column-badge]")
      if (badge) { badge.hidden = !section || isSection; badge.textContent = `Coluna ${column?.value || 1}` }
      if (column) {
        column.closest(".ax-span-6").hidden = !section || isSection
        const count = Number(section?.querySelector("[name$='[data][columns]']")?.value || 3)
        Array.from(column.options).forEach((option) => { option.disabled = Number(option.value) > count })
        if (Number(column.value) > count) column.value = String(count)
      }
      if (span) span.closest(".ax-span-6").hidden = Boolean(section) || isSection
      if (block.dataset.blockType === "text") {
        const expanded = block.querySelector("input[type='checkbox'][name$='[data][expandable]']")?.checked
        block.querySelectorAll("[data-block-field='more_body'], [data-block-field='more_label']").forEach((field) => { field.hidden = !expanded })
      }
      if (isSection) block.querySelector("[data-block-field='ratio']").hidden = block.querySelector("[name$='[data][columns]']").value !== "2"
      block.querySelector(POSITION).value = index
      const source = block.querySelector("[data-landing-page-builder-summary='1']")
      const summary = block.querySelector("[data-landing-page-builder-target='summary']")
      if (summary) summary.textContent = source?.value?.trim() || ""
    })
    this.emptyTarget.hidden = false
    const ordinals = ["primeiro", "segundo", "terceiro", "quarto", "quinto", "sexto", "sétimo", "oitavo", "nono", "décimo"]
    this.emptyTarget.querySelector("[data-next-block-label]").textContent = `Adicionar ${ordinals[blocks.length] || `${blocks.length + 1}º`} bloco`
    this.listTarget.querySelectorAll(".lp-column-slots").forEach((slots) => slots.remove())
    blocks.filter((block) => block.dataset.blockType === "section").forEach((section) => {
      const members = this.sectionMembers(section).slice(1)
      let tail = members.at(-1) || section
      const count = Number(section.querySelector("[name$='[data][columns]']").value)
      for (let column = 1; column <= count; column++) {
        const columnBlocks = members.filter((block) => Number(block.querySelector("[name$='[data][column]']")?.value || 1) === column)
        if (columnBlocks.length) continue
        const slots = document.createElement("div")
        slots.className = "lp-column-slots"
        slots.hidden = section.dataset.collapsed === "true"
        const button = document.createElement("button")
        button.type = "button"
        button.className = "ax-btn ax-btn--secondary"
        button.textContent = `Coluna ${column} · Adicionar bloco nesta coluna`
        button.dataset.sectionPosition = this.positionOf(section)
        button.dataset.column = column
        button.dataset.action = "landing-page-builder#openColumnMenu"
        slots.append(button)
        tail.after(slots)
        tail = slots
      }
    })
    this.liveBlocks().forEach((block, index) => { block.querySelector(POSITION).value = index })
    if (this.element.dataset.inspectorMode === "element") this.inspectorAppearance({ currentTarget: this.element.querySelector(`.lp-inspector-tabs [data-panel='${this.element.dataset.inspectorTab === "appearance" ? "appearance" : "content"}']`) })
  }

  openColumnMenu(event) {
    this.menuSection = this.cardAt(event.currentTarget.dataset.sectionPosition)
    this.menuColumn = event.currentTarget.dataset.column
    this.menuTarget.hidden = false
    this.menuTarget.style.left = "8px"
    this.menuTarget.style.top = "8px"
    this.menuTarget.querySelector("[data-block-type='section']").hidden = true
  }

  toggleSection(event) {
    event.preventDefault()
    const section = event.currentTarget.closest(BLOCK)
    section.dataset.collapsed = section.dataset.collapsed !== "true" ? "true" : "false"
    event.currentTarget.setAttribute("aria-expanded", String(section.dataset.collapsed !== "true"))
    this.reindex()
  }

  resetLayout(event) {
    const block = event.currentTarget.closest(BLOCK)
    const defaults = { layout_width: "theme", layout_height: "auto", layout_min_height: 0, offset_x: 0, offset_y: 0, layer: 0, mobile_offset_x: 0, mobile_offset_y: 0, mobile_min_height: 0 }
    Object.entries(defaults).forEach(([key, value]) => { block.querySelectorAll(`[name$='[data][${key}]']`).forEach((input) => { input.value = value }) })
    block.querySelector("input[type='checkbox'][name$='[data][mobile_layout]']").checked = false
    block.querySelectorAll("input[type='range']").forEach((input) => { input.value = 0 })
    this.changed()
  }

  // O texto formatado do cartão é só texto: sem anexos/imagens arrastados para dentro.
  blockFiles(event) {
    event.preventDefault()
  }

  // ---- Endereço (URL) ----

  titleChanged() {
    if (this.autoSlug) this.slugTarget.value = this.slugify(this.titleTarget.value)
  }

  slugChanged() {
    this.autoSlug = this.slugTarget.value.trim() === ""
  }

  slugify(text) {
    return text.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  }

  // ---- Etapas ----

  focusStep(event) { focusStep(this.element, event) }

  goToStep(event) { goToStep(this.element, event) }

  refreshProgress() {
    const hasTitle = this.titleTarget.value.trim() !== ""
    const hasBlock = this.liveBlocks().some((block) => block.querySelector("input[type='checkbox'][name$='[visible]']")?.checked)
    renderProgress(this.element, {
      states: { 1: hasTitle, 2: hasBlock, 3: true },
      checks: {},
      count: [Number(hasTitle) + Number(hasBlock), 2],
      label: !hasTitle ? "Comece pelo título" : !hasBlock ? "Adicione um bloco" : "Pronto para salvar",
      ready: hasTitle && hasBlock
    })
  }

  // ---- Atualização da prévia e autosave ----

  changed(event) {
    this.refreshProgress()
    this.schedule()
  }

  schedule(event) {
    const control = event?.target?.tagName === "TRIX-EDITOR" ? this.element.querySelector(`[id="${event.target.getAttribute("input")}"]`) : event?.target
    const match = control?.name?.match(/\[([^\]]*?)(background_color|text_color|border_color|border_width|border_style|border_radius)\]$/)
    if (match) {
      const suffix = match[2].startsWith("border_") ? "custom_border" : "custom_colors"
      const toggleName = control.name.replace(/\[[^\]]+\]$/, `[${match[1]}${suffix}]`)
      const toggle = Array.from(control.closest(".lp-block")?.querySelectorAll("input") || []).find(input => input.name === toggleName)
      if (toggle) toggle.value = "true"
      if (match[2] === "background_color" || match[2] === "text_color") {
        const scope = control.closest(".ax-dynamic-list__item") || control.closest(".lp-block")
        const modeName = control.name.replace(/\[[^\]]+\]$/, `[${match[1]}background_mode]`)
        const mode = [...scope.querySelectorAll("select")].find(input => input.name === modeName)
        if (mode?.value === "inherit") {
          const swatch = [...scope.querySelectorAll("input")].find(input => input.name === control.name)
          mode.value = match[2] === "background_color" ? "solid" : swatch?.dataset.transparentBackground === "true" ? "transparent" : "inherit"
        }
      }
    }

    if (event?.target && /\[(?:background_mode|text_gradient|backdrop_enabled)\]$/.test(event.target.name || "") && this.element.dataset.inspectorMode === "element") this.inspectorAppearance({ currentTarget: this.element.querySelector(`.lp-inspector-tabs [data-panel='${this.element.dataset.inspectorTab === "appearance" ? "appearance" : "content"}']`) })
    this.dirty = true
    this.saveStatus("Alterações não salvas — use Salvar")
    if (this.applyLocalPreview(control)) {
      this.localControls ||= new Set()
      this.localControls.add(control)
      this.status("Atualizado")
      return
    }
    if (control && ["input", "trix-change"].includes(event?.type)) {
      this.status("A prévia da estrutura atualiza ao concluir o campo")
      return
    }
    this.reindex()
    if (this.editing || this.dragging) {
      this.pendingRender = true
      return
    }

    clearTimeout(this.timer)
    this.status("Atualizando…")
    this.timer = setTimeout(() => this.render(), 0)
  }

  applyLocalPreview(control) {
    if (!this.frameReady || !control) return false
    const card = control.closest(".lp-block")
    if (!card) return !control.name?.includes("[blocks_attributes]")
    const wrapper = this.doc?.querySelector(`.lp-preview-block[data-block-position='${this.positionOf(card)}']`)
    if (!wrapper) return false
    const key = control.name?.match(/\[([^\]]+)\]$/)?.[1]
    if (!key) return false
    const row = control.closest(".ax-dynamic-list__item")
    let root = wrapper
    if (row) {
      const rows = [...row.parentElement.querySelectorAll(".ax-dynamic-list__item")]
      const index = rows.indexOf(row)
      const rowKey = row.querySelector("[name$='[row_key]']")?.value
      root = [...wrapper.querySelectorAll("[data-item-row-key], [data-faq-row-index], [data-label-index]")].find(node =>
        rowKey ? node.dataset.itemRowKey === rowKey : Number(node.dataset.faqRowIndex ?? node.dataset.labelIndex) === index)
      if (!root) return false
    }
    const scope = row || card
    const values = Object.fromEntries([...scope.querySelectorAll("input[name], select[name], textarea[name]")].map(input => [input.name.match(/\[([^\]]+)\]$/)?.[1], input.type === "checkbox" ? String(input.checked) : input.value]))
    const style = key.match(/^(element_[a-z]+_|block_|button_|secondary_)?(background_mode|background_color|background_opacity|text_color|text_opacity|gradient_color|gradient_kind|gradient_angle|text_gradient|text_gradient_color|font_family|font_size|font_weight|font_style|text_align|text_decoration|text_transform|line_height|letter_spacing|custom_colors|custom_border|border_color|border_style|border_width|border_radius|backdrop_enabled|backdrop_blur|backdrop_saturation)$/)
    if (style) {
      const prefix = style[1] || ""
      let node = root
      if (prefix.startsWith("element_")) node = root.querySelector(`[data-element-field='${prefix.slice(8, -1)}'], [data-item-element='${prefix.slice(8, -1)}']`)
      else if (prefix === "button_" || prefix === "secondary_") node = root.querySelectorAll("a.public-theme-builder-action, .public-theme-block-cover__button, .public-theme-content-callout__button")[prefix === "secondary_" ? 1 : 0]
      else if (prefix === "block_") node = card.dataset.blockType === "callout" ? wrapper.querySelector(".public-theme-content-callout") : [...wrapper.children].find(child => !child.classList.contains("lp-column-slots"))
      if (!node) return false
      this.localStyles ||= new WeakMap()
      if (!this.localStyles.has(node)) {
        const managed = ["background", "background-color", "background-image", "background-clip", "-webkit-background-clip", "-webkit-text-fill-color", "color", "border", "border-color", "border-radius", "font-family", "font-size", "font-weight", "font-style", "text-align", "text-decoration", "text-transform", "line-height", "letter-spacing", "backdrop-filter", "-webkit-backdrop-filter"]
        managed.forEach(name => node.style.removeProperty(name))
        this.localStyles.set(node, node.getAttribute("style") || "")
      }
      if (prefix === "block_") {
        [...wrapper.style].filter(name => name.startsWith("--lp-style-") || name.startsWith("--lp-custom-")).forEach(name => wrapper.style.removeProperty(name))
        wrapper.classList.remove("has-custom-colors", "has-creative-style")
        wrapper.style.removeProperty("border")
        wrapper.style.removeProperty("border-radius")
      }
      node.setAttribute("style", this.localStyles.get(node))
      const properties = previewStyle(values, prefix)
      Object.entries(properties).forEach(([name, value]) => (prefix === "block_" && card.dataset.blockType !== "callout" && ["border", "border-radius"].includes(name) ? wrapper : node).style.setProperty(name, value))
      this.positionTools()
      return true
    }
    let node = root.querySelector(`[data-element-field='${key}'], [data-item-element='${key}']`)
    if (row && key === "text") node ||= root.querySelector(".public-theme-block-faq__answer, .public-theme-content-callout__text")
    if (!node || !["title", "heading", "subtitle", "body", "text", "caption", "eyebrow", "badge", "label"].includes(key)) return false
    const trix = [...scope.querySelectorAll("trix-editor")].find(editor => editor.getAttribute("input") === control.id)
    if (trix) {
      // Trix HTML is untrusted until server validation. Only its formatting tags enter the canvas.
      const fragment = new DOMParser().parseFromString(control.value, "text/html")
      fragment.querySelectorAll("script, style, iframe, object, embed").forEach(element => element.remove())
      fragment.body.querySelectorAll("*").forEach(element => {
        if (!["DIV", "P", "BR", "STRONG", "EM", "DEL", "S", "PRE", "CODE", "UL", "OL", "LI", "BLOCKQUOTE", "A"].includes(element.tagName)) element.replaceWith(...element.childNodes)
        else [...element.attributes].forEach(attribute => {
          if (element.tagName === "A" && attribute.name === "href" && /^(https?:|mailto:|tel:|\/(?!\/)|#)/i.test(attribute.value)) return
          element.removeAttribute(attribute.name)
        })
      })
      node.innerHTML = fragment.body.innerHTML
    } else {
      const icon = node.querySelector("i.bi")?.cloneNode(true)
      node.textContent = control.value
      if (icon) node.prepend(icon, " ")
    }
    this.positionTools()
    return true
  }

  async render() {
    // Trocar o conteúdo no meio de uma edição ou arrasto perderia o que está em andamento.
    if (this.editing || this.dragging) {
      this.pendingRender = true
      return
    }

    this.pendingRender = false
    this.abort?.abort()
    this.abort = new AbortController()

    // Arquivos novos não vão para a prévia (ela os mostra daqui, pela URL local do arquivo).
    const body = new FormData(this.element)
    body.delete("_method")
    this.fileTargets.forEach((input) => body.delete(input.name))

    try {
      const response = await fetch(this.previewUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": this.csrfToken(), Accept: "text/html" },
        credentials: "same-origin",
        body,
        signal: this.abort.signal
      })
      if (!response.ok) throw new Error(response.status)

      const preview = new DOMParser().parseFromString(await response.text(), "text/html")
      // A prévia usa sandbox sem scripts; inclusive scripts injetados por ferramentas de diagnóstico.
      preview.querySelectorAll("script").forEach((script) => script.remove())
      const html = `<!DOCTYPE html>${preview.documentElement.outerHTML}`
      // Só troca o corpo se o documento da prévia já tem as folhas de estilo (senão, carrega tudo de novo).
      if (this.frameReady && this.doc?.querySelector("link[rel='stylesheet']")) this.morph(html)
      else {
        this.srcdocSet = true
        this.frameTarget.srcdoc = html
      }
      this.status("Atualizado")
    } catch (error) {
      if (error.name !== "AbortError") this.status("Não foi possível atualizar a prévia")
    }
  }

  // Troca só o corpo da página: o iframe não recarrega (sem piscar, mantém a rolagem e as folhas de estilo).
  morph(html) {
    const doc = this.doc
    if (!doc) return

    const parsed = new DOMParser().parseFromString(html, "text/html")
    const scroll = doc.defaultView.scrollY
    doc.body.innerHTML = parsed.body.innerHTML
    doc.defaultView.scrollTo(0, scroll)
    this.afterRender()
  }

  afterRender() {
    this.decorate()
    this.applyPickedImages()
    this.localControls?.forEach(control => { if (control.isConnected) this.applyLocalPreview(control); else this.localControls.delete(control) })
    this.markSelected(this.selectedPosition)
    const wrapper = this.doc.querySelector(`.lp-preview-block[data-block-position='${this.selectedPosition}']`)
    if (this.selectedElementSelector) wrapper?.querySelectorAll(this.selectedElementSelector).forEach(node => node.classList.add("lp-selected-element"))
    this.positionTools()
    const card = this.element.querySelector(".is-inspected")
    if (card) this.renderElementPanel(card)
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }

  switchDevice(event) {
    this.device = event.currentTarget.dataset.device
    this.deviceTargets.forEach((button) => button.setAttribute("aria-pressed", button === event.currentTarget))
    this.fit()
    this.applyPickedImages()
    this.positionTools()
  }

  fit() {
    const width = this.device === "desktop" ? (this.element.classList.contains("lp-fullscreen-editor") ? this.stageTarget.clientWidth : DESKTOP_WIDTH) : MOBILE_WIDTH
    this.scale = Math.min(1, this.stageTarget.clientWidth / width)
    const frame = this.frameTarget.style
    frame.width = `${width}px`
    frame.height = `${this.stageTarget.clientHeight / this.scale}px`
    frame.transform = `scale(${this.scale})`
    this.frameLeft = Math.max(0, (this.stageTarget.clientWidth - width * this.scale) / 2)
    frame.left = `${this.frameLeft}px`
  }

  status(text) {
    this.statusTarget.textContent = text
  }

  // ---- Envio explícito ----

  // One JSON part per block avoids multipart limits as the style catalog grows.
  compactFormData(event) {
    const body = event.formData
    const blocks = new Map()
    for (const [name, value] of [...body.entries()]) {
      if (typeof value !== "string" && value.name === "" && value.size === 0) { body.delete(name); continue }
      const match = name.match(/^(landing_page\[blocks_attributes\]\[[^\]]+\])\[data\]((?:\[[^\]]*\])+)$/)
      if (!match || typeof value !== "string") continue
      const data = blocks.get(match[1]) || Object.create(null)
      blocks.set(match[1], data)
      const keys = [...match[2].matchAll(/\[([^\]]*)\]/g)].map(part => part[1])
      let node = data
      keys.forEach((key, index) => {
        if (index === keys.length - 1) { if (Array.isArray(node)) node.push(value); else node[key] = value }
        else node = node[key] ||= keys[index + 1] === "" ? [] : Object.create(null)
      })
      body.delete(name)
    }
    blocks.forEach((data, name) => body.set(`${name}[data_payload]`, JSON.stringify(data)))
  }

  beforeSubmit() {
    this.finishEditing()
    clearTimeout(this.timer)
    this.abort?.abort()
    this.submitting = true
  }

  afterSubmit() { this.submitting = false }

  saveStatus(text, state = "") {
    this.saveStatusTarget.textContent = text
    this.saveStatusTarget.dataset.state = state
  }

  // ---- Prévia: clique, hover e edição no lugar ----

  bindPreview() {
    const doc = this.doc
    if (!doc) return

    // Links e botões da página não navegam na prévia: o clique só escolhe o que editar.
    doc.addEventListener("click", (event) => {
      if (this.editing?.el.contains(event.target)) return
      const text = event.target.closest?.("summary, h1, h2, h3, .public-theme-block-faq__answer, .public-theme-block-text__body, .public-theme-content-callout__text")
      if (!text) return this.previewClick(event)
      event.preventDefault()
      clearTimeout(this.previewClickTimer)
      this.previewClickTimer = setTimeout(() => this.previewClick(event), 300)
    }, true)
    doc.addEventListener("dblclick", (event) => { clearTimeout(this.previewClickTimer); this.previewClick(event) }, true)
    doc.addEventListener("input", (event) => {
      if (!event.target.matches('[data-public-faq-target="search"]')) return
      const faq = event.target.closest(".public-theme-block-faq")
      applyFAQFilters(faq, faq.dataset.previewCategory || "", event.target.value)
    })
    doc.addEventListener("submit", (event) => event.preventDefault(), true)
    doc.addEventListener("mouseover", (event) => {
      const wrapper = event.target.closest?.(".lp-preview-block")
      if (wrapper && !this.dragging) this.hoverBlock(wrapper.dataset.blockPosition)
    })
    doc.documentElement.addEventListener("mouseleave", () => this.hoverLeave())
    doc.addEventListener("scroll", () => this.positionTools(), true)
    doc.defaultView.addEventListener("scroll", () => this.positionTools())
  }

  previewClick(event) {
    const target = event.target
    if (this.editing?.el.contains(target)) return
    event.preventDefault()
    const faqFilter = target.closest?.('[data-public-faq-target="filter"]')
    if (faqFilter) {
      const faq = faqFilter.closest(".public-theme-block-faq")
      faq.dataset.previewCategory = faqFilter.dataset.category
      applyFAQFilters(faq, faq.dataset.previewCategory, faq.querySelector('[data-public-faq-target="search"]')?.value || "")
      return
    }
    const faqItem = target.closest?.("[data-faq-row-index]")
    if (faqItem) {
      const wrapper = faqItem.closest(".lp-preview-block")
      const card = this.cardAt(wrapper.dataset.blockPosition)
      const row = card.querySelectorAll(".ax-dynamic-list__item")[Number(faqItem.dataset.faqRowIndex)]
      const answer = target.closest(".public-theme-block-faq__answer, .public-theme-content-callout__text")
      const summary = target.closest("summary, [data-element-field='title']")
      const badge = target.closest("[data-element-field='badge']")
      if (summary?.parentElement.tagName === "DETAILS") summary.parentElement.open = true
      const el = badge || answer || summary || faqItem.querySelector("details, .public-theme-content-callout") || faqItem
      this.finishEditing()
      this.markSelected(wrapper.dataset.blockPosition)
      this.revealCard(card)
      const key = badge ? "badge" : answer ? "text" : summary ? "title" : null
      this.inspectCard(card, ["items"], badge ? "Editar etiqueta" : answer ? "Editar resposta" : summary ? "Editar pergunta" : "Editar card")
      this.inspectItemRow(card, row, key ? [key] : null)
      this.selectPreviewElement(el)
      this.elementHierarchy(card)
      const input = key && row?.querySelector(`[name$='[${key}]']`)
      if (event.type === "dblclick" && input) this.startEditing(el, input, Boolean(answer), card)
      return
    }
    if (target.matches?.('[data-public-faq-target="search"]')) { target.focus(); return }
    if (this.editing?.el.contains(target)) return // clique dentro do texto em edição: só move o cursor

    this.finishEditing()
    const insert = target.closest?.(".lp-insert__btn")
    if (insert) return this.openMenu(insert, event)

    const wrapper = target.closest?.(".lp-preview-block")
    if (wrapper) this.editFromPreview(wrapper, target, event.type === "dblclick")
  }

  editFromPreview(wrapper, target, inline = false) {
    const position = wrapper.dataset.blockPosition
    const block = this.cardAt(position)
    if (!block) return

    this.markSelected(position)
    this.positionTools()

    const element = target.closest("[data-element-field]")
    if (element) {
      const field = element.dataset.elementField
      const input = block.querySelector(`[name$='[data][${field}]']`)
      if (input) {
        this.revealCard(block)
        const fields = [field, ...Array.from(block.querySelectorAll("[data-block-field]")).map(node => node.dataset.blockField).filter(name => name.startsWith(`element_${field}_`))]
        if (field === "badge") fields.push("badge_icon")
        this.inspectCard(block, fields, `Editar ${field === "title" || field === "heading" ? "título" : field === "eyebrow" || field === "badge" ? "etiqueta" : "texto"}`)
        this.selectPreviewElement(element)
        this.elementHierarchy(block, field === "eyebrow" || field === "badge")
        if (inline) this.startEditing(element, input, Boolean(block.querySelector(`trix-editor[input='${input.id}']`)), block)
        return
      }
    }
    const label = target.closest("[data-label-index]")
    const labels = target.closest("[data-element-group='labels']")
    if (labels) {
      this.revealCard(block)
      this.inspectCard(block, ["labels", ...(!label ? Array.from(block.querySelectorAll("[data-block-field]")).map(node => node.dataset.blockField).filter(name => name.startsWith("element_labels_")) : [])], label ? "Editar etiqueta" : "Editar grupo de etiquetas")
      if (label) this.inspectItemRow(block, block.querySelector("[data-block-field='labels']").querySelectorAll(".ax-dynamic-list__item")[Number(label.dataset.labelIndex)])
      this.selectPreviewElement(label || labels)
      this.elementHierarchy(block, true)
      return
    }
    const item = target.closest?.("[data-item-row-key]")
    if (item) {
      const input = [...block.querySelectorAll("[name$='[row_key]']")].find((input) => input.value === item.dataset.itemRowKey)
      if (input) {
        this.revealCard(block)
        const text = target.closest(".public-theme-block-collection__text, .public-theme-block-collection__quote")
        const title = target.closest(".public-theme-block-collection__title")
        const label = target.closest(".public-theme-block-collection__label, .public-theme-builder-badge")
        const key = target.closest("[data-item-element]")?.dataset.itemElement || (text ? "text" : title ? "title" : label ? (label.classList.contains("public-theme-builder-badge") ? "badge" : "label") : null)
        const row = input.closest(".ax-dynamic-list__item")
        this.inspectCard(block, ["items"], key ? (text ? "Editar texto" : "Editar título") : "Editar item")
        this.inspectItemRow(block, row, key ? [key] : null)
        this.selectPreviewElement(text || title || label || item)
        this.elementHierarchy(block)
        if (inline && key) this.startEditing(text || title || label || item, row.querySelector(`[name$='[${key}]']`), Boolean(text), block)
        return
      }
    }
    const button = target.closest?.("a")
    if (button && ["callout", "cover", "button"].includes(block.dataset.blockType)) {
      this.selectPreviewElement(button)
      const secondary = button.className.includes("secondary")
      const fields = block.dataset.blockType === "button" ? ["label", "url", "icon", "style", "align", "size", "custom_colors", "background_color", "text_color"] : secondary ? ["secondary_label", "secondary_url", "secondary_icon", "secondary_custom_colors", "secondary_background_color", "secondary_text_color"] : ["button_label", "button_url", "button_icon", "button_custom_colors", "button_background_color", "button_text_color"]
      const prefix = block.dataset.blockType === "button" ? "" : secondary ? "secondary_" : "button_"
      const custom = block.querySelector(`input[name$='[data][${prefix}custom_colors]']`)
      if (custom?.value !== "true") {
        const computed = this.doc.defaultView.getComputedStyle(button)
        ;[["background_color", computed.backgroundColor], ["text_color", computed.color]].forEach(([key, value]) => {
          const channels = value.match(/\d+/g)
          if (!channels || channels.length < 3 || (channels.length > 3 && Number(channels[3]) === 0)) return
          const hex = `#${channels.slice(0, 3).map((channel) => Number(channel).toString(16).padStart(2, "0")).join("")}`
          block.querySelectorAll(`input[name$='[${prefix}${key}]']`).forEach((input) => { input.value = hex })
        })
      }
      this.revealCard(block)
      this.inspectCard(block, fields, "Editar botão")
      this.elementHierarchy(block)
      block.querySelector(`[data-block-field='${fields[0]}'] input`)?.focus({ preventScroll: true })
      return
    }
    this.revealCard(block)
    const map = FIELD_FOR_CLASS[block.dataset.blockType] || {}
    const hit = Object.keys(map).find((name) => target.closest?.(`.${name}`))
    const spec = hit && map[hit]
    const field = spec && (spec.field || spec)
    const input = field && block.querySelector(`[name$='[data][${field}]']`)

    // Texto dos campos simples e do corpo: edita ali mesmo.
    if (hit && input) {
      this.inspectCard(block, [field, ...Array.from(block.querySelectorAll("[data-block-field]")).map(node => node.dataset.blockField).filter(name => name.startsWith(`element_${field}_`))], `Editar ${field === "heading" || field === "title" ? "título" : "texto"}`)
      this.selectPreviewElement(target.closest(`.${hit}`))
      this.elementHierarchy(block)
      if (inline) this.startEditing(target.closest(`.${hit}`), input, Boolean(spec.rich), block)
      return
    }

    this.revealCard(block)
    this.selectedElementSelector = null
    this.doc.querySelectorAll(".lp-selected-element").forEach(node => node.classList.remove("lp-selected-element"))
    this.elementHierarchy(block)
    if (!this.element.classList.contains("lp-canvas-editor")) block.scrollIntoView({ block: "center", behavior: "smooth" })
    block.querySelector("input:not([type='hidden']):not([type='checkbox']):not([type='file']), select, textarea")?.focus({ preventScroll: true })
  }

  elementHierarchy(card) {
    this.renderElementPanel(card)
  }

  renderElementPanel(card) {
    if (!this.element.classList.contains("lp-canvas-editor")) return
    this.element.querySelector(".lp-element-hierarchy")?.remove()
    this.element.querySelector(".lp-element-panel")?.remove()
    this.element.querySelector(".lp-element-breadcrumb")?.remove()
    const name = card.querySelector(".lp-block__title strong")?.textContent || "Bloco"
    const level = card.dataset.blockType === "section" ? "Seção" : card.dataset.blockType === "callout" ? "Card" : "Bloco"
    const selectedKey = this.inspectedItemKeys?.[0] || this.inspectedFields?.find(key => ["heading", "title", "text", "body", "subtitle", "badge", "eyebrow", "caption"].includes(key))
    const selectedPart = !this.parentInspector && selectedKey ? ({ heading: "Título", title: "Título", text: "Texto", body: "Texto", subtitle: "Texto", badge: "Etiqueta", eyebrow: "Etiqueta", caption: "Legenda" }[selectedKey] || "Elemento") : null
    this.inspectorTitleTarget.textContent = selectedPart ? `Editar ${selectedPart.toLowerCase()} · ${name}` : `${level} · ${name}`
    const panel = document.createElement("div")
    panel.className = "lp-element-panel"
    const breadcrumb = document.createElement("div")
    breadcrumb.className = "lp-element-breadcrumb"
    breadcrumb.textContent = `Página › ${level}: ${name}${selectedPart ? ` › ${selectedPart}` : ""}`
    const tabs = document.createElement("div")
    tabs.className = "lp-element-panel__tabs"
    const makeButton = (label, handler) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "ax-btn ax-btn--secondary ax-btn--sm"
      button.textContent = label
      button.addEventListener("click", handler)
      return button
    }
    ;[["Elementos", "elements"], ["Configurações", "configuration"]].forEach(([label, mode]) => {
      const button = makeButton(label, () => this.parentPanel(card, mode))
      button.setAttribute("aria-pressed", String((this.element.dataset.elementPanel || "elements") === mode))
      tabs.append(button)
    })
    this.inspectorTitleTarget.closest(".lp-inspector-heading").prepend(breadcrumb)
    panel.append(tabs)
    const hint = document.createElement("p")
    hint.className = "lp-element-panel__hint"
    hint.textContent = selectedPart ? `Você está editando apenas ${selectedPart.toLowerCase()}. As cores e bordas afetam este elemento.` : level === "Card" ? "Configurações alteram o card arredondado. Em Elementos, edite título, texto e botões separadamente." : `Configurações alteram ${level.toLowerCase()} inteiro. Em Elementos, selecione um item para editar somente ele.`
    panel.append(hint)
    const elements = this.previewElements(card)
    if (this.element.dataset.elementPanel !== "configuration") {
      const header = document.createElement("div")
      header.className = "lp-element-panel__list-header"
      const count = document.createElement("strong")
      count.textContent = `${elements.length} elementos`
      header.append(count, makeButton("Adicionar", () => this.addElement(card)))
      panel.append(header)
      const list = document.createElement("div")
      list.className = "lp-element-panel__list"
      elements.forEach(element => {
        const { key, node, name: label, icon } = element
        const row = this.element.querySelector("[data-builder-element-template]").content.firstElementChild.cloneNode(true)
        row.dataset.elementKey = key
        row.querySelector("strong").textContent = label
        row.querySelector("small").textContent = node.textContent.trim().replace(/\s+/g, " ").slice(0, 100)
        row.querySelector(".ax-sortable-element__icon i").classList.add(`bi-${icon}`)
        const active = this.selectedElementSelector && node.matches(this.selectedElementSelector)
        row.classList.toggle("is-selected", Boolean(active && !this.parentInspector))
        row.querySelector("[data-element-edit]").addEventListener("click", () => {
          this.finishEditing()
          if (element.formRow) {
            this.editFromPreview(node.closest(".lp-preview-block"), node)
          } else if (element.card) {
            this.markSelected(this.positionOf(element.card))
            this.revealCard(element.card)
          } else if (key === "items" || key === "actions" || key === "labels") {
            this.inspectCard(card, key === "actions" ? ["button_label", "button_url", "button_icon", "secondary_label", "secondary_url", "secondary_icon"] : [key], `Editar ${label.toLowerCase()}`)
            this.selectPreviewElement(node)
            this.renderElementPanel(card)
          } else this.editFromPreview(node.closest(".lp-preview-block"), node)
        })
        row.querySelector(".ax-sortable-element__grip").addEventListener("keydown", event => {
          if (!["ArrowUp", "ArrowDown"].includes(event.key)) return
          event.preventDefault()
          const index = elements.findIndex(element => element.key === key)
          const target = elements[index + (event.key === "ArrowUp" ? -1 : 1)]
          if (target) this.moveElement(card, key, target.key)
        })
        row.addEventListener("dragstart", event => { this.elementDragging = key; event.dataTransfer.setData("text/plain", key); event.dataTransfer.effectAllowed = "move"; event.stopPropagation() })
        row.addEventListener("dragover", event => { event.preventDefault(); event.stopPropagation(); row.classList.add("is-drop-target") })
        row.addEventListener("dragleave", () => row.classList.remove("is-drop-target"))
        row.addEventListener("drop", event => { event.preventDefault(); event.stopPropagation(); row.classList.remove("is-drop-target"); if (this.elementDragging) this.moveElement(card, this.elementDragging, key); this.elementDragging = null })
        row.addEventListener("dragend", () => { this.elementDragging = null; list.querySelectorAll(".is-drop-target").forEach(item => item.classList.remove("is-drop-target")) })
        list.append(row)
      })
      panel.append(list)
      if (!this.parentInspector && this.inspectedFields) {
        const context = document.createElement("div")
        context.className = "lp-element-panel__context"
        const field = this.inspectedFields[0]
        const selected = elements.find(item => item.key === field)
        const key = this.inspectedItemKeys?.[0]
        const rowTitle = this.inspectedRow?.querySelector("[name$='[title]']")?.value
        const partName = key ? ({ title: "Título", text: "Texto", label: "Número / legenda", badge: "Etiqueta" }[key] || "Elemento") : null
        context.textContent = [name, rowTitle ? `Card: ${rowTitle}` : null, partName || selected?.name || (this.inspectedRow ? "Card" : "Elemento")].filter(Boolean).join(" › ")
        panel.append(context)
      }
    }
    this.inspectorTitleTarget.closest(".lp-inspector-heading").after(panel)
    this.element.dataset.parentInspector = String(Boolean(this.parentInspector))
  }

  previewElements(card) {
    const wrapper = this.doc?.querySelector(`.lp-preview-block[data-block-position='${this.positionOf(card)}']`)
    if (!wrapper) return []
    const names = { title: ["Título", "type"], heading: ["Título", "type"], subtitle: ["Texto", "text-left"], body: ["Texto", "text-left"], text: ["Texto", "text-left"], eyebrow: ["Etiqueta", "tag"], badge: ["Etiqueta", "tag"], labels: ["Etiquetas", "tags"], items: ["Itens do bloco", "grid"], actions: ["Botões", "cursor"], caption: ["Legenda", "text-left"] }
    const nodes = [...wrapper.querySelectorAll("[data-element-field], [data-element-group], .public-theme-block-cover__actions, .public-theme-content-callout__actions, .public-theme-block-collection__items")].filter(node => node.closest(".lp-preview-block") === wrapper && !node.closest("[data-item-row-key], [data-faq-row-index]") && node.textContent.trim())
    const elements = nodes.filter(node => !node.classList.contains("public-theme-block-collection__items")).map(node => {
      const key = node.dataset.elementField || node.dataset.elementGroup || (node.className.includes("__actions") ? "actions" : "items")
      const [name, icon] = names[key] || ["Elemento", "square"]
      return { key, node, name, icon }
    })
    wrapper.querySelectorAll("[data-item-row-key], [data-faq-row-index], [data-label-index]").forEach((node, index) => {
      if (node.closest(".lp-preview-block") !== wrapper) return
      const field = node.hasAttribute("data-label-index") ? "labels" : "items"
      const rows = card.querySelector(`[data-block-field='${field}']`)?.querySelectorAll(".ax-dynamic-list__item") || []
      const formRow = node.dataset.itemRowKey ? [...rows].find(row => row.querySelector("[name$='[row_key]']")?.value === node.dataset.itemRowKey) : rows[Number(node.dataset.faqRowIndex ?? node.dataset.labelIndex)]
      if (formRow) elements.push({ key: `${field}_${index}`, node, formRow, name: field === "labels" ? "Etiqueta" : (formRow.querySelector("[name$='[title]']")?.value || "Item"), icon: field === "labels" ? "tag" : "card-text" })
    })
    if (card.dataset.blockType === "section") this.sectionMembers(card).slice(1).forEach(child => {
      const node = this.doc.querySelector(`.lp-preview-block[data-block-position='${this.positionOf(child)}']`)
      if (node) elements.push({ key: `block_${this.positionOf(child)}`, node, card: child, name: child.querySelector(".lp-block__title strong")?.textContent.trim() || "Bloco", icon: "layout-text-window" })
    })
    return elements
  }

  parentPanel(card, mode = "elements") {
    this.finishEditing()
    this.inspectCard(card)
    this.element.dataset.elementPanel = mode
    if (mode === "configuration") {
      const wrapper = this.doc?.querySelector(`.lp-preview-block[data-block-position='${this.positionOf(card)}']`)
      const surface = (card.dataset.blockType === "callout" ? wrapper?.querySelector(".public-theme-content-callout") : wrapper?.querySelector("section")) || wrapper?.closest("section") || wrapper
      if (surface) this.readElementStyle(surface, "block_")
    }
    this.inspectorAppearance({ currentTarget: this.element.querySelector(".lp-inspector-tabs [data-panel='content']") })
    this.renderElementPanel(card)
  }

  addElement(card) {
    if (card.dataset.blockType === "section") {
      this.menuSection = card
      this.menuColumn = "1"
      this.menuBefore = "end"
      this.menuTarget.querySelector("[data-block-type='section']").hidden = true
      this.menuTarget.hidden = false
      this.menuTarget.style.left = `${Math.max(8, this.stageTarget.clientWidth - this.menuTarget.offsetWidth - 8)}px`
      this.menuTarget.style.top = "64px"
      return
    }
    const fields = card.querySelector("[data-block-field='labels']") ? ["labels"] : card.querySelector("[data-block-field='items']") ? ["items"] : ["heading", "body", "subtitle", "button_label", "button_url"]
    this.inspectCard(card, fields, "Adicionar elemento")
    card.querySelector(`[data-block-field='${fields[0]}'] [data-action='dynamic-list#add']`)?.click()
    this.renderElementPanel(card)
  }

  moveElement(card, source, target) {
    const elements = this.previewElements(card)
    const from = elements.find(item => item.key === source)
    const to = elements.find(item => item.key === target)
    if (!from || !to || from === to || from.node.parentElement !== to.node.parentElement) return
    if (from.formRow && to.formRow && from.formRow.parentElement === to.formRow.parentElement) {
      const movingDown = elements.indexOf(from) < elements.indexOf(to)
      if (movingDown) to.formRow.after(from.formRow)
      else to.formRow.before(from.formRow)
      this.schedule()
      return
    }
    if (from.card && to.card) {
      this.placeBlock(from.card, to.card, elements.indexOf(from) > elements.indexOf(to))
      this.reindex()
      this.selectedPosition = this.positionOf(card)
      this.changed()
      return
    }
    const keys = elements.map(item => item.key)
    const movingDown = keys.indexOf(source) < keys.indexOf(target)
    keys.splice(keys.indexOf(source), 1)
    keys.splice(keys.indexOf(target) + (movingDown ? 1 : 0), 0, source)
    card.querySelector("[name$='[data][element_order]']").value = keys.join(",")
    if (movingDown) to.node.after(from.node)
    else to.node.before(from.node)
    this.schedule()
    this.renderElementPanel(card)
  }

  startEditing(el, input, rich, card) {
    this.editing = { el, input, rich, card, original: rich ? input.value : input.value }
    if (rich) return this.startInlineRichEditor(el, input)
    el.contentEditable = "plaintext-only"
    el.focus()
    const range = this.doc.createRange()
    range.selectNodeContents(el)
    range.collapse(false)
    const selection = this.doc.defaultView.getSelection()
    selection.removeAllRanges()
    selection.addRange(range)

    this.editHandlers = {
      input: () => this.writeEditing(),
      blur: () => this.finishEditing(),
      keydown: (event) => {
        if (event.key === "Escape") this.cancelEditing()
        else if (event.key === "Enter" && !rich) { event.preventDefault(); el.blur() }
      }
    }
    Object.entries(this.editHandlers).forEach(([name, handler]) => el.addEventListener(name, handler))
    if (rich) this.showRichbar(el)
  }

  startInlineRichEditor(el, input) {
    this.fit()
    const rect = el.getBoundingClientRect()
    const host = document.createElement("div")
    host.className = "lp-inline-trix"
    host.style.left = `${this.frameLeft + rect.left * this.scale}px`
    host.style.top = `${rect.top * this.scale}px`
    host.style.width = `${Math.min(rect.width * this.scale, this.stageTarget.clientWidth - 16)}px`
    const source = document.createElement("input")
    source.type = "hidden"
    source.id = `lp-inline-text-${Date.now()}`
    const initialHTML = input.value
    source.setAttribute("value", initialHTML)
    let ready = false
    const editor = document.createElement("trix-editor")
    editor.setAttribute("input", source.id)
    editor.setAttribute("aria-label", "Editar texto no elemento")
    editor.addEventListener("trix-change", () => {
      if (!ready || !this.editing) return
      input.value = source.value
      input.dispatchEvent(new Event("input", { bubbles: true }))
    })
    editor.addEventListener("trix-file-accept", (event) => event.preventDefault())
    const done = document.createElement("button")
    done.type = "button"
    done.className = "ax-btn ax-btn--primary ax-btn--sm"
    done.textContent = "Concluir edição"
    done.addEventListener("click", () => this.finishEditing())
    host.addEventListener("keydown", (event) => { if (event.key === "Escape") this.cancelEditing() })
    host.append(source, editor, done)
    this.inlineRichHost = host
    this.editHandlers = {}
    editor.addEventListener("trix-initialize", () => { editor.editor.loadHTML(initialHTML); ready = true; editor.focus() }, { once: true })
    this.stageTarget.append(host)
  }

  // Cada tecla grava no input do cartão; o canvas permanece local durante a edição.
  writeEditing() {
    const { el, input, rich } = this.editing
    input.value = rich ? el.innerHTML : el.innerText.replace(/\n+/g, " ").trim()
    input.dispatchEvent(new Event("input", { bubbles: true }))
  }

  finishEditing() {
    if (!this.editing) return

    const { el, input, rich, card } = this.editing
    Object.entries(this.editHandlers).forEach(([name, handler]) => el.removeEventListener(name, handler))
    el.removeAttribute("contenteditable")
    this.editing = null
    this.inlineRichHost?.remove()
    this.inlineRichHost = null
    this.richbarTarget.hidden = true
    // O Trix do cartão passa a mostrar o texto novo.
    if (rich) Array.from(card.querySelectorAll("trix-editor")).find((editor) => editor.getAttribute("input") === input.id)?.editor?.loadHTML(input.value)
    this.reindex()
    if (this.pendingRender) this.render()
  }

  cancelEditing() {
    if (!this.editing) return

    const { input, original } = this.editing
    input.value = original
    input.dispatchEvent(new Event("input", { bubbles: true }))
    if (this.inlineRichHost) this.finishEditing()
    else this.editing.el.blur()
  }

  // ---- Barra de texto formatado ----

  showRichbar(el) {
    const rect = el.getBoundingClientRect()
    const bar = this.richbarTarget
    bar.hidden = false
    bar.style.left = `${Math.max(4, this.frameLeft + rect.left * this.scale)}px`
    bar.style.top = `${Math.max(4, rect.top * this.scale - bar.offsetHeight - 8)}px`
  }

  richMouseDown(event) {
    event.preventDefault() // mantém a seleção do texto na prévia
  }

  richClick(event) {
    const button = event.target.closest("button[data-cmd]")
    if (!button || !this.editing) return

    const command = button.dataset.cmd
    this.doc.defaultView.focus()
    if (command === "link") {
      const url = window.prompt("Endereço do link (https://… ou /pagina)")
      if (url) this.doc.execCommand("createLink", false, url)
    } else {
      this.doc.execCommand(command, false, null)
    }
    this.writeEditing()
  }

  // ---- Ferramentas do bloco (barra flutuante) ----

  hoverBlock(position) {
    clearTimeout(this.hideTimer)
    this.hoverPosition = position
    this.positionTools()
  }

  hoverLeave() {
    clearTimeout(this.hideTimer)
    this.hideTimer = setTimeout(() => { this.hoverPosition = null; this.positionTools() }, 250)
  }

  keepTools() {
    clearTimeout(this.hideTimer)
  }

  toolsLeave() {
    this.hoverLeave()
  }

  markSelected(position) {
    if (String(this.selectedPosition) !== String(position)) this.selectedElementSelector = null
    this.selectedPosition = position
    this.doc?.querySelectorAll(".lp-preview-block").forEach((item) => {
      item.classList.toggle("is-selected", position != null && item.dataset.blockPosition === String(position))
    })
  }

  // Cartão do editor em foco -> bloco destacado na prévia.
  selectBlock(event) {
    const block = event.target.closest?.(BLOCK)
    if (!block) return

    this.markSelected(this.positionOf(block))
    this.positionTools()
  }

  activePosition() {
    return this.dragging ? null : (this.hoverPosition ?? this.selectedPosition)
  }

  positionTools() {
    const tools = this.toolsTarget
    const position = this.activePosition()
    const wrapper = position != null && this.doc?.querySelector(`.lp-preview-block[data-block-position='${position}']`)
    const card = position != null && this.cardAt(position)
    if (!wrapper || !card || this.editing) {
      tools.hidden = true
      return
    }

    const rect = wrapper.getBoundingClientRect()
    if (rect.bottom < 40 || rect.top > this.frameTarget.clientHeight) {
      tools.hidden = true
      return
    }

    const type = card.dataset.blockType
    tools.dataset.position = position
    tools.querySelectorAll("[data-for]").forEach((group) => { group.hidden = !group.dataset.for.split(" ").includes(type) })
    tools.querySelectorAll("[data-only-for]").forEach((item) => { item.hidden = item.dataset.onlyFor !== type })
    const span = card.querySelector("[name$='[data][span]']")
    const section = this.liveBlocks().slice(0, this.liveBlocks().indexOf(card)).findLast((block) => block.dataset.blockType === "section")
    const spanTool = tools.querySelector("[data-tool='span']")
    spanTool.hidden = Boolean(section) || type === "section"
    if (span) spanTool.value = span.value
    const columnTool = tools.querySelector("[data-tool='column']")
    columnTool.hidden = !section || type === "section"
    const columnCount = Number(section?.querySelector("[name$='[data][columns]']")?.value || 3)
    Array.from(columnTool.options).forEach((option) => { option.disabled = Number(option.value) > columnCount })
    columnTool.value = card.querySelector("[name$='[data][column]']")?.value || "1"
    tools.querySelectorAll("[data-not-for]").forEach((button) => { button.hidden = button.dataset.notFor === type })
    const align = card.querySelector("[name$='[data][align]']")?.value
    tools.querySelectorAll("[data-tool='align']").forEach((button) => button.classList.toggle("is-active", button.dataset.value === align))
    const overlay = card.querySelector("[name$='[data][overlay]']")
    if (overlay) tools.querySelector("[data-tool='overlay']").value = overlay.value

    tools.hidden = false
    const left = this.frameLeft + rect.right * this.scale - tools.offsetWidth - 8
    tools.style.left = `${Math.max(4, left)}px`
    const above = rect.top * this.scale - tools.offsetHeight - 6
    const top = above >= 4 ? above : rect.bottom * this.scale + 6
    tools.style.top = `${Math.max(4, Math.min(top, this.stageTarget.clientHeight - tools.offsetHeight - 4))}px`
  }

  toolMouseDown(event) {
    const grip = event.target.closest("[data-tool='grip']")
    if (grip) this.startDrag(event)
  }

  toolClick(event) {
    const button = event.target.closest("button[data-tool]")
    const position = this.toolsTarget.dataset.position
    const card = position != null && this.cardAt(position)
    if (!button || !card) return

    switch (button.dataset.tool) {
      case "up": return this.moveCard(card, -1)
      case "down": return this.moveCard(card, 1)
      case "edit":
        this.revealCard(card)
        card.scrollIntoView({ block: "center", behavior: "smooth" })
        return
      case "hide":
        card.querySelector("input[type='checkbox'][name$='[visible]']").click()
        this.status("Bloco oculto. Para mostrar de novo, use o olho no cartão do editor.")
        return
      case "duplicate": {
        const members = this.sectionMembers(card)
        const before = members.at(-1).nextElementSibling
        const copies = members.map((member) => this.addBlock(member.dataset.blockType, before, member))
        if (copies[0]) this.selectedPosition = this.positionOf(copies[0])
        return
      }
      case "remove": return this.removeCard(card)
      case "align": return this.setCardValue(card, "align", button.dataset.value)
      case "image": return card.querySelector("input[type='file'][name$='[image_desktop]']")?.click()
      case "width": {
        const current = card.querySelector("[name$='[data][width]']")?.value
        return this.setCardValue(card, "width", current === "wide" ? "narrow" : "wide")
      }
    }
  }

  toolChange(event) {
    const select = event.target.closest("select[data-tool]")
    const card = this.cardAt(this.toolsTarget.dataset.position)
    if (select && card) this.setCardValue(card, select.dataset.tool, select.value)
  }

  setCardValue(card, field, value) {
    const input = card.querySelector(`[name$='[data][${field}]']`)
    if (!input) return

    input.value = value
    input.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // ---- Inserir bloco entre blocos ----

  // Botões "+" nas emendas (e o convite da página vazia), feitos no iframe a cada renderização.
  decorate() {
    const doc = this.doc
    const root = doc?.querySelector(".public-landing-page")
    if (!root) return
    doc.querySelectorAll("[data-section-column]").forEach((column) => {
      if (column.querySelector(".lp-preview-block")) return
      const insert = doc.createElement("div")
      insert.className = "lp-insert lp-insert--empty"
      insert.dataset.sectionPosition = column.dataset.sectionPosition
      insert.dataset.column = column.dataset.sectionColumn
      insert.innerHTML = '<button type="button" class="lp-insert__btn">+ Adicionar bloco nesta coluna</button>'
      column.append(insert)
    })

    // Unidades da página: bloco de linha inteira ou linha de colunas (que guarda vários blocos).
    const firstPosition = (unit) => (unit.classList.contains("lp-preview-block") ? unit : unit.querySelector(".lp-preview-block"))?.dataset.blockPosition
    const units = [...root.children].filter((el) => firstPosition(el) !== undefined)
    const make = (before, extra = "") => {
      const insert = doc.createElement("div")
      insert.className = `lp-insert ${extra}`
      insert.dataset.before = before
      insert.innerHTML = `<button type="button" class="lp-insert__btn" aria-label="Adicionar bloco aqui" title="Adicionar bloco aqui">${extra.includes("empty") ? "+ Adicionar bloco" : "+"}</button>`
      return insert
    }
    if (units.length === 0) return root.append(make("end", "lp-insert--empty"))

    units.forEach((unit, index) => unit.before(make(firstPosition(unit), index === 0 ? "lp-insert--first" : "")))
    units.at(-1).after(make("end"))
  }

  openMenu(button, event) {
    const insert = button.closest(".lp-insert")
    this.menuSection = insert.dataset.sectionPosition ? this.cardAt(insert.dataset.sectionPosition) : null
    this.menuColumn = insert.dataset.column
    this.menuTarget.querySelector("[data-block-type='section']").hidden = Boolean(this.menuSection)
    this.menuBefore = insert.dataset.before
    const rect = button.getBoundingClientRect()
    const menu = this.menuTarget
    menu.hidden = false
    menu.style.left = `${Math.min(this.stageTarget.clientWidth - menu.offsetWidth - 8, Math.max(8, this.frameLeft + rect.left * this.scale))}px`
    menu.style.top = `${Math.min(this.stageTarget.clientHeight - menu.offsetHeight - 8, Math.max(8, rect.bottom * this.scale + 6))}px`
  }

  menuClick(event) {
    const button = event.target.closest("button[data-block-type]")
    if (!button) return

    this.menuTarget.hidden = true
    const owner = this.menuSection
    const before = owner ? this.sectionMembers(owner).at(-1).nextElementSibling?.closest(BLOCK) : this.menuBefore === "end" ? null : this.cardAt(this.menuBefore)
    const card = this.addBlock(button.dataset.blockType, before)
    if (owner && card) {
      this.sectionMembers(owner).at(-1).after(card)
      card.querySelector("[name$='[data][column]']").value = this.menuColumn
      this.reindex()
      this.changed()
    }
    this.menuSection = null
    if (card) this.selectedPosition = this.positionOf(card)
  }

  // ---- Arrastar blocos pelo ⠿ ----

  startDrag(event) {
    event.preventDefault()
    const position = this.toolsTarget.dataset.position
    const card = this.cardAt(position)
    if (!card) return

    this.dragging = { card, index: null }
    this.toolsTarget.hidden = true
    this.shieldTarget.hidden = false
    const move = (moveEvent) => this.dragMove(moveEvent)
    const stop = () => {
      this.shieldTarget.removeEventListener("mousemove", move)
      document.removeEventListener("mouseup", stop)
      this.dragEnd()
    }
    this.shieldTarget.addEventListener("mousemove", move)
    document.addEventListener("mouseup", stop)
  }

  // Destino = antes do primeiro bloco cujo meio está abaixo do cursor (ou no fim).
  dragMove(event) {
    const stage = this.stageTarget.getBoundingClientRect()
    const y = (event.clientY - stage.top) / this.scale
    const x = (event.clientX - stage.left - this.frameLeft) / this.scale
    const pageWidth = this.doc.documentElement.clientWidth
    const wrappers = [...this.doc.querySelectorAll(".lp-preview-block")]
    this.dragging.column = null
    const column = this.dragging.card.dataset.blockType !== "section" && [...this.doc.querySelectorAll("[data-section-column]")].find((element) => {
      const rect = element.getBoundingClientRect()
      const grid = element.parentElement.getBoundingClientRect()
      return x >= rect.left && x <= rect.right && y >= grid.top && y <= grid.bottom
    })
    if (column) {
      const children = [...column.querySelectorAll(".lp-preview-block")].filter((item) => item.dataset.blockPosition !== this.positionOf(this.dragging.card))
      const next = children.find((item) => y < item.getBoundingClientRect().top + item.getBoundingClientRect().height / 2)
      this.dragging.column = column.dataset.sectionColumn
      this.dragging.section = column.dataset.sectionPosition
      this.dragging.before = next?.dataset.blockPosition || null
      const rect = column.getBoundingClientRect()
      this.droplineTarget.hidden = false
      this.droplineTarget.style.left = `${this.frameLeft + rect.left * this.scale}px`
      this.droplineTarget.style.width = `${rect.width * this.scale}px`
      this.droplineTarget.style.top = `${(next ? next.getBoundingClientRect().top : children.at(-1)?.getBoundingClientRect().bottom || rect.top) * this.scale}px`
      return
    }
    this.droplineTarget.style.left = "0"
    this.droplineTarget.style.width = "100%"
    // Blocos em coluna (estreitos): dentro da faixa vertical compara a posição horizontal; os demais, o meio vertical.
    const target = wrappers.find((wrapper) => {
      const rect = wrapper.getBoundingClientRect()
      if (rect.width < pageWidth * 0.95 && y >= rect.top && y <= rect.bottom) return x < rect.left + rect.width / 2
      return y < rect.top + rect.height / 2
    })
    this.dragging.before = target ? target.dataset.blockPosition : "end"
    const edge = target ? target.getBoundingClientRect().top : wrappers.at(-1)?.getBoundingClientRect().bottom ?? 0
    this.droplineTarget.hidden = false
    this.droplineTarget.style.top = `${Math.max(0, edge * this.scale - 2)}px`
  }

  dragEnd() {
    const { card, before, column, section } = this.dragging
    this.dragging = null
    this.shieldTarget.hidden = true
    this.droplineTarget.hidden = true
    if (before === undefined) return

    if (column) {
      const owner = this.cardAt(section)
      if (!owner) return
      const target = before != null ? this.cardAt(before) : this.sectionMembers(owner).at(-1)
      if (target !== card) this.placeBlock(card, target, before != null)
      card.querySelector("[name$='[data][column]']").value = column
      this.reindex()
      this.selectedPosition = this.positionOf(card)
      this.changed()
      return
    }

    const target = before === "end" ? null : this.cardAt(before)
    if (target === card || target === card.nextElementSibling) return

    // Fim da lista = depois do último cartão visível.
    this.placeBlock(card, target, true)
    this.reindex()
    this.selectedPosition = this.positionOf(card)
    this.changed()
  }

  // ---- Imagem escolhida e ainda não salva ----

  // O servidor não recebe o arquivo na prévia: ela o mostra daqui (URL local do arquivo).
  applyPickedImages() {
    const doc = this.doc
    if (!doc) return

    this.liveBlocks().forEach((block) => {
      block.querySelectorAll("input[type='file'][name*='[item_uploads]']").forEach((input) => {
        const file = input.files?.[0]
        const key = input.closest(".ax-dynamic-list__item")?.querySelector("input[name$='[row_key]']")?.value
        const item = doc.querySelector(`.lp-preview-block[data-block-position='${this.positionOf(block)}'] [data-item-row-key='${key}']`)
        if (!file || !item) return

        let img = item.querySelector(".public-theme-block-collection__image")
        if (!img) {
          img = Object.assign(doc.createElement("img"), { className: "public-theme-block-collection__image", alt: "" })
          item.prepend(img)
        }
        img.src = URL.createObjectURL(file)
      })
    })

    this.liveBlocks().filter((block) => block.dataset.blockType === "image").forEach((block) => {
      const file = block.querySelector("input[type='file'][name$='[image_desktop]']")?.files?.[0]
      const figure = doc.querySelector(`.lp-preview-block[data-block-position='${this.positionOf(block)}'] .public-theme-block-image`)
      if (!file || !figure) return

      let img = figure.querySelector(".public-theme-block-image__img")
      if (!img) {
        img = Object.assign(doc.createElement("img"), { className: "public-theme-block-image__img", alt: "" })
        figure.querySelector(".public-theme-block-image__placeholder")?.replaceWith(img)
        figure.classList.remove("is-empty")
      }
      img.src = URL.createObjectURL(file)
    })

    this.liveBlocks().filter((block) => block.dataset.blockType === "video").forEach((block) => {
      const file = block.querySelector("input[type='file'][name$='[image_desktop]']")?.files?.[0]
      const frame = doc.querySelector(`.lp-preview-block[data-block-position='${this.positionOf(block)}'] .public-theme-block-video__frame`)
      if (!file || !frame) return
      let img = frame.querySelector(".public-theme-block-video__thumb")
      if (!img) {
        img = Object.assign(doc.createElement("img"), { className: "public-theme-block-video__thumb", alt: "" })
        frame.prepend(img)
      }
      img.src = URL.createObjectURL(file)
    })

    this.liveBlocks().filter((block) => block.dataset.blockType === "cover").forEach((block) => {
      const picked = (name) => block.querySelector(`input[type='file'][name$='[${name}]']`)?.files?.[0]
      const file = (this.device === "mobile" && picked("image_mobile")) || picked("image_desktop")
      const section = doc.querySelector(`.public-theme-block-cover[data-block-position='${this.positionOf(block)}']`)
      if (!file || !section) return

      let media = section.querySelector(".public-theme-block-cover__media")
      if (!media) {
        media = doc.createElement("picture")
        media.className = "public-theme-block-cover__media"
        media.innerHTML = '<img class="public-theme-block-cover__image" alt="">'
        section.prepend(media)
        section.classList.add("has-image")
      }
      media.querySelectorAll("source").forEach((source) => source.remove())
      media.querySelector("img").src = URL.createObjectURL(file)
    })
  }
}
