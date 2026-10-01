import { Controller } from "@hotwired/stimulus"

// Preview ao vivo e editável do modal.
// O servidor renderiza o mesmo partial e CSS do site público com o estado atual do builder (sem salvar);
// o iframe é da mesma origem, então aqui ligamos a edição por cima dele:
//   - passar o mouse numa região mostra a ferramenta flutuante dela (cores, editar, campo...);
//   - clicar num texto edita ali mesmo; "Adicionar campo", clicar num campo e arrastar montam o formulário;
//   - benefícios e saída dos dados abrem um painel compacto.
// Tudo grava nos inputs do próprio formulário (fonte única) e, ao sair de cada edição, salva sozinho.
const WIDTHS = { desktop: 1100, mobile: 390 }
const CHOICE_TYPES = new Set(["select", "radio", "checkbox"])
const CARD = "[data-public-form-builder-target~='field']"
const HEX = /^#[0-9a-f]{6}$/i
const FIELD_INPUTS = {
  type: "[name$='[field_type]']",
  label: "[name$='[label]']",
  placeholder: "[name$='[placeholder]']",
  hint: "[name$='[hint]']",
  required: "input[type='checkbox'][name$='[required]']",
  options: "[name$='[options_text]']",
  kind: "[data-file-setting='kind']",
  max_mb: "[data-file-setting='max_mb']",
  multiple: "[data-file-setting='multiple']",
  width: "[name$='[config][width]']",
  mask: "[name$='[config][mask]']"
}
const MASKABLE_TYPES = new Set(["text", "tel", "number", "currency"])
// Elementos do modal de onde sai a cor atual quando ainda vale o padrão do tema.
const COLOR_SOURCES = {
  aside: ".public-form-modal__aside",
  title: ".public-form-modal__aside h2",
  body: ".public-form-modal__body",
  submit: ".public-form-modal__submit"
}
const BOX_REGIONS = new Set(["aside", "body"])
const PANEL_TITLES = { benefits: "Benefícios", output: "Saída dos dados" }

export default class extends Controller {
  static targets = [
    "frame", "stage", "status", "device", "inspector", "inspectorTitle", "choiceRow", "fileRow",
    "tools", "saveStatus", "layoutButton", "sizeButton", "statusButton", "saveButton", "saveExitButton", "panel", "fullscreenButton", "maskRow"
  ]
  // Status já salvo: "new" (ainda não criado), draft, published ou inactive. Só new/draft salvam sozinhos.
  static values = { url: String, savedStatus: String }

  connect() {
    this.device = "desktop"
    this.scale = 1
    this.selectedKey = null
    this.dragKey = null
    this.editing = null
    this.toolsFor = null
    this.dirty = false
    this.saving = false
    this.observer = new ResizeObserver(() => this.fit())
    this.observer.observe(this.stageTarget)
    this.fake = false
    this.onFullscreenChange = () => this.applyFullscreen()
    document.addEventListener("fullscreenchange", this.onFullscreenChange)
    this.onDocMouseDown = (event) => {
      if (this.pinned && !this.toolsTarget.contains(event.target)) this.releaseTools()
    }
    document.addEventListener("mousedown", this.onDocMouseDown)
    this.onFrameLoad = () => this.bindFrame()
    this.frameTarget.addEventListener("load", this.onFrameLoad)
    this.syncQuick()
    this.render()
  }

  disconnect() {
    document.removeEventListener("fullscreenchange", this.onFullscreenChange)
    document.removeEventListener("mousedown", this.onDocMouseDown)
    if (this.isFullscreen()) this.leaveFullscreen()
    clearTimeout(this.timer)
    clearTimeout(this.saveTimer)
    clearTimeout(this.hideTimer)
    clearTimeout(this.switchTimer)
    this.abort?.abort()
    this.observer?.disconnect()
    this.frameTarget.removeEventListener("load", this.onFrameLoad)
  }

  // ---- Render do preview ----

  schedule() {
    this.dirty = true
    this.syncQuick()
    if (this.editing || this.dragKey || this.pinned) {
      this.pendingRender = true
      return
    }

    clearTimeout(this.timer)
    this.setRenderStatus("Atualizando…")
    this.timer = setTimeout(() => this.render(), 350)
  }

