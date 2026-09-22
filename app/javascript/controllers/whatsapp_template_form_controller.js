import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "bodyInput",
    "buttonList",
    "buttonRow",
    "carouselCardList",
    "carouselCardRow",
    "exampleInput",
    "exampleRow",
    "examplesList",
    "flowActionSelect",
    "flowScreenField",
    "headerTextField",
    "mediaSelect",
    "mediaField",
    "mediaRules",
    "nameInput",
    "buttonTemplate",
    "carouselCardTemplate",
    "exampleTemplate"
  ]
  static values = {
    uploadMediaUrl: String,
    type: { type: String, default: "text" }
  }

  connect() {
    this.toggleMedia()
    this.toggleButtonRows()
    this.toggleCarouselButtonRows()
    this.toggleFlowFields()
    this.refreshCarouselIndexes()
    this.syncExamples()
    this.refresh()
    this.openIncompleteCards()
  }

  // Depois de um envio recusado, abre os cards que ficaram incompletos para a pessoa ver o que corrigir.
  openIncompleteCards() {
    if (!this.hasCarouselCardListTarget || !this.element.querySelector(".whatsapp-template-form__feedback")) return

    this.carouselCardRowTargets.forEach((row) => {
      const card = this.cardValues(row)
      if (this.cardStarted(card) && !this.cardComplete(card)) this.setCardCollapsed(row, false)
    })
    this.syncToggleAllCards()
  }

  // Cabeçalho pode ser um select (carousel/flow) ou um grupo de radios (construtor de texto).
  headerFormat() {
    const checked = this.mediaSelectTargets.find((element) => element.checked)
    return (checked || this.mediaSelectTargets[0])?.value
  }

  toggleMedia() {
    if (!this.hasMediaSelectTarget) return

    const value = this.headerFormat()
    const hasMedia = ["image", "video", "document"].includes(value)
    const hasText = value === "text"
    if (this.hasHeaderTextFieldTarget) this.headerTextFieldTarget.hidden = !hasText
    if (this.hasMediaFieldTarget) this.mediaFieldTarget.hidden = !hasMedia
    if (this.hasMediaRulesTarget) this.mediaRulesTarget.hidden = !hasMedia

    const handleInput = this.element.querySelector("input[name='whatsapp_template[header_media_handle]']")
    if (handleInput && !hasMedia) handleInput.value = ""
  }

  toggleFlowFields() {
    if (!this.hasFlowActionSelectTarget || !this.hasFlowScreenFieldTarget) return

    this.flowScreenFieldTarget.hidden = this.flowActionSelectTarget.value !== "navigate"
  }

  syncExamples() {
    const expected = this.expectedExampleCount()
    if (!this.hasExamplesListTarget) return

    while (this.exampleRowTargets.length < expected) this.addExampleRow()
    this.refreshExampleLabels()
    this.refresh()
  }

  addExample(event) {
    event?.preventDefault()
    this.addExampleRow()
    this.refreshExampleLabels()
    this.refresh()
  }

  addButton(event) {
    event?.preventDefault()
    if (!this.hasButtonListTarget || this.buttonRowTargets.length >= 10) return

    this.buttonListTarget.insertAdjacentHTML("beforeend", this.cloneTemplate(this.buttonTemplateTarget, this.buttonRowTargets.length))
    this.refreshButtonIndexes()
    this.toggleButtonRows()
    this.refresh()
  }

  addCarouselCard(event) {
    event?.preventDefault()
    if (!this.hasCarouselCardListTarget || this.carouselCardRowTargets.length >= 10) return

    this.carouselCardListTarget.insertAdjacentHTML("beforeend", this.cloneTemplate(this.carouselCardTemplateTarget, this.carouselCardRowTargets.length))
    this.refreshCarouselIndexes()
    this.toggleCarouselButtonRows()
    this.refresh()
    this.syncToggleAllCards()
  }

  removeCarouselCard(event) {
    event?.preventDefault()
    const row = event.currentTarget.closest("[data-whatsapp-template-form-target='carouselCardRow']")
    if (!row) return

    if (this.carouselCardRowTargets.length <= 2) {
      row.querySelectorAll("input, textarea").forEach((input) => {
        if (input.type !== "hidden") input.value = ""
      })
      row.querySelectorAll("select").forEach((select) => {
        this.setSelectValue(select, select.name.includes("[button_kind]") ? "url" : "image")
      })
      this.toggleCarouselButtonRows()
      this.refresh()
      return
    }

    row.remove()
    this.refreshCarouselIndexes()
    this.toggleCarouselButtonRows()
    this.refresh()
  }

  removeButton(event) {
    event?.preventDefault()
    const row = event.currentTarget.closest("[data-whatsapp-template-form-target='buttonRow']")
    if (!row) return

    if (this.buttonRowTargets.length <= 1) {
      row.querySelectorAll("input").forEach((input) => { input.value = "" })
      this.setSelectValue(row.querySelector("select"), "quick_reply")
      this.toggleButtonRows()
      this.refresh()
      return
    }

    row.remove()
    this.refreshButtonIndexes()
    this.toggleButtonRows()
    this.refresh()
  }

  removeExample(event) {
    event?.preventDefault()
    const row = event.currentTarget.closest("[data-whatsapp-template-form-target='exampleRow']")
    if (!row) return
    if (this.exampleRowTargets.length <= this.minimumExampleRows()) {
      const input = row.querySelector("input")
      if (input) input.value = ""
      return
    }

    row.remove()
    this.refreshExampleLabels()
    this.refresh()
  }

  toggleButtonRows() {
    this.element.querySelectorAll(".whatsapp-template-button-row").forEach((row) => {
      const select = row.querySelector("select")
      const extra = row.querySelector("[data-whatsapp-template-button-extra]")
      if (!select || !extra) return

      row.dataset.kind = select.value

      const needsExtra = ["url", "phone_number"].includes(select.value)
      extra.hidden = !needsExtra
      const input = extra.querySelector("input")
      if (input) {
        const phoneSelected = select.value === "phone_number"
        input.placeholder = phoneSelected ? "+55 00 00000-0000" : "https://exemplo.invalid"
        input.type = phoneSelected ? "tel" : "text"
        input.autocomplete = phoneSelected ? "tel" : "off"
        if (phoneSelected) {
          input.dataset.controller = "phone-input"
        } else if (input.dataset.controller === "phone-input") {
          delete input.dataset.controller
        }
      }
    })
  }

  toggleCarouselButtonRows() {
    this.element.querySelectorAll(".whatsapp-template-carousel-card").forEach((row) => {
      const select = row.querySelector("select[name*='[button_kind]']")
      if (!select) return

      row.querySelectorAll("[data-whatsapp-template-carousel-extra]").forEach((extra) => {
        extra.hidden = extra.dataset.whatsappTemplateCarouselExtra !== select.value
      })
    })
  }

  async updateFileName(event) {
    const input = event.currentTarget
    const control = input.closest(".whatsapp-template-upload-control")
    const status = control?.querySelector("[data-whatsapp-template-file-status]")
    if (!status) return

    const files = Array.from(input.files || [])
    status.textContent = files.length > 0 ? files.map((file) => file.name).join(", ") : "Nenhum arquivo selecionado"
    await this.uploadMediaHandle(input, control, status)
    this.refresh()
  }

  submitStarted() {
    const submitButton = this.element.querySelector("button[type='submit']")
    if (!submitButton) return

    submitButton.disabled = true
    submitButton.innerHTML = '<i class="bi bi-arrow-repeat ax-ico"></i><span>Enviando para a Meta...</span>'
  }

  async uploadMediaHandle(input, control, status) {
    const file = input.files?.[0]
    if (!file || !this.hasUploadMediaUrlValue) return

    const hiddenInput = this.mediaHandleInputFor(input, control)
    if (hiddenInput) hiddenInput.value = ""

    const mediaType = this.mediaTypeFor(input)
    if (!mediaType) return

    const formData = new FormData()
    formData.append("file", file)
    formData.append("media_type", mediaType)

    status.textContent = "Validando mídia na Meta..."

    try {
      const response = await fetch(this.uploadMediaUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.csrfToken(),
          "Accept": "application/json"
        },
        body: formData,
        credentials: "same-origin"
      })
      const data = await response.json().catch(() => ({}))

      if (!response.ok || !data.handle) {
        throw new Error(data.error || "Não foi possível validar a mídia na Meta.")
      }

      const handle = this.normalizeMediaHandle(data.handle)
      if (!handle) throw new Error("A Meta não retornou um handle válido para esta mídia.")

      if (hiddenInput) hiddenInput.value = handle
      status.textContent = `${file.name} · validada na Meta`
    } catch (error) {
      if (hiddenInput) hiddenInput.value = ""
      status.textContent = error.message || "Não foi possível validar a mídia na Meta."
    }
  }

  mediaTypeFor(input) {
    if (input.name.includes("[header_media_file]")) {
      return this.hasMediaSelectTarget ? this.headerFormat() : null
    }

    const card = input.closest("[data-whatsapp-template-form-target='carouselCardRow']")
    return card?.querySelector("select[name*='[media_type]']")?.value || null
  }

  mediaHandleInputFor(input, control) {
    const field = control?.closest(".ax-field")
    if (input.name.includes("[header_media_file]")) {
      return field?.querySelector("input[name='whatsapp_template[header_media_handle]']")
    }

    return field?.querySelector("input[type='hidden'][name*='[media_handle]']")
  }

  normalizeMediaHandle(value) {
    return String(value || "")
      .split(/\r?\n/)
      .map((line) => line.trim())
      .find((line) => line.length > 0) || ""
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  // Linhas novas vêm do mesmo partial do servidor (renderizado num <template>), então usam os mesmos componentes do design system.
  cloneTemplate(template, index) {
    return template.innerHTML.replaceAll("__INDEX__", String(index)).replaceAll("__NUMBER__", String(index + 1))
  }

  // Selects do design system são TomSelect: o valor precisa passar pela instância para a tela acompanhar.
  setSelectValue(select, value) {
    if (select.tomselect) select.tomselect.setValue(value, true)
    else select.value = value
    select.dispatchEvent(new Event("change", { bubbles: true }))
  }

  refreshButtonIndexes() {
    this.buttonRowTargets.forEach((row, index) => {
      row.querySelectorAll("label, input, select").forEach((element) => {
        if (element.htmlFor) element.htmlFor = element.htmlFor.replace(/buttons_\d+_/, `buttons_${index}_`)
        if (element.id) element.id = element.id.replace(/buttons_\d+_/, `buttons_${index}_`)
        if (element.name) element.name = element.name.replace(/buttons\]\[\d+\]/, `buttons][${index}]`)
      })
    })
  }

  refreshCarouselIndexes() {
    if (!this.hasCarouselCardListTarget) return

    this.carouselCardRowTargets.forEach((row, index) => {
      const title = row.querySelector(".whatsapp-template-carousel-card__head strong")
      if (title) title.textContent = `Card ${index + 1}`

      row.querySelectorAll("label, input, textarea, select").forEach((element) => {
        if (element.htmlFor) {
          element.htmlFor = element.htmlFor
            .replace(/carousel_cards_\d+_/, `carousel_cards_${index}_`)
            .replace(/carousel_card_media_files_\d+/, `carousel_card_media_files_${index}`)
        }
        if (element.id) {
          element.id = element.id
            .replace(/carousel_cards_\d+_/, `carousel_cards_${index}_`)
            .replace(/carousel_card_media_files_\d+/, `carousel_card_media_files_${index}`)
        }
        if (element.name) element.name = element.name.replace(/carousel_cards\]\[\d+\]/, `carousel_cards][${index}]`)
      })
    })
  }

  addExampleRow() {
    this.examplesListTarget.insertAdjacentHTML("beforeend", this.cloneTemplate(this.exampleTemplateTarget, this.exampleRowTargets.length))
  }

  refreshExampleLabels() {
    this.exampleRowTargets.forEach((row, index) => {
      const label = row.querySelector("label")
      const input = row.querySelector("input")
      if (label) {
        label.textContent = `Exemplo ${index + 1}`
        label.setAttribute("for", `whatsapp_template_example_values_${index}`)
      }
      if (input) input.id = `whatsapp_template_example_values_${index}`
    })
  }

  expectedExampleCount() {
    if (!this.hasBodyInputTarget) return this.minimumExampleRows()

    const indexes = Array.from(this.bodyInputTarget.value.matchAll(/\{\{(\d+)\}\}/g)).map((match) => Number(match[1]))
    return Math.max(this.minimumExampleRows(), ...indexes.filter((index) => Number.isFinite(index)))
  }

  minimumExampleRows() {
    return 1
  }

  // ---- Construtor guiado de template de texto (pré-visualização, progresso e etapas) ----

  static previewIcons = { quick_reply: "bi-reply", url: "bi-box-arrow-up-right", phone_number: "bi-telephone" }
  static mediaLabels = { image: ["bi-image", "Imagem"], video: ["bi-camera-video", "Vídeo"], document: ["bi-file-earmark-pdf", "Documento"] }
  static categoryTones = { MARKETING: "marketing", UTILITY: "utility", AUTHENTICATION: "authentication" }

  guided(name) { return this.element.querySelector(`[data-guided='${name}']`) }

  field(name) { return this.element.querySelector(`[name='whatsapp_template[${name}]']`) }

  refresh(event) {
    if (!this.guided("bubble")) return

    if (event?.target?.name === "whatsapp_template[category]") this.categoryConfirmed = true

    this.renderPreview()
    this.updateProgress()
  }

  buttonValues() {
    return this.buttonRowTargets.map((row) => {
      const kind = row.querySelector("select")?.value || "quick_reply"
      const text = row.querySelector("input[name$='[text]']")?.value.trim() || ""
      const extra = row.querySelector("[data-whatsapp-template-button-extra] input")?.value.trim() || ""
      return { kind, text, extra }
    }).filter((button) => button.text || button.extra)
  }

  exampleValues() {
    return this.exampleInputTargets.map((input) => input.value.trim())
  }

  variableIndexes() {
    const body = this.hasBodyInputTarget ? this.bodyInputTarget.value : ""
    return [...new Set(Array.from(body.matchAll(/\{\{(\d+)\}\}/g), (match) => Number(match[1])))]
  }

  renderPreview() {
    const body = this.hasBodyInputTarget ? this.bodyInputTarget.value : ""
    const examples = this.exampleValues()
    const format = this.headerFormat()
    const checked = this.element.querySelector("input[name='whatsapp_template[category]']:checked")
    const tag = this.guided("previewCategory")
    if (tag && checked) {
      tag.textContent = checked.dataset.label || checked.value
      tag.dataset.tone = this.constructor.categoryTones[checked.value] || "marketing"
    }

    const media = this.guided("previewMedia")
    if (media) {
      const [mediaIcon, mediaLabel] = this.constructor.mediaLabels[format] || []
      media.hidden = !mediaIcon
      if (mediaIcon) {
        media.querySelector("i").className = `bi ${mediaIcon}`
        media.querySelector("span").textContent = mediaLabel
      }
    }
    const header = this.guided("previewHeader")
    if (header) {
      const headerText = this.field("header_text")?.value.trim() || ""
      header.hidden = !(format === "text" && headerText)
      header.textContent = headerText
    }

    const target = this.guided("previewBody")
    if (body.trim()) {
      target.classList.remove("is-empty")
      target.replaceChildren(...this.formatBody(body, examples))
    } else {
      target.classList.add("is-empty")
      target.textContent = "Sua mensagem aparece aqui enquanto você escreve."
    }

    const footerText = this.field("footer_text")?.value.trim() || ""
    const footer = this.guided("previewFooter")
    if (footer) {
      footer.hidden = !footerText
      footer.textContent = footerText
    }

    const actions = this.guided("previewButtons")
    if (actions) {
      const buttons = this.buttonValues().filter((button) => button.text)
      const visible = buttons.slice(0, 3).map((button) => this.previewAction(button.text, this.constructor.previewIcons[button.kind]))
      if (buttons.length > 3) visible.push(this.previewAction("Ver todas as opções", "bi-list-ul"))
      if (this.typeValue === "flow") visible.push(this.previewAction(this.flowValues().buttonText || "Abrir", "bi-ui-checks-grid"))
      actions.replaceChildren(...visible)
    }
    if (this.hasCarouselCardListTarget) this.renderCardSummaries()
    this.guided("previewCards")?.replaceChildren(...this.carouselCardRowTargets.map((row) => this.previewCard(this.cardValues(row))))

    this.setCounter("bodyCount", body.length, 1024)
    this.setCounter("footerCount", footerText.length, 60)
    this.renderNameHint()
  }

  // Cards do carrossel começam fechados; o cabeçalho mostra um resumo e se o card está completo.
  toggleCard(event) {
    const row = event.currentTarget.closest("[data-whatsapp-template-form-target='carouselCardRow']")
    if (row) this.setCardCollapsed(row, !row.classList.contains("is-collapsed"))
    this.syncToggleAllCards()
  }

  toggleAllCards() {
    const expand = this.carouselCardRowTargets.some((row) => row.classList.contains("is-collapsed"))
    this.carouselCardRowTargets.forEach((row) => this.setCardCollapsed(row, !expand))
    this.syncToggleAllCards()
  }

  setCardCollapsed(row, collapsed) {
    row.classList.toggle("is-collapsed", collapsed)
    row.querySelector(".wtb-cardrow__toggle")?.setAttribute("aria-expanded", String(!collapsed))
    const panel = row.querySelector(".wtb-cardrow__panel")
    if (panel) panel.inert = collapsed
  }

  syncToggleAllCards() {
    const button = this.guided("toggleAllCards")
    if (!button) return

    const anyCollapsed = this.carouselCardRowTargets.some((row) => row.classList.contains("is-collapsed"))
    button.querySelector("span").textContent = anyCollapsed ? "Expandir todos" : "Recolher todos"
    button.querySelector("i").className = `bi ${anyCollapsed ? "bi-arrows-expand" : "bi-arrows-collapse"} ax-ico`
  }

  renderCardSummaries() {
    this.carouselCardRowTargets.forEach((row) => {
      const card = this.cardValues(row)
      const started = this.cardStarted(card)
      const state = !started ? ["empty", "Vazio"] : (this.cardComplete(card) ? ["done", "Pronto"] : ["todo", "Incompleto"])
      const summary = row.querySelector("[data-card-summary]")
      const badge = row.querySelector("[data-card-state]")
      if (summary) summary.textContent = card.text || card.buttonText || "Ainda sem conteúdo"
      if (badge) {
        badge.textContent = state[1]
        badge.dataset.state = state[0]
      }
    })
  }

  flowValues() {
    const value = (name) => this.field(`flow_config][${name}`)?.value.trim() || ""
    return { flowId: value("flow_id"), buttonText: value("button_text") }
  }

  cardValues(row) {
    const value = (suffix) => row.querySelector(`[name$='[${suffix}]']`)?.value.trim() || ""
    return {
      media: value("media_type") || "image",
      handle: value("media_handle"),
      file: (row.querySelector("input[type='file']")?.files?.length || 0) > 0,
      text: value("text"),
      kind: value("button_kind") || "url",
      buttonText: value("button_text"),
      url: value("button_url"),
      phone: value("button_phone_number")
    }
  }

  cardStarted(card) { return !!(card.handle || card.file || card.text || card.buttonText || card.url || card.phone) }

  cardComplete(card) {
    const action = card.kind === "url" ? card.url : (card.kind === "phone_number" ? card.phone : true)
    return !!((card.handle || card.file) && card.text && card.buttonText && action)
  }

  previewCard(card) {
    const item = document.createElement("div")
    item.className = "wtb-mini"
    const [icon, label] = this.constructor.mediaLabels[card.media] || this.constructor.mediaLabels.image
    const media = document.createElement("div")
    media.className = "wtb-mini__media"
    const glyph = document.createElement("i")
    glyph.className = `bi ${icon}`
    const caption = document.createElement("span")
    caption.textContent = label
    media.append(glyph, caption)
    const text = document.createElement("p")
    text.textContent = card.text || "Texto do card"
    if (!card.text) text.classList.add("is-empty")
    item.append(media, text)
    if (card.buttonText) item.append(this.previewAction(card.buttonText, this.constructor.previewIcons[card.kind]))
    return item
  }

  // *negrito*, _itálico_ e {{n}} viram nós de DOM; nada do que o usuário digita entra como HTML.
  formatBody(text, examples) {
    const nodes = []
    let last = 0
    for (const match of text.matchAll(/\{\{(\d+)\}\}|\*([^*\n]+)\*|_([^_\n]+)_/g)) {
      if (match.index > last) nodes.push(document.createTextNode(text.slice(last, match.index)))
      let node
      if (match[1]) {
        const example = examples[Number(match[1]) - 1]
        node = document.createElement("mark")
        node.textContent = example || `{{${match[1]}}}`
        if (!example) node.classList.add("is-missing")
      } else {
        node = document.createElement(match[2] ? "strong" : "em")
        node.append(...this.formatBody(match[2] || match[3], examples))
      }
      nodes.push(node)
      last = match.index + match[0].length
    }
    if (last < text.length) nodes.push(document.createTextNode(text.slice(last)))
    return nodes
  }

  previewAction(label, icon) {
    const item = document.createElement("span")
    item.className = "wtb-action"
    const glyph = document.createElement("i")
    glyph.className = `bi ${icon}`
    const text = document.createElement("span")
    text.textContent = label
    item.append(glyph, text)
    return item
  }

  setCounter(name, size, limit) {
    const counter = this.guided(name)
    if (!counter) return

    counter.textContent = `${size} / ${limit}`
    counter.classList.toggle("is-near", size > limit * 0.9)
  }

  renderNameHint() {
    const hint = this.guided("nameHint")
    if (!hint || !this.hasNameInputTarget) return

    const slug = this.nameInputTarget.value.trim().toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
      .replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "")
    hint.hidden = this.nameInputTarget.readOnly || !slug || slug === this.nameInputTarget.value.trim()
    this.guided("nameSlug").textContent = slug
  }

  stepStates() {
    const type = this.typeValue
    const format = this.headerFormat()
    const variables = this.variableIndexes()
    const examples = this.exampleValues()
    const missingExamples = variables.filter((index) => !examples[index - 1]).length
    const hasBody = !!(this.hasBodyInputTarget && this.bodyInputTarget.value.trim())
    // A categoria já vem sugerida; a etapa só conta como feita quando a pessoa confirma (ou ao editar, onde ela é fixa).
    const categoryLocked = !!this.element.querySelector("input[name='whatsapp_template[category]']:disabled")
    const category = !!this.categoryConfirmed || categoryLocked
    const name = !!(this.hasNameInputTarget && this.nameInputTarget.value.trim())

    const checks = {
      name: [name ? "done" : "todo", name ? "Nome do template" : "Dê um nome ao template"],
      body: [hasBody ? "done" : "todo", hasBody ? "Texto da mensagem" : "Escreva o texto da mensagem"],
      examples: variables.length
        ? [missingExamples === 0 ? "done" : "todo", missingExamples === 0 ? "Exemplos das variáveis preenchidos" : `Faltam ${missingExamples} exemplo(s) de variável`]
        : ["done", "Sem variáveis, nada a exemplificar"]
    }
    let messageOk = hasBody && missingExamples === 0
    let step4
    let pendingLast

    if (type === "carousel") {
      const cards = this.carouselCardRowTargets.map((row) => this.cardValues(row)).filter((card) => this.cardStarted(card))
      const incomplete = cards.filter((card) => !this.cardComplete(card)).length
      const cardsOk = cards.length >= 2 && cards.length <= 10 && incomplete === 0
      checks.cards = [cardsOk ? "done" : "todo", cardsOk ? `${cards.length} cards prontos` : (cards.length < 2 ? "Monte pelo menos 2 cards" : `Complete ${incomplete} card(s): mídia, texto e botão`)]
      step4 = cardsOk ? "done" : "todo"
      pendingLast = !cardsOk && "os cards"
    } else if (type === "flow") {
      const flow = this.flowValues()
      const flowOk = !!(flow.flowId && flow.buttonText)
      checks.flow = [flowOk ? "done" : "todo", flowOk ? "Flow conectado" : (flow.flowId ? "Escreva o texto do botão" : "Informe o ID do Flow")]
      step4 = flowOk ? "done" : "todo"
      pendingLast = !flowOk && "a conexão com o Flow"
    } else {
      const headerText = this.field("header_text")?.value.trim()
      const mediaReady = !!this.field("header_media_handle")?.value
      const headerOk = format === "text" ? !!headerText : (["image", "video", "document"].includes(format) ? mediaReady : true)
      const buttons = this.buttonValues()
      const buttonsBroken = buttons.some((button) => !button.text || (button.kind !== "quick_reply" && !button.extra))
      const extras = !!(buttons.length || this.field("footer_text")?.value.trim())
      messageOk = messageOk && headerOk
      checks.header = format === "none"
        ? ["optional", "Sem cabeçalho"]
        : [headerOk ? "done" : "todo", headerOk ? "Cabeçalho pronto" : (format === "text" ? "Escreva o texto do cabeçalho" : "Anexe a mídia de exemplo")]
      checks.buttons = buttons.length
        ? [buttonsBroken ? "todo" : "done", buttonsBroken ? "Complete o texto e o link/telefone dos botões" : `${buttons.length} botão(ões) configurado(s)`]
        : ["optional", "Sem botões (opcional)"]
      step4 = extras && !buttonsBroken ? "done" : (buttonsBroken ? "todo" : "optional")
      pendingLast = buttonsBroken && "os botões"
    }

    const required = type === "text" ? [1, 2, 3] : [1, 2, 3, 4]
    return {
      checks,
      required,
      steps: { 1: name ? "done" : "todo", 2: category ? "done" : "todo", 3: messageOk ? "done" : "todo", 4: step4 },
      pending: [!name && "o nome", !category && "o objetivo", !messageOk && (type === "carousel" ? "a introdução" : "a mensagem"), pendingLast].filter(Boolean)
    }
  }

  updateProgress() {
    const { checks, steps, pending, required } = this.stepStates()
    const done = required.filter((step) => steps[step] === "done").length
    const ready = pending.length === 0
    steps[5] = ready ? "done" : "todo"

    this.element.querySelectorAll("[data-guided-step]").forEach((section) => { section.dataset.state = steps[section.dataset.guidedStep] })
    this.element.querySelectorAll(".ax-guided-steps-nav__item").forEach((item) => { item.dataset.state = steps[item.dataset.step] })
    Object.entries(checks).forEach(([key, [state, text]]) => {
      const item = this.element.querySelector(`[data-check='${key}']`)
      if (!item) return
      item.dataset.state = state
      item.querySelector("span").textContent = text
    })

    this.guided("progressBar").style.width = `${Math.round((done / required.length) * 100)}%`
    this.guided("progressCount").textContent = `${done} de ${required.length}`
    this.guided("progressLabel").textContent = ready ? "Pronto para enviar" : `Falta ${pending[0]}`
    this.element.classList.toggle("is-ready", ready)
  }

  focusStep(event) {
    const section = event.target.closest?.("[data-guided-step]")
    if (!section) return

    this.element.querySelectorAll("[data-guided-step]").forEach((item) => item.classList.toggle("is-active", item === section))
    this.element.querySelectorAll(".ax-guided-steps-nav__item").forEach((item) => item.classList.toggle("is-active", item.dataset.step === section.dataset.guidedStep))
  }

  goToStep(event) {
    const section = this.element.querySelector(`[data-guided-step='${event.currentTarget.dataset.step}']`)
    if (!section) return

    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    section.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "start" })
    section.querySelector("input:not([type='hidden']):not([type='radio']):not([type='checkbox']), textarea, select, button[type='submit']")?.focus({ preventScroll: true })
  }

  wrap(event) {
    if (!this.hasBodyInputTarget) return

    const field = this.bodyInputTarget
    const mark = event.currentTarget.dataset.wrap
    const { selectionStart: start, selectionEnd: end } = field
    const selected = field.value.slice(start, end) || "texto"
    field.setRangeText(`${mark}${selected}${mark}`, start, end, "select")
    field.setSelectionRange(start + 1, start + 1 + selected.length)
    field.focus()
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }

  insertVariable() {
    if (!this.hasBodyInputTarget) return

    const field = this.bodyInputTarget
    const next = Math.max(0, ...this.variableIndexes()) + 1
    const { selectionStart: start, selectionEnd: end } = field
    field.setRangeText(`{{${next}}}`, start, end, "end")
    field.focus()
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
