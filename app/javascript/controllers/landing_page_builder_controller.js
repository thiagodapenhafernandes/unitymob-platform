import { Controller } from "@hotwired/stimulus"
import { focusStep, goToStep, renderProgress } from "controllers/ax_guided"

// Editor visual de páginas por blocos.
// O servidor renderiza a página real (mesmo tema do site) com o que está no editor; o iframe é da mesma origem,
// então aqui ligamos a edição por cima dele: clicar num texto edita ali mesmo, passar o mouse num bloco mostra
// as ferramentas (mover, alinhar, duplicar, ocultar, remover), o + entre blocos insere e o ⠿ arrasta.
// Tudo grava nos inputs do próprio formulário (fonte única); em Rascunho salva sozinho.
const DESKTOP_WIDTH = 1280
const MOBILE_WIDTH = 390
const AUTOSAVE_MS = 1800
const BLOCK = "[data-landing-page-builder-target='block']"
const POSITION = "[data-landing-page-builder-target='position']"

// Elemento da prévia -> campo do cartão do bloco. rich = texto formatado (editor com barra própria).
const FIELD_FOR_CLASS = {
  cover: { "public-theme-block-cover__title": "title", "public-theme-block-cover__subtitle": "subtitle", "public-theme-block-cover__button": "button_label" },
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
    "list", "empty", "template", "block", "position", "destroy", "summary", "title", "slug", "frame", "stage", "device",
    "status", "saveStatus", "file", "tools", "richbar", "menu", "dropline", "shield", "addMenu", "addMenuList"
  ]
  // Status já salvo: "new" (ainda não criada), draft, published ou inactive. Só new/draft salvam sozinhas.
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
      if (!this.addMenuTarget.contains(event.target)) this.closeAddMenu()
    }
    this.onDocKey = (event) => {
      if (event.key === "Escape") { this.closeAddMenu(); this.menuTarget.hidden = true }
    }
    document.addEventListener("click", this.onDocPointer)
    document.addEventListener("keydown", this.onDocKey)
    // Página nova: o endereço acompanha o título até a pessoa editá-lo (ou a página ser salva).
    this.autoSlug = this.savedStatusValue === "new" && (this.slugTarget.value === "" || this.slugTarget.value === this.slugify(this.titleTarget.value))
    this.reindex()
    this.refreshProgress()
    this.render()
  }

  disconnect() {
    this.observer?.disconnect()
    this.frameTarget.removeEventListener("load", this.onFrameLoad)
    document.removeEventListener("mousedown", this.onDocMouseDown)
    document.removeEventListener("click", this.onDocPointer)
    document.removeEventListener("keydown", this.onDocKey)
    this.abort?.abort()
    clearTimeout(this.timer)
    clearTimeout(this.saveTimer)
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
  }

  // Posição = ordem na tela; resumo = primeiro texto do bloco; estado vazio.
  reindex() {
    this.liveBlocks().filter((block) => block.dataset.blockType === "section").forEach((section) => {
      const count = Number(section.querySelector("[name$='[data][columns]']").value)
      const members = this.sectionMembers(section)
      const overflow = members.slice(1).filter((block) => Number(block.querySelector("[name$='[data][column]']")?.value) > count)
      let tail = members.filter((block) => !overflow.includes(block)).at(-1)
      overflow.forEach((block) => { tail.after(block); tail = block })
    })
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
      if (block.dataset.blockType === "button") {
        const custom = block.querySelector("input[type='checkbox'][name$='[data][custom_colors]']")?.checked
        block.querySelectorAll("[data-block-field='text_color'],[data-block-field='background_color']").forEach((field) => { field.hidden = !custom })
      }
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
      let tail = section
      const count = Number(section.querySelector("[name$='[data][columns]']").value)
      for (let column = 1; column <= count; column++) {
        const columnBlocks = members.filter((block) => Number(block.querySelector("[name$='[data][column]']")?.value || 1) === column)
        columnBlocks.forEach((block) => { tail.after(block); tail = block })
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

  changed() {
    this.refreshProgress()
    this.schedule()
  }

  schedule() {
    this.reindex()
    this.queueAutosave()
    if (this.editing || this.dragging) {
      this.pendingRender = true
      return
    }

    clearTimeout(this.timer)
    this.status("Atualizando…")
    this.timer = setTimeout(() => this.render(), 400)
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
    this.markSelected(this.selectedPosition)
    this.positionTools()
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
    const width = this.device === "desktop" ? DESKTOP_WIDTH : MOBILE_WIDTH
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

  // ---- Autosave (só Rascunho) ----

  canAutosave() {
    const selected = this.element.querySelector("input[name='landing_page[status]']:checked")?.value
    return ["new", "draft"].includes(this.savedStatusValue) && (!selected || selected === "draft")
  }

  queueAutosave() {
    clearTimeout(this.saveTimer)
    if (!this.canAutosave()) {
      this.saveStatus("Salva sozinha só em Rascunho. Use Salvar para aplicar.")
      return
    }

    this.saveStatus("Alterações pendentes…")
    this.saveTimer = setTimeout(() => this.autosave(), AUTOSAVE_MS)
  }

  async autosave() {
    if (this.editing || this.dragging || this.saving) {
      this.queueAutosave()
      return
    }
    if (this.titleTarget.value.trim() === "") {
      this.saveStatus("Dê um título para salvar sozinha")
      return
    }

    this.saving = true
    this.saveStatus("Salvando…", "saving")
    const body = new FormData(this.element)
    body.delete("landing_page[status]") // publicar/inativar é sempre explícito
    try {
      const response = await fetch(this.element.action, {
        method: "POST",
        headers: { "X-CSRF-Token": this.csrfToken(), Accept: "application/json" },
        credentials: "same-origin",
        body
      })
      const data = await response.json()
      if (!response.ok || !data.ok) throw new Error((data.errors || ["erro"]).join(" "))

      this.afterAutosave(data)
      this.saveStatus("Rascunho salvo", "saved")
    } catch (error) {
      this.saveStatus(`Não salvou: ${error.message}`, "error")
    } finally {
      this.saving = false
    }
  }

  // Passa a editar a página salva: formulário vira PATCH, cartões ganham o id e a prévia enxerga as imagens salvas.
  afterAutosave(data) {
    if (this.savedStatusValue === "new") {
      this.savedStatusValue = "draft"
      this.autoSlug = false
      this.slugTarget.value = data.slug
      const method = document.createElement("input")
      Object.assign(method, { type: "hidden", name: "_method", value: "patch" })
      this.element.prepend(method)
      window.history.replaceState({}, "", data.edit_url)
    }
    this.element.action = data.update_url
    this.previewUrlValue = `${this.previewUrlValue.split("?")[0]}?id=${encodeURIComponent(data.slug)}`

    this.blockTargets.filter((block) => block.hidden).forEach((block) => block.remove()) // removidos: já saíram do banco
    data.blocks.forEach(({ position, id, item_image_keys }) => {
      const card = this.cardAt(position)
      if (!card) return
      card.querySelectorAll("input[name$='[image_key]']").forEach((input, index) => { input.value = item_image_keys?.[index] || "" })
      if (card.querySelector("input[name$='[id]']")) return

      const name = card.querySelector(POSITION).name.replace(/\[position\]$/, "[id]")
      const input = Object.assign(document.createElement("input"), { type: "hidden", name, value: id })
      card.querySelector(POSITION).after(input)
    })
    // Imagens enviadas e remoções já foram aplicadas: não reenviar no próximo autosave.
    this.fileTargets.forEach((input) => { input.value = "" })
    this.element.querySelectorAll("select[name$='[remove_image]']").forEach((input) => { input.value = "false" })
    this.element.querySelectorAll("input[type='checkbox'][name*='[remove_image_']:checked").forEach((box) => box.closest("label")?.remove())
  }

  saveStatus(text, state = "") {
    this.saveStatusTarget.textContent = text
    this.saveStatusTarget.dataset.state = state
  }

  // ---- Prévia: clique, hover e edição no lugar ----

  bindPreview() {
    const doc = this.doc
    if (!doc) return

    // Links e botões da página não navegam na prévia: o clique só escolhe o que editar.
    doc.addEventListener("click", (event) => this.previewClick(event), true)
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
    event.preventDefault()
    const target = event.target
    if (this.editing?.el.contains(target)) return // clique dentro do texto em edição: só move o cursor

    this.finishEditing()
    const insert = target.closest?.(".lp-insert__btn")
    if (insert) return this.openMenu(insert, event)

    const wrapper = target.closest?.(".lp-preview-block")
    if (wrapper) this.editFromPreview(wrapper, target)
  }

  editFromPreview(wrapper, target) {
    const position = wrapper.dataset.blockPosition
    const block = this.cardAt(position)
    if (!block) return

    this.markSelected(position)
    this.positionTools()

    const map = FIELD_FOR_CLASS[block.dataset.blockType] || {}
    const hit = Object.keys(map).find((name) => target.closest?.(`.${name}`))
    const spec = hit && map[hit]
    const field = spec && (spec.field || spec)
    const input = field && block.querySelector(`[name$='[data][${field}]']`)

    // Texto dos campos simples e do corpo: edita ali mesmo.
    if (hit && input) return this.startEditing(target.closest(`.${hit}`), input, Boolean(spec.rich), block)

    this.revealCard(block)
    block.scrollIntoView({ block: "center", behavior: "smooth" })
    block.querySelector("input:not([type='hidden']):not([type='checkbox']):not([type='file']), select, textarea")?.focus({ preventScroll: true })
  }

  startEditing(el, input, rich, card) {
    this.editing = { el, input, rich, card, original: rich ? input.value : input.value }
    el.contentEditable = rich ? "true" : "plaintext-only"
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

  // Cada tecla grava no input do cartão (fonte única); a prévia só recarrega ao terminar.
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
    this.richbarTarget.hidden = true
    // O Trix do cartão passa a mostrar o texto novo.
    if (rich) card.querySelector("trix-editor")?.editor?.loadHTML(input.value)
    this.reindex()
    if (this.pendingRender) this.render()
  }

  cancelEditing() {
    if (!this.editing) return

    const { input, original } = this.editing
    input.value = original
    input.dispatchEvent(new Event("input", { bubbles: true }))
    this.pendingRender = true
    this.editing.el.blur()
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