  async render() {
    // Trocar o documento do iframe no meio de uma edição, arrasto ou seleção de cor perderia o que está em andamento.
    if (this.editing || this.dragKey || this.pinned) {
      this.pendingRender = true
      return
    }

    this.abort?.abort()
    this.abort = new AbortController()

    const body = new FormData(this.element)
    body.delete("_method")

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": this.csrfToken(), Accept: "text/html" },
        credentials: "same-origin",
        body,
        signal: this.abort.signal
      })
      if (!response.ok) throw new Error(response.status)

      this.frameTarget.srcdoc = await response.text()
      this.setRenderStatus("Atualizado")
    } catch (error) {
      if (error.name !== "AbortError") this.setRenderStatus("Não foi possível atualizar")
    }
  }

  switchDevice(event) {
    this.device = event.currentTarget.dataset.device
    this.deviceTargets.forEach((button) => button.setAttribute("aria-pressed", button === event.currentTarget))
    this.fit()
  }

  fit() {
    // Desktop: tela virtual de no mínimo 1100 px, mas acompanha o palco quando ele é mais largo (editor em tela cheia),
    // para o modal "Tela cheia" ocupar toda a largura e os demais tamanhos aparecerem como numa tela desse tamanho.
    const width = this.device === "desktop" ? Math.max(WIDTHS.desktop, this.stageTarget.clientWidth) : WIDTHS[this.device]
    this.scale = Math.min(1, this.stageTarget.clientWidth / width)
    const frame = this.frameTarget.style

    frame.width = `${width}px`
    frame.height = `${this.stageTarget.clientHeight / this.scale}px`
    frame.transform = `scale(${this.scale})`
    frame.left = `${(this.stageTarget.clientWidth - width * this.scale) / 2}px`
  }

  // Tela cheia do editor: usa a tela cheia nativa do navegador no painel inteiro (barra de botões, preview
  // e ferramentas). A nativa escapa dos contêineres do layout do admin; a cobertura fixa (`fake`) é só reserva.
  toggleFullscreen() {
    if (this.isFullscreen()) this.leaveFullscreen()
    else this.enterFullscreen()
  }

  isFullscreen() {
    return this.fake || document.fullscreenElement === this.panelTarget
  }

  async enterFullscreen() {
    if (this.panelTarget.requestFullscreen) {
      try {
        await this.panelTarget.requestFullscreen()
        return
      } catch (_error) {
        // sem permissão/suporte: cai na cobertura simples
      }
    }

    this.fake = true
    this.applyFullscreen()
  }

  leaveFullscreen() {
    if (document.fullscreenElement === this.panelTarget) {
      document.exitFullscreen()
    } else {
      this.fake = false
      this.applyFullscreen()
    }
  }

  // Esc na tela cheia nativa é tratado pelo navegador; aqui só a cobertura de reserva.
  escape(event) {
    if (event.key === "Escape" && this.fake && !this.editing) this.leaveFullscreen()
  }

  applyFullscreen() {
    const on = this.isFullscreen()
    if (!this.hasPanelTarget) return

    this.panelTarget.classList.toggle("is-fullscreen", !!this.fake)
    document.documentElement.classList.toggle("public-form-preview-locked", !!this.fake)

    if (this.hasFullscreenButtonTarget) {
      const button = this.fullscreenButtonTarget
      button.setAttribute("aria-pressed", on)
      button.querySelector("i").className = `bi ${on ? "bi-arrows-angle-contract" : "bi-arrows-angle-expand"}`
      button.querySelector("span").textContent = on ? "Recolher" : "Expandir"
    }
    this.hideTools(true)
    this.fit()
  }

  setRenderStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  // ---- Modelo e tamanho (barra do preview) ----

  syncQuick() {
    const checked = (name) => this.element.querySelector(`input[type='radio'][name='${name}']:checked`)?.value
    const layout = checked("public_form[modal_layout]")
    this.layoutButtonTargets.forEach((button) => button.setAttribute("aria-pressed", button.dataset.value === layout))

    const size = checked("public_form[modal_size]")
    this.sizeButtonTargets.forEach((button) => button.setAttribute("aria-pressed", button.dataset.value === size))

    this.syncStatus(checked("public_form[status]"))
  }

  // Status escolhido (ainda não salvo): realça o botão e diz o que "Salvar" faz.
  syncStatus(status) {
    this.statusButtonTargets.forEach((button) => button.setAttribute("aria-pressed", button.dataset.status === status))

    // Dois botões: só salvar/publicar (fica no editor) e salvar/publicar e sair.
    const labels = { published: ["Publicar", "Publicar e sair"], draft: ["Salvar", "Salvar e sair"], inactive: ["Salvar", "Salvar e sair"] }
    const [stay, leave] = labels[status] || labels.draft
    const stayLabel = this.hasSaveButtonTarget && this.saveButtonTarget.querySelector("span")
    const leaveLabel = this.hasSaveExitButtonTarget && this.saveExitButtonTarget.querySelector("span")
    if (stayLabel) stayLabel.textContent = stay
    if (leaveLabel) leaveLabel.textContent = leave

    this.refreshSaveHint()
  }

  setStatus(event) {
    const radio = this.element.querySelector(`input[type='radio'][name='public_form[status]'][value='${event.currentTarget.dataset.status}']`)
    if (!radio) return

    radio.checked = true
    radio.dispatchEvent(new Event("change", { bubbles: true }))
  }

  statusChanged() {
    this.syncQuick()
  }

  // Por que o autosave não está salvando agora (ou null se pode salvar).
  autosaveBlock() {
    if (this.savedStatusValue !== "new" && this.savedStatusValue !== "draft") {
      return "Só rascunhos salvam sozinhos. Clique em “Salvar” para aplicar."
    }
    if (this.savedStatusValue === "new") {
      const value = (name) => this.element.querySelector(`[name='public_form[${name}]']`)?.value.trim()
      if (!value("name") || !value("title")) return "Preencha nome e título para começar a salvar sozinho."
    }
    return null
  }

  // Aviso neutro (não é erro) enquanto o autosave está pausado; some quando volta a poder salvar.
  refreshSaveHint() {
    if (!this.hasSaveStatusTarget || this.saving) return

    const state = this.saveStatusTarget.dataset.state
    const block = this.autosaveBlock()
    if (block) this.setSaveStatus(block, "idle")
    else if (state === "idle" || !state) this.setSaveStatus("Rascunho: salva sozinho ao sair de cada edição", "idle")
  }

  setRadio(event) {
    const source = event.currentTarget
    const value = source.dataset.value || source.value
    const radio = this.element.querySelector(`input[type='radio'][name='${source.dataset.radioName}'][value='${value}']`)
    if (!radio) return

    radio.checked = true
    radio.dispatchEvent(new Event("change", { bubbles: true }))
    this.syncQuick()
    this.commit()
  }

  // ---- Documento do iframe ----

  get frameDoc() {
    return this.frameTarget.contentDocument
  }

  get builder() {
    return this.application.getControllerForElementAndIdentifier(this.element, "public-form-builder")
  }

  bindFrame() {
    const doc = this.frameDoc
    if (!doc?.body) return

    this.relinkTools()
    doc.querySelectorAll("[data-preview-field]").forEach((field) => { field.draggable = true })
    doc.addEventListener("mousedown", () => this.releaseTools())
    doc.addEventListener("click", (event) => this.frameClick(event))
    doc.addEventListener("mouseover", (event) => this.frameHover(event))
    doc.addEventListener("mousemove", (event) => this.frameHover(event))
    doc.documentElement.addEventListener("mouseleave", () => this.leaveTools())
    doc.addEventListener("scroll", () => this.hideTools(true, "scroll"), true)
    doc.addEventListener("dragstart", (event) => this.dragStart(event))
    doc.addEventListener("dragover", (event) => this.dragOver(event))
    doc.addEventListener("drop", (event) => this.drop(event))
    doc.addEventListener("dragend", () => this.dragEnd())
    this.highlightSelected()
  }

  frameClick(event) {
    if (event.target.closest("a")) event.preventDefault()
    // Clique dentro do texto em edição só posiciona o cursor.
    if (this.editing?.textEl.contains(event.target)) return

    if (event.target.closest("[data-preview-add]")) {
      event.preventDefault()
      this.openPicker()
      return
    }

    const region = event.target.closest("[data-edit]")
    if (region?.dataset.editMode) {
      event.preventDefault()
      this.beginEdit(region)
      return
    }
    if (region && PANEL_TITLES[region.dataset.edit]) {
      event.preventDefault()
      this.openPanel(region.dataset.edit)
      return
    }

    const field = event.target.closest("[data-preview-field]")
    if (!field) return

    event.preventDefault()
    this.selectField(field.dataset.previewField)
  }

  // ---- Ferramentas flutuantes (hover) ----

  // O ponteiro é rastreado em coordenadas do palco. A decisão de manter a ferramenta atual é GEOMÉTRICA (ponteiro
  // sobre a região dela ou na faixa ao redor da ferramenta), então não depende da ordem de mouseenter/mouseleave
  // entre o preview (iframe) e a ferramenta (na página), que não é garantida.
  frameHover(event) {
    if (this.editing || this.dragKey || this.pinned) return

    this.pointer = this.stagePoint(event.clientX, event.clientY, true)
    const target = event.target.closest?.("[data-edit], [data-preview-field]")

    if (this.toolsVisible() && (target === this.toolsFor || this.pointerInToolsHull())) {
      clearTimeout(this.hideTimer)
      clearTimeout(this.switchTimer)
      return
    }

    if (!target) {
      this.leaveTools()
      return
    }
    this.showTools(target)
  }

  toolsVisible() {
    return !this.toolsTarget.hidden && !!this.toolsFor
  }

  // Ponto do ponteiro em coordenadas do palco (o iframe é escalado e deslocado dentro dele).
  stagePoint(clientX, clientY, inFrame) {
    const stage = this.stageTarget.getBoundingClientRect()
    if (!inFrame) return { x: clientX - stage.left, y: clientY - stage.top }

    const frame = this.frameTarget.getBoundingClientRect()
    return { x: frame.left - stage.left + clientX * this.scale, y: frame.top - stage.top + clientY * this.scale }
  }

  // Ferramenta + 12px ao redor (cobre o vão e a sobreposição com o elemento).
  pointerInToolsHull() {
    if (!this.pointer || this.toolsTarget.hidden) return false

    const stage = this.stageTarget.getBoundingClientRect()
    const tools = this.toolsTarget.getBoundingClientRect()
    const margin = 12
    return this.pointer.x >= tools.left - stage.left - margin && this.pointer.x <= tools.right - stage.left + margin &&
      this.pointer.y >= tools.top - stage.top - margin && this.pointer.y <= tools.bottom - stage.top + margin
  }

  // Após atualizar o preview, a ferramenta aberta continua se o ponteiro ainda está nela: religa ao elemento novo.
  relinkTools() {
    const key = this.toolsKey
    if (!key || !this.toolsVisible() || !this.pointerInToolsHull()) {
      this.hideTools(true, "render")
      return
    }

    const doc = this.frameDoc
    const el = key.field != null ? doc.querySelector(`[data-preview-field="${key.field}"]`) : doc.querySelector(`[data-edit="${key.edit}"]`)
    if (!el) {
      this.hideTools(true, "render-sem-elemento")
      return
    }

    this.toolsFor = el
    this.fillTools()
    this.positionTools(el)
  }

  // Diagnóstico: localStorage.setItem("pfPreviewDebug", "1") e recarregar mostra por que a ferramenta sumiu/trocou.
  debug(...args) {
    if (window.localStorage?.getItem("pfPreviewDebug")) console.debug("[preview]", ...args)
  }

  // Com uma ferramenta aberta, passar por outra região no caminho até ela não a troca na hora:
  // a troca espera um instante e é cancelada se o mouse chegar na ferramenta (keepTools).
  showTools(el) {
    clearTimeout(this.hideTimer)
    if (this.toolsFor === el && !this.toolsTarget.hidden) {
      clearTimeout(this.switchTimer)
      return
    }

    if (this.toolsFor && !this.toolsTarget.hidden) {
      clearTimeout(this.switchTimer)
      this.switchTimer = setTimeout(() => { if (!this.pinned && !this.pointerInToolsHull()) this.openTools(el) }, 280)
      return
    }

    this.openTools(el)
  }

  openTools(el) {
    const kind = el.dataset.edit || "field"
    const template = this.element.querySelector(`template[data-tool='${kind}']`)
    if (!template) {
      this.hideTools(true)
      return
    }

    this.toolsFor = el
    this.toolsKey = { edit: el.dataset.edit, field: el.dataset.previewField ?? null }
    this.debug("abre", kind)
    this.renderTools(template, el)
  }

  renderTools(template, el) {
    const tools = this.toolsTarget
    tools.replaceChildren(template.content.cloneNode(true))
    // Cores do texto só fazem sentido na lateral; no modelo Básico o texto é do tema.
    if (!el.closest(".public-form-modal__aside")) tools.querySelectorAll("[data-aside-only]").forEach((node) => node.remove())
    this.fillTools()
    tools.hidden = false
    this.positionTools(el)
  }

  // Cor salva no formulário; senão a cor que o tema está aplicando agora.
  fillTools() {
    this.toolsTarget.querySelectorAll("input[type='color'][data-color]").forEach((input) => {
      const saved = this.element.querySelector(`[name='public_form[modal_config][${input.dataset.color}]']`)?.value.trim()
      input.value = HEX.test(saved) ? saved : this.defaultColor(input.dataset.defaultFrom)
    })
  }

  defaultColor(spec) {
    const [name, property] = (spec || "").split("|")
    const element = this.frameDoc.querySelector(COLOR_SOURCES[name])
    if (!element) return "#000000"

    const match = this.frameTarget.contentWindow.getComputedStyle(element)[property].match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/)
    if (!match || (match[4] !== undefined && parseFloat(match[4]) === 0)) return "#ffffff"

    return `#${[1, 2, 3].map((index) => Number(match[index]).toString(16).padStart(2, "0")).join("")}`
  }

  // Coordenadas do iframe (escalado) para o palco: acima da região, à direita; caixas grandes, no canto superior esquerdo.
  positionTools(el) {
    const rect = el.getBoundingClientRect()
    const left = parseFloat(this.frameTarget.style.left) || 0
    const tools = this.toolsTarget
    const box = BOX_REGIONS.has(el.dataset.edit)

    let x = box ? left + rect.left * this.scale + 10 : left + rect.right * this.scale - tools.offsetWidth
    // Sobrepõe 8px da borda do elemento: sem vão entre ele e a ferramenta para o hover não se perder.
    let y = box ? rect.top * this.scale + 10 : rect.top * this.scale - tools.offsetHeight + 8
    if (y < 4) y = rect.top * this.scale + 6

    x = Math.max(4, Math.min(x, this.stageTarget.clientWidth - tools.offsetWidth - 4))
    y = Math.max(4, Math.min(y, this.stageTarget.clientHeight - tools.offsetHeight - 4))
    tools.style.left = `${x}px`
    tools.style.top = `${y}px`
  }

  hideTools(immediate = false, reason = "") {
    clearTimeout(this.hideTimer)
    clearTimeout(this.switchTimer)
    if (!immediate) return
    this.debug("esconde", reason || "ação")
    this.pinned = false
    this.overTools = false
    clearTimeout(this.unpinTimer)
    this.toolsFor = null
    this.toolsTarget.hidden = true
  }

  leaveTools() {
    clearTimeout(this.hideTimer)
    clearTimeout(this.switchTimer)
    if (this.editing || this.pinned || this.overTools || this.pointerInToolsHull()) return

    this.hideTimer = setTimeout(() => {
      if (!this.pinned && !this.overTools && !this.pointerInToolsHull()) this.hideTools(true, "saiu")
    }, 350)
  }

  // Ponteiro saiu do palco inteiro (preview + ferramenta): esquece a última posição e agenda o sumiço.
  stageLeave() {
    this.pointer = null
    this.leaveTools()
  }

  // Movimento sobre a própria ferramenta (página): mantém o ponteiro em coordenadas do palco.
  toolsMove(event) {
    this.overTools = true
    this.pointer = this.stagePoint(event.clientX, event.clientY, false)
    clearTimeout(this.hideTimer)
    clearTimeout(this.switchTimer)
  }

  keepTools() {
    this.overTools = true
    clearTimeout(this.hideTimer)
    clearTimeout(this.switchTimer)
  }

  toolsLeave() {
    this.overTools = false
    this.leaveTools()
  }

  // Seletor de cor aberto: o mouse sai da página e o preview não pode ser trocado, senão a ferramenta (dona
  // do seletor) some e o seletor fecha. Fica fixa até o seletor fechar (change) ou um clique em outro lugar.
  pinTools(event) {
    if (!event.target.matches?.("input[type='color']")) return

    this.pinned = true
    clearTimeout(this.hideTimer)
    clearTimeout(this.switchTimer)
    clearTimeout(this.unpinTimer)
  }

  unpinTools() {
    clearTimeout(this.unpinTimer)
    this.unpinTimer = setTimeout(() => this.releaseTools(), 250)
  }

  releaseTools() {
    clearTimeout(this.unpinTimer)
    if (!this.pinned) return

    this.pinned = false
    if (this.pendingRender) {
      this.pendingRender = false
      this.render()
    }
    if (!this.overTools) this.leaveTools()
  }

  // Botões da ferramenta não podem roubar a seleção do texto em edição.
  toolMouseDown(event) {
    if (event.target.closest("[data-exec], [data-tool-action]")) event.preventDefault()
  }

  toolClick(event) {
    const exec = event.target.closest("[data-exec]")
    if (exec) {
      this.frameDoc.execCommand(exec.dataset.exec)
      this.editInput()
      return
    }

    const button = event.target.closest("[data-tool-action]")
    const el = this.toolsFor
    if (!button || !el) return

    switch (button.dataset.toolAction) {
      case "edit": this.beginEdit(el); break
      case "panel": this.openPanel(button.dataset.panel); break
      case "field-edit": this.selectField(el.dataset.previewField); break
      case "width": this.toggleWidth(el); break
      case "duplicate": this.selectedKey = el.dataset.previewField; this.duplicateField(); break
      case "remove": this.selectedKey = el.dataset.previewField; this.removeField(); break
    }
  }

  // Cor: aplica na hora no preview (variável CSS) e grava no campo do formulário; salva ao soltar o seletor.
  toolInput(event) {
    const input = event.target.closest("input[type='color'][data-color]")
    if (!input) return

    const field = this.element.querySelector(`[name='public_form[modal_config][${input.dataset.color}]']`)
    if (field) {
      field.value = input.value
      field.dispatchEvent(new Event("input", { bubbles: true }))
    }
    this.frameDoc?.querySelector(".public-form-modal__dialog")?.style.setProperty(input.dataset.live, input.value)
  }

  toolChange(event) {
    if (!event.target.closest("input[type='color'][data-color]")) return

    this.commit()
    this.unpinTools()
  }

  // ---- Edição de texto no lugar ----

  beginEdit(el) {
    const textEl = el.dataset.editText ? el.querySelector(el.dataset.editText) : el
    if (!textEl) return

    this.hideTools(true)
    const rich = el.dataset.editMode === "rich"
    const bound = rich ? this.element.querySelector("#public_form_subtitle") : this.element.querySelector(`[name="${el.dataset.bind}"]`)
    this.editing = { el, textEl, rich, original: rich ? textEl.innerHTML : textEl.textContent, initial: bound?.value }

    try {
      textEl.contentEditable = rich ? "true" : "plaintext-only"
    } catch (_error) {
      textEl.contentEditable = "true"
    }
    textEl.classList.add("is-editing")
    textEl.focus()

    const selection = this.frameTarget.contentWindow.getSelection()
    const range = this.frameDoc.createRange()
    range.selectNodeContents(textEl)
    selection.removeAllRanges()
    selection.addRange(range)

    this.editHandlers = {
      input: () => this.editInput(),
      blur: () => this.endEdit(),
      keydown: (event) => this.editKey(event)
    }
    Object.entries(this.editHandlers).forEach(([type, handler]) => textEl.addEventListener(type, handler))

    if (rich) {
      const template = this.element.querySelector("template[data-tool='format']")
      if (template) {
        this.toolsFor = el
        this.renderTools(template, el)
      }
    }
  }

  editInput() {
    if (!this.editing) return

    const { el, textEl, rich } = this.editing
    if (rich) this.writeRich(textEl.innerHTML)
    else this.writeBound(el.dataset.bind, textEl.textContent.replace(/\s+/g, " ").trim())
  }

  editKey(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.editing.cancelled = true
      this.editing.textEl.blur()
    } else if (event.key === "Enter" && !this.editing.rich) {
      event.preventDefault()
      this.editing.textEl.blur()
    }
  }

  endEdit() {
    const editing = this.editing
    if (!editing) return

    const { el, textEl, rich, original, initial, cancelled } = editing
    Object.entries(this.editHandlers).forEach(([type, handler]) => textEl.removeEventListener(type, handler))
    textEl.removeAttribute("contenteditable")
    textEl.classList.remove("is-editing")

    if (cancelled) {
      if (rich) textEl.innerHTML = original
      else textEl.textContent = original
      if (initial !== undefined) rich ? this.writeRich(initial) : this.writeBound(el.dataset.bind, initial)
    }

    const changed = !cancelled && (rich ? textEl.innerHTML : textEl.textContent) !== original
    this.editing = null
    this.hideTools(true)

    if (this.pendingRender) {
      this.pendingRender = false
      this.render()
    }
    if (changed) this.commit()
  }

  writeBound(name, value) {
    const input = this.element.querySelector(`[name="${name}"]`)
    if (!input) return

    input.value = value
    input.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // O texto principal mora no Trix do bloco 1: carrega o HTML nele (ele atualiza o input oculto).
  writeRich(html) {
    const trix = this.element.querySelector("trix-editor")
    if (trix?.editor) {
      trix.editor.loadHTML(html)
      return
    }

    const hidden = this.element.querySelector("#public_form_subtitle")
    if (!hidden) return

    hidden.value = html
    hidden.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // ---- Arrastar para reordenar ----

  dragStart(event) {
    const field = event.target.closest?.("[data-preview-field]")
    if (!field) return

    this.hideTools(true)
    this.dragKey = field.dataset.previewField
    field.classList.add("is-dragging")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.dragKey)
  }

  dragOver(event) {
    if (!this.dragKey) return

    this.clearDropMarks()
    const drop = this.resolveDrop(event)
    if (!drop) return

    event.preventDefault()
    const marker = drop.side ? (drop.before ? "is-drop-side-before" : "is-drop-side-after") : (drop.before ? "is-drop-above" : "is-drop-below")
    drop.target.classList.add(marker)
  }

  // Onde o campo arrastado vai cair, em duas intenções:
  //   side: true  -> na mesma linha do alvo, ao lado dele (o campo passa a meia largura);
  //   side: false -> numa linha própria, acima ou abaixo do alvo.
  // Sobre um campo de meia largura: o meio divide a linha (esquerda/direita); a borda de cima/baixo cria linha nova.
  // Espaço vazio ao lado de um campo de meia largura (ex.: metade direita do telefone) conta como "ao lado dele".
  resolveDrop(event) {
    const fields = Array.from(this.frameDoc.querySelectorAll("[data-preview-field]")).filter((field) => field.dataset.previewField !== this.dragKey)
    if (!fields.length) return null

    const { clientX: x, clientY: y } = event
    const grid = fields[0].parentElement.getBoundingClientRect()
    if (x < grid.left - 12 || x > grid.right + 12 || y < grid.top - 12 || y > grid.bottom + 12) return null

    const rectOf = (field) => field.getBoundingClientRect()
    const isFull = (field) => field.classList.contains("public-form-modal__field--w-full")
    const gapX = (field) => { const r = rectOf(field); return x < r.left ? r.left - x : (x > r.right ? x - r.right : 0) }
    const gapY = (field) => { const r = rectOf(field); return y < r.top ? r.top - y : (y > r.bottom ? y - r.bottom : 0) }

    const over = fields.find((field) => gapX(field) === 0 && gapY(field) === 0)
    if (over) {
      const r = rectOf(over)
      if (isFull(over)) return { target: over, before: y < r.top + r.height / 2, side: false }

      const edge = r.height * 0.25
      if (y < r.top + edge) return { target: over, before: true, side: false }
      if (y > r.bottom - edge) return { target: over, before: false, side: false }
      return { target: over, before: x < r.left + r.width / 2, side: true }
    }

    const sameRow = fields.filter((field) => gapY(field) === 0 && !isFull(field))
    if (sameRow.length) {
      const nearest = sameRow.reduce((best, field) => (gapX(field) < gapX(best) ? field : best))
      return { target: nearest, before: x < rectOf(nearest).left, side: true }
    }

    const nearest = fields.reduce((best, field) => (gapY(field) < gapY(best) ? field : best))
    const r = rectOf(nearest)
    return { target: nearest, before: y < r.top + r.height / 2, side: false }
  }

  drop(event) {
    const placement = this.dragKey && this.resolveDrop(event)
    if (!placement) return this.dragEnd()

    event.preventDefault()
    const { target, before, side } = placement
    const key = this.dragKey
    const dragged = this.frameDoc.querySelector(`[data-preview-field="${key}"]`)

    this.moveCard(key, target.dataset.previewField, before)
    this.adjustWidthAfterDrop(key, dragged, side)
    // O preview acompanha na hora; o render seguinte confirma a ordem vinda do builder.
    if (dragged) target.parentElement.insertBefore(dragged, before ? target : target.nextElementSibling)
    this.dragEnd()
    this.commit()
  }

  // Ao lado de outro campo vira meia largura (é isso que o deixa na mesma linha); numa linha própria,
  // um "meia" vindo de encaixe lateral volta ao automático (o checkbox, por exemplo, volta a ocupar a linha).
  adjustWidthAfterDrop(key, dragged, side) {
    const select = this.cardFor(key)?.querySelector(FIELD_INPUTS.width)
    if (!select) return

    const next = side ? "half" : (select.value === "half" ? "auto" : select.value)
    if (select.value === next) return

    select.value = next
    select.dispatchEvent(new Event("change", { bubbles: true }))
    if (!dragged) return

    const fullByType = ["textarea", "radio", "checkbox", "file"].some((type) => dragged.classList.contains(`public-form-modal__field--${type}`))
    const full = next === "full" || (next === "auto" && fullByType)
    dragged.classList.toggle("public-form-modal__field--w-full", full)
    dragged.classList.toggle("public-form-modal__field--w-half", !full)
  }

  dragEnd() {
    this.clearDropMarks()
    this.frameDoc?.querySelectorAll(".is-dragging").forEach((field) => field.classList.remove("is-dragging"))
    this.dragKey = null
    if (this.pendingRender) {
      this.pendingRender = false
      this.schedule()
    }
  }

  clearDropMarks() {
    this.frameDoc?.querySelectorAll("[class*='is-drop-']").forEach((field) => field.classList.remove("is-drop-side-before", "is-drop-side-after", "is-drop-above", "is-drop-below"))
  }

  moveCard(key, targetKey, before) {
    const card = this.cardFor(key)
    const target = this.cardFor(targetKey)
    if (!card || !target) return

    target.parentElement.insertBefore(card, before ? target : target.nextElementSibling)
    this.builder?.refresh()
  }

  // ---- Mini builder (inspetor): tipo/campo, benefícios, saída dos dados ----

  showMode(name) {
    this.inspectorTarget.hidden = false
    this.inspectorTarget.querySelectorAll("[data-mode]").forEach((node) => { node.hidden = node.dataset.mode !== name })
  }

  openPicker() {
    this.hideTools(true)
    this.selectedKey = null
    this.highlightSelected()
    this.inspectorTitleTarget.textContent = "Novo campo"
    this.showMode("picker")
  }

  openPanel(name) {
    this.hideTools(true)
    this.selectedKey = null
    this.highlightSelected()
    this.inspectorTitleTarget.textContent = PANEL_TITLES[name]
    this.showMode(name)

    this.inspectorTarget.querySelectorAll(`[data-mode='${name}'] [data-bind]`).forEach((input) => {
      const source = this.element.querySelector(`[name="${input.dataset.bind}"]`)
      if (source && input.value !== source.value) input.value = source.value
    })
  }

  closeInspector() {
    this.selectedKey = null
    this.highlightSelected()
    this.inspectorTarget.hidden = true
    this.commit()
  }

  // Cria o campo no builder real (sem mover o foco da página) e abre o editor dele.
  addField(event) {
    const builder = this.builder
    if (!builder) return

    const card = builder.buildField(event.currentTarget.dataset.fieldType || "text")
    builder.listTarget.appendChild(card)
    builder.refresh()
    this.selectField(this.keyOf(card))
  }

  selectField(key) {
    const card = this.cardFor(key)
    if (!card) return

    this.hideTools(true)
    this.selectedKey = key
    this.fillEditor(card)
    this.showMode("editor")
    this.highlightSelected()
  }

  fillEditor(card) {
    this.inspectorTarget.querySelectorAll("[data-mode='editor'] [data-proxy]").forEach((input) => {
      const source = card.querySelector(FIELD_INPUTS[input.dataset.proxy])
      if (!source) return

      if (input.type === "checkbox") input.checked = source.checked
      else if (input.value !== source.value) input.value = source.value
    })

    const type = this.inspectorTarget.querySelector("[data-proxy='type']").value
    this.choiceRowTarget.hidden = !CHOICE_TYPES.has(type)
    this.fileRowTarget.hidden = type !== "file"
    this.maskRowTarget.hidden = !MASKABLE_TYPES.has(type)
    this.inspectorTitleTarget.textContent = card.querySelector(FIELD_INPUTS.label)?.value.trim() || "Novo campo"
  }

  // Edita o input do formulário e dispara o mesmo evento de uma edição manual.
  proxyInput(event) {
    const bound = event.target.closest("[data-bind]")
    if (bound) {
      if (event.type === "input" && bound.tagName === "SELECT") return

      const source = this.element.querySelector(`[name="${bound.dataset.bind}"]`)
      if (!source) return

      source.value = bound.value
      source.dispatchEvent(new Event(bound.tagName === "SELECT" ? "change" : "input", { bubbles: true }))
      return
    }

    const input = event.target.closest("[data-proxy]")
    const card = this.cardFor(this.selectedKey)
    if (!input || !card) return

    const isChoice = input.tagName === "SELECT" || input.type === "checkbox"
    if (event.type === "input" && isChoice) return

    const source = card.querySelector(FIELD_INPUTS[input.dataset.proxy])
    if (!source) return

    if (input.type === "checkbox") source.checked = input.checked
    else source.value = input.value
    source.dispatchEvent(new Event(isChoice ? "change" : "input", { bubbles: true }))

    // Trocar o tipo ajusta padrões no builder (opções, placeholder): reflete no editor.
    if (input.dataset.proxy === "type" || input.dataset.proxy === "label") this.fillEditor(card)
  }

  // Alterna o campo entre meia coluna e linha inteira (a partir de como está aparecendo no modal).
  toggleWidth(el) {
    const select = this.cardFor(el.dataset.previewField)?.querySelector(FIELD_INPUTS.width)
    if (!select) return

    select.value = el.classList.contains("public-form-modal__field--w-full") ? "half" : "full"
    select.dispatchEvent(new Event("change", { bubbles: true }))
    this.commit()
  }

  // Atalho de formato no mini editor: preenche a máscara (o "input" sobe pelo proxy para o card do builder).
  maskPreset(event) {
    const select = event.currentTarget
    const input = this.inspectorTarget.querySelector("[data-proxy='mask']")
    if (!input || !select.value) return

    input.value = select.value
    select.value = ""
    input.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // Enter num campo do inspetor não pode enviar o formulário inteiro.
  editorKey(event) {
    if (event.key === "Enter" && event.target.tagName !== "TEXTAREA") event.preventDefault()
  }

  duplicateField() {
    const card = this.cardFor(this.selectedKey)
    card?.querySelector("[data-action='public-form-builder#duplicate']")?.click()

    const copy = card?.nextElementSibling
    if (copy) this.selectField(this.keyOf(copy))
  }

  removeField() {
    this.cardFor(this.selectedKey)?.querySelector("[data-action='public-form-builder#remove']")?.click()
    this.closeInspector()
  }

  highlightSelected() {
    const doc = this.frameDoc
    if (!doc) return

    doc.querySelectorAll("[data-preview-field].is-selected").forEach((field) => field.classList.remove("is-selected"))
    if (this.selectedKey === null) return

    doc.querySelector(`[data-preview-field="${this.selectedKey}"]`)?.classList.add("is-selected")
  }

  // ---- Ligação preview <-> card do builder (pela chave de fields_attributes) ----

  cardFor(key) {
    if (key === null || key === undefined) return null

    return this.element
      .querySelector(`[data-public-form-builder-target~='list'] [name^='public_form[fields_attributes][${key}]']`)
      ?.closest(CARD) || null
  }

  keyOf(card) {
    return card?.querySelector("[name*='[fields_attributes]']")?.name.match(/\[fields_attributes\]\[([^\]]+)\]/)?.[1] ?? null
  }

  // ---- Salvar sozinho ao sair de cada edição ----

  commit() {
    if (!this.dirty) return
    if (this.autosaveBlock()) {
      this.refreshSaveHint()
      return
    }

    clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.autosave(), 500)
  }

  async autosave() {
    if (this.autosaveBlock()) {
      this.refreshSaveHint()
      return
    }

    return this.persist()
  }

  // "Salvar" / "Publicar" sem sair: salva em segundo plano com o status escolhido (o autosave só grava rascunho).
  async saveNow() {
    clearTimeout(this.saveTimer)
    await this.persist({ explicit: true })
  }

  async persist({ explicit = false } = {}) {
    if (this.saving) {
      if (!explicit) {
        this.saveAgain = true
        return
      }
      // O salvamento explícito espera o automático em andamento terminar.
      while (this.saving) await new Promise((resolve) => setTimeout(resolve, 80))
    }

    const publishing = this.element.querySelector("input[name='public_form[status]']:checked")?.value === "published"
    this.saving = true
    this.dirty = false
    if (explicit) this.setSaveButtonsDisabled(true)
    this.setSaveStatus(explicit && publishing ? "Publicando…" : "Salvando…", "saving")

    try {
      const body = new FormData(this.element)
      if (explicit) body.append("commit", "1")

      const response = await fetch(this.element.action, {
        method: "POST",
        headers: { "X-CSRF-Token": this.csrfToken(), Accept: "application/json" },
        credentials: "same-origin",
        body
      })
      const data = await response.json().catch(() => ({}))
      if (!response.ok || data.ok === false) throw new Error((data.errors || []).join(" · ") || `Erro ${response.status}`)

      this.afterSave(data)
      const time = new Date().toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" })
      this.setSaveStatus(`${explicit && data.status === "published" ? "Publicado" : "Salvo"} às ${time}`, "saved")
    } catch (error) {
      this.dirty = true
      this.setSaveStatus(`Não salvou: ${error.message}`, "error")
    } finally {
      this.saving = false
      if (explicit) this.setSaveButtonsDisabled(false)
      if (this.saveAgain) {
        this.saveAgain = false
        this.autosave()
      }
    }
  }

  setSaveButtonsDisabled(disabled) {
    [this.saveButtonTargets, this.saveExitButtonTargets].flat().forEach((button) => { button.disabled = disabled })
  }

  // Formulário novo vira edição (próximo salvamento atualiza); campos novos ganham id; removidos saem da lista.
  afterSave(data) {
    const cards = this.element.querySelectorAll("[data-public-form-builder-target~='list'] > [data-public-form-builder-target~='field']")
    cards.forEach((card) => {
      if (card.hidden) {
        card.remove()
        return
      }
      if (card.querySelector("input[name$='[id]']")) return

      const position = card.querySelector("[data-public-form-builder-target~='positionInput']")?.value
      const id = data.fields?.[position]
      const prefix = card.querySelector("[name*='[fields_attributes]']")?.name.match(/^(public_form\[fields_attributes\]\[[^\]]+\])/)?.[1]
      if (!id || !prefix) return

      const hidden = document.createElement("input")
      hidden.type = "hidden"
      hidden.name = `${prefix}[id]`
      hidden.value = id
      card.prepend(hidden)
    })

    if (!this.element.querySelector("input[name='_method']")) {
      const method = document.createElement("input")
      method.type = "hidden"
      method.name = "_method"
      method.value = "patch"
      this.element.prepend(method)
    }
    this.element.action = data.update_url
    window.history.replaceState(null, "", data.edit_url)
    this.savedStatusValue = data.status || "draft"
    this.application.getControllerForElementAndIdentifier(this.element, "public-form-setup")?.lockSlug()
  }

  setSaveStatus(text, state) {
    if (!this.hasSaveStatusTarget) return

    this.saveStatusTarget.textContent = text
    this.saveStatusTarget.dataset.state = state
  }
}
