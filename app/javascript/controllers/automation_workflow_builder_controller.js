import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["definition", "canvas", "inspector", "inspectorTitle", "catalog", "aside"]

  connect() {
    this.catalog = this.parseJson(this.catalogTarget.textContent, { triggers: {}, actions: {}, statuses: {}, automation_stages: {}, sources: {}, brokers: {}, templates: {} })
    this.definition = this.normalizeDefinition(this.parseJson(this.definitionTarget.value, this.defaultDefinition()))
    this.selectedNodeId = this.definition.nodes?.[0]?.id
    this.sync()
    this.render()
  }

  zoomIn(event) {
    if (event) event.preventDefault()
    this.updateZoom(0.1)
  }

  zoomOut(event) {
    if (event) event.preventDefault()
    this.updateZoom(-0.1)
  }

  addNode(event) {
    const type = event.params.type
    if (type === "action") {
      this.openStepChooser(this.lastInsertAnchorId())
      return
    }

    const node = this.buildNode(type)
    this.insertNodeAfter(this.lastInsertAnchorId(), node, "sequential")

    this.selectedNodeId = node.id
    this.openDrawer()
    this.sync()
    this.render()
  }

  addActionAfter(event) {
    if (event) event.preventDefault()

    const afterId = event.currentTarget.dataset.nodeId
    const mode = event.currentTarget.dataset.insertMode || "sequential"
    this.openStepChooser(afterId, mode)
  }

  chooseStep(event) {
    if (event) event.preventDefault()

    const type = event.currentTarget.dataset.type
    const actionType = event.currentTarget.dataset.actionType
    const node = this.buildNode(type)

    if (node.type === "action" && actionType) {
      node.config.action_type = actionType
      node.label = this.catalog.actions?.[actionType] || node.label
    }

    this.insertNodeAfter(this.pendingInsertion?.afterId, node, this.pendingInsertion?.mode || "sequential")
    this.selectedNodeId = node.id
    this.pendingInsertion = null
    this.inspectorMode = "node"
    this.openDrawer()
    this.sync()
    this.render()
  }

  cancelStepChooser(event) {
    if (event) event.preventDefault()

    this.selectedNodeId = this.pendingInsertion?.afterId || this.selectedNodeId || this.definition.nodes?.[0]?.id
    this.pendingInsertion = null
    this.inspectorMode = "node"
    this.render()
  }

  openStepChooser(afterId, mode = "sequential") {
    const afterIndex = this.definition.nodes.findIndex((node) => node.id === afterId)
    const fallbackAfterId = this.lastInsertAnchorId()
    const anchorNode = this.definition.nodes[afterIndex] || this.definition.nodes.find((node) => node.id === fallbackAfterId)

    this.pendingInsertion = { afterId: anchorNode?.id || fallbackAfterId, mode: mode === "parallel" ? "parallel" : "sequential" }
    this.inspectorMode = "step_chooser"
    this.entryPolicyMenuOpen = false
    this.openDrawer()
    this.renderInspector()
  }

  selectNode(event) {
    this.selectedNodeId = event.currentTarget.dataset.nodeId
    this.pendingInsertion = null
    this.inspectorMode = "node"
    this.entryPolicyMenuOpen = false
    this.openDrawer()
    this.render()
  }

  toggleEntryPolicyMenu(event) {
    if (event) event.preventDefault()

    this.entryPolicyMenuOpen = !this.entryPolicyMenuOpen
    this.renderInspector()
  }

  chooseEntryPolicy(event) {
    if (event) event.preventDefault()

    const node = this.selectedNode()
    if (!node) return

    node.config = node.config || {}
    node.config.entry_policy = event.currentTarget.dataset.value
    this.entryPolicyMenuOpen = false

    this.sync()
    this.renderCanvas()
    this.renderInspector()
  }

  closeDrawer() {
    if (this.hasAsideTarget) this.asideTarget.classList.add("is-collapsed")
    this.element.classList.add("automation-workflow-builder--drawer-collapsed")
  }

  openDrawer() {
    if (this.hasAsideTarget) this.asideTarget.classList.remove("is-collapsed")
    this.element.classList.remove("automation-workflow-builder--drawer-collapsed")
  }

  updateZoom(delta) {
    this.definition.viewport = this.definition.viewport || {}
    this.definition.viewport.zoom = this.clampZoom(this.currentZoom() + delta)
    this.applyCanvasZoom()
    this.sync()
  }

  applyCanvasZoom() {
    const zoom = this.currentZoom()
    this.canvasTarget.style.zoom = zoom
    this.canvasTarget.dataset.zoom = `${Math.round(zoom * 100)}%`
    this.updateZoomButtons()
  }

  updateZoomButtons() {
    const zoom = this.currentZoom()
    this.element.querySelectorAll("[data-automation-workflow-builder-zoom]").forEach((button) => {
      const direction = button.dataset.automationWorkflowBuilderZoom
      button.disabled = direction === "out" ? zoom <= this.minZoom() : zoom >= this.maxZoom()
      button.title = `${direction === "out" ? "Reduzir" : "Aumentar"} zoom (${Math.round(zoom * 100)}%)`
    })
  }

  currentZoom() {
    return this.clampZoom(Number.parseFloat(this.definition?.viewport?.zoom || 1))
  }

  clampZoom(value) {
    const zoom = Number.isFinite(value) ? value : 1
    return Math.round(Math.min(this.maxZoom(), Math.max(this.minZoom(), zoom)) * 100) / 100
  }

  minZoom() {
    return 0.55
  }

  maxZoom() {
    return 1.45
  }

  updateNode(event) {
    const node = this.selectedNode()
    if (!node) return

    const field = event.currentTarget.dataset.field
    const value = event.currentTarget.type === "checkbox" ? event.currentTarget.checked : event.currentTarget.value

    if (field === "label") {
      node.label = value
    } else {
      node.config = node.config || {}
      node.config[field] = value
      if (node.type === "entry") this.normalizeEntryConfigForTrigger(node)
      if (node.type === "await_event") this.normalizeAwaitEventConfigForTrigger(node)
    }

    this.sync()
    this.renderCanvas()
    this.refreshLiteralSummary()
    if (event.currentTarget.tagName === "SELECT" || field === "retry_enabled") this.renderInspector()
  }

  removeNode(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }

    const nodeId = event?.currentTarget?.dataset?.nodeId || this.selectedNodeId
    const node = this.definition.nodes.find((item) => item.id === nodeId)
    if (!node || node.type === "entry") return

    const removedIndex = this.definition.nodes.findIndex((item) => item.id === node.id)
    const predecessors = this.incomingEdges(node.id).map((edge) => edge.from)
    const successors = this.outgoingEdges(node.id).map((edge) => edge.to)

    this.definition.nodes = this.definition.nodes.filter((item) => item.id !== node.id)
    this.definition.edges = this.definition.edges.filter((edge) => edge.from !== node.id && edge.to !== node.id)
    predecessors.forEach((from) => {
      successors.forEach((to) => {
        if (from !== to) this.addEdge(from, to)
      })
    })
    this.selectedNodeId = this.definition.nodes[Math.max(removedIndex - 1, 0)]?.id || this.definition.nodes[0]?.id
    this.sync()
    this.render()
  }

  moveNode(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }

    const nodeId = event.currentTarget.dataset.nodeId
    const direction = event.currentTarget.dataset.direction
    const levels = this.workflowLevels()
    const column = levels.find((items) => items.some((node) => node.id === nodeId))
    if (!column || column.length < 2) return

    const currentIndex = column.findIndex((node) => node.id === nodeId)
    const target = direction === "up" ? column[currentIndex - 1] : column[currentIndex + 1]
    if (!target) return

    this.reorderNodeNear(nodeId, target.id, direction === "up" ? "before" : "after")
    this.sync()
    this.renderCanvas()
  }

  render() {
    this.renderCanvas()
    this.renderInspector()
  }

  renderCanvas() {
    this.canvasTarget.replaceChildren()

    const levels = this.workflowLevels()
    levels.forEach((nodes, index) => {
      const column = document.createElement("div")
      column.className = `automation-workflow-builder__column ${nodes.length > 1 ? "automation-workflow-builder__column--parallel" : ""}`

      nodes.forEach((node) => {
        const slot = document.createElement("div")
        slot.className = "automation-workflow-builder__slot"
        slot.appendChild(this.nodeElement(node, nodes))
        if (!this.endsFlow(node)) slot.appendChild(this.inlineAddElement(node))
        column.appendChild(slot)
      })

      this.canvasTarget.appendChild(column)
      if (index < levels.length - 1) this.canvasTarget.appendChild(this.connectorElement())
    })

    this.applyCanvasZoom()
  }

  renderInspector() {
    const node = this.selectedNode()
    this.inspectorTarget.replaceChildren()

    if (this.inspectorMode === "step_chooser") {
      this.inspectorTitleTarget.textContent = "Adicionar intervenção"
      this.inspectorTarget.appendChild(this.stepChooserPanel())
      return
    }

    this.inspectorTitleTarget.textContent = node ? this.nodeTitle(node) : "Acompanhamento"

    if (!node) return

    this.inspectorTarget.appendChild(this.field("Nome do bloco", "label", node.label || this.nodeTitle(node)))
    this.inspectorTarget.appendChild(this.literalSummaryPanel(node))

    if (node.type === "entry") {
      this.inspectorTarget.appendChild(this.entryPolicyPanel(node))
      this.inspectorTarget.appendChild(this.selectField("Evento observado", "trigger", node.config?.trigger, this.catalog.triggers, { placeholder: "Selecione o evento" }))
      this.renderEntryEventFields(node)
    } else if (node.type === "action") {
      this.inspectorTarget.appendChild(this.selectField("Tipo de intervenção", "action_type", node.config?.action_type, this.actionOptionsFor(node), { placeholder: "Selecione a intervenção" }))
      this.renderActionFields(node)
      this.inspectorTarget.appendChild(this.finalActionField(node))
    } else if (node.type === "wait") {
      this.renderWaitFields(node)
    } else if (node.type === "await_event") {
      this.renderAwaitEventFields(node)
    } else if (node.type === "condition") {
      this.inspectorTarget.appendChild(this.selectField("Operador", "operator", node.config?.operator, {
        and: "E - todos os criterios",
        or: "OU - pelo menos um criterio"
      }, { placeholder: "Selecione o operador" }))
      this.inspectorTarget.appendChild(this.selectField("Etapa do lead", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      this.inspectorTarget.appendChild(this.selectField("Origem do lead", "source", node.config?.source, { "": "Qualquer origem", ...this.catalog.sources }, { placeholder: "Qualquer origem" }))
      this.inspectorTarget.appendChild(this.field("Resumo dos criterios", "summary", node.config?.summary || ""))
    }

    if (node.type !== "entry") {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "automation-workflow-builder__danger"
      button.dataset.action = "automation-workflow-builder#removeNode"
      button.innerHTML = '<i class="bi bi-trash"></i><span>Remover etapa</span>'
      this.inspectorTarget.appendChild(button)
    }
  }

  normalizeEntryConfigForTrigger(node) {
    const trigger = node.config?.trigger
    const keep = ["trigger", "entry_policy"]

    if (trigger === "lead_stage_changed") keep.push("from_stage", "to_stage")
    if (trigger === "lead_created") keep.push("stage", "source")
    if (trigger === "lead_idle") keep.push("idle_hours", "stage", "source")
    if (trigger === "whatsapp_received") keep.push("stage", "message_contains", "message_not_contains")
    if (trigger === "scheduled_routine") keep.push("schedule_frequency", "interval", "time_of_day", "weekdays", "month_day", "stage", "source")
    if (this.proposalEvents().includes(trigger)) keep.push("stage")
    if (this.interestEvents().includes(trigger)) keep.push("stage", "source", "minimum_score")

    Object.keys(node.config || {}).forEach((key) => {
      if (!keep.includes(key)) delete node.config[key]
    })
  }

  normalizeAwaitEventConfigForTrigger(node) {
    const trigger = node.config?.trigger
    const keep = ["trigger", "timeout_amount", "timeout_unit"]

    if (trigger === "lead_stage_changed") keep.push("from_stage", "to_stage")
    if (trigger === "whatsapp_received") keep.push("stage", "message_contains", "message_not_contains")
    if (this.proposalEvents().includes(trigger)) keep.push("stage")
    if (this.interestEvents().includes(trigger)) keep.push("stage", "source", "minimum_score")

    Object.keys(node.config || {}).forEach((key) => {
      if (!keep.includes(key)) delete node.config[key]
    })
  }

  nodeElement(node, columnNodes = []) {
    const wrapper = document.createElement("div")
    wrapper.className = "automation-workflow-builder__node-wrap"
    wrapper.dataset.nodeId = node.id

    const button = document.createElement("button")
    button.type = "button"
    button.className = `automation-workflow-builder__node automation-workflow-builder__node--${node.type} ${node.id === this.selectedNodeId ? "active" : ""}`
    button.dataset.action = "automation-workflow-builder#selectNode"
    button.dataset.nodeId = node.id

    const icon = document.createElement("i")
    icon.className = `bi ${this.nodeIcon(node)}`

    const content = document.createElement("span")
    content.className = "automation-workflow-builder__node-content"

    const title = document.createElement("strong")
    title.textContent = node.label || this.nodeTitle(node)

    const meta = document.createElement("small")
    meta.textContent = this.nodeSummary(node)

    content.append(title, meta)
    button.append(icon, content)
    wrapper.appendChild(button)

    if (columnNodes.length > 1) {
      const move = document.createElement("div")
      move.className = "automation-workflow-builder__node-move"
      const index = columnNodes.findIndex((item) => item.id === node.id)
      move.appendChild(this.moveButton(node, "up", index === 0))
      move.appendChild(this.moveButton(node, "down", index === columnNodes.length - 1))
      wrapper.appendChild(move)
    }

    if (node.type !== "entry") {
      const removeButton = document.createElement("button")
      removeButton.type = "button"
      removeButton.className = "automation-workflow-builder__node-remove"
      removeButton.dataset.action = "automation-workflow-builder#removeNode"
      removeButton.dataset.nodeId = node.id
    removeButton.title = "Remover etapa"
    removeButton.setAttribute("aria-label", "Remover etapa")
      removeButton.innerHTML = '<i class="bi bi-trash"></i>'
      wrapper.appendChild(removeButton)
    }

    return wrapper
  }

  moveButton(node, direction, disabled) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "automation-workflow-builder__node-move-btn"
    button.dataset.action = "automation-workflow-builder#moveNode"
    button.dataset.nodeId = node.id
    button.dataset.direction = direction
    button.disabled = disabled
    button.title = direction === "up" ? "Mover para cima" : "Mover para baixo"
    button.setAttribute("aria-label", button.title)
    button.innerHTML = `<i class="bi ${direction === "up" ? "bi-chevron-up" : "bi-chevron-down"}"></i>`
    return button
  }

  stepChooserPanel() {
    const panel = document.createElement("section")
    panel.className = "automation-workflow-builder__step-chooser"

    const header = document.createElement("div")
    header.className = "automation-workflow-builder__step-chooser-header"

    const anchor = this.definition.nodes.find((node) => node.id === this.pendingInsertion?.afterId)
    const anchorTitle = anchor ? (anchor.label || this.nodeTitle(anchor)) : "acompanhamento"

    const copy = document.createElement("div")
    const eyebrow = document.createElement("span")
    eyebrow.textContent = "Nova intervenção"
    const title = document.createElement("strong")
    title.textContent = this.pendingInsertion?.mode === "parallel"
      ? `Adicionar caminho paralelo a partir de ${anchorTitle}`
      : `Adicionar etapa depois de ${anchorTitle}`
    const description = document.createElement("p")
    description.textContent = this.pendingInsertion?.mode === "parallel"
      ? "Escolha uma intervenção que será executada em paralelo com os outros caminhos que saem desta etapa."
      : "Escolha o próximo passo da jornada. Depois da escolha, este drawer abre a configuração específica da etapa."
    copy.append(eyebrow, title, description)

    const cancel = document.createElement("button")
    cancel.type = "button"
    cancel.className = "automation-workflow-builder__step-chooser-cancel"
    cancel.dataset.action = "automation-workflow-builder#cancelStepChooser"
    cancel.innerHTML = '<i class="bi bi-arrow-left"></i><span>Voltar</span>'

    header.append(copy, cancel)
    panel.appendChild(header)
    panel.appendChild(this.stepChooserSearch())

    this.appendStepChooserGroup(panel, "Operação", "Tarefas e registros internos para organizar o atendimento.", this.actionStepOptions(["create_task", "add_note", "move_stage"]))
    this.appendStepChooserGroup(panel, "Comunicação", "Mensagens enviadas ao lead durante a jornada.", this.actionStepOptions(["send_whatsapp", "send_whatsapp_template"]))
    this.appendStepChooserGroup(panel, "Inteligência de Interesse", "Curadoria e recomendação com base no comportamento do lead e nos imóveis disponíveis.", this.actionStepOptions([
      "create_interest_curation_task",
      "add_interest_note",
      "suggest_matching_properties",
      "notify_broker_interest_opportunity",
      "prepare_matching_properties_whatsapp",
      "generate_interest_ai_summary"
    ]))
    this.appendStepChooserGroup(panel, "Controle do acompanhamento", "Tempo e critérios antes da próxima intervenção.", [
      { type: "wait", icon: "bi-clock", title: "Espera", copy: "Aguarda duração, data/hora ou próxima janela comercial antes de continuar." },
      { type: "await_event", icon: "bi-broadcast", title: "Aguardar evento", copy: "Espera resposta, etapa ou proposta acontecer antes do timeout." },
      { type: "condition", icon: "bi-signpost-split", title: "Condição", copy: "Segue somente quando etapa, origem ou critérios definidos forem atendidos." }
    ])

    const empty = document.createElement("div")
    empty.className = "automation-workflow-builder__step-chooser-empty"
    empty.hidden = true
    empty.textContent = "Nenhuma etapa encontrada com esse termo."
    panel.appendChild(empty)

    return panel
  }

  stepChooserSearch() {
    const wrap = document.createElement("label")
    wrap.className = "automation-workflow-builder__step-search"

    const icon = document.createElement("i")
    icon.className = "bi bi-search"

    const input = document.createElement("input")
    input.type = "search"
    input.placeholder = "Buscar etapa pelo título"
    input.autocomplete = "off"
    input.dataset.action = "input->automation-workflow-builder#filterStepChooser"
    input.setAttribute("aria-label", "Buscar etapa")

    wrap.append(icon, input)
    return wrap
  }

  filterStepChooser(event) {
    const query = this.normalizedSearchText(event.target.value)
    const panel = event.target.closest(".automation-workflow-builder__step-chooser")
    if (!panel) return

    let visibleCount = 0
    panel.querySelectorAll(".automation-workflow-builder__step-chooser-group").forEach((group) => {
      let groupVisible = false

      group.querySelectorAll(".automation-workflow-builder__step-option").forEach((option) => {
        const matches = query === "" || option.dataset.searchText.includes(query)
        option.hidden = !matches
        groupVisible = groupVisible || matches
        if (matches) visibleCount += 1
      })

      group.hidden = !groupVisible
    })

    const empty = panel.querySelector(".automation-workflow-builder__step-chooser-empty")
    if (empty) empty.hidden = visibleCount > 0
  }

  appendStepChooserGroup(panel, title, copy, options) {
    if (!options || options.length === 0) return

    panel.appendChild(this.stepChooserGroup(title, copy, options))
  }

  stepChooserGroup(title, copy, options) {
    const group = document.createElement("div")
    group.className = "automation-workflow-builder__step-chooser-group"

    const heading = document.createElement("div")
    heading.className = "automation-workflow-builder__step-chooser-group-title"
    heading.innerHTML = `<strong>${title}</strong><span>${copy}</span>`
    group.appendChild(heading)

    options.forEach((option) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "automation-workflow-builder__step-option"
      button.dataset.action = "automation-workflow-builder#chooseStep"
      button.dataset.type = option.type
      button.dataset.searchText = this.normalizedSearchText([option.title, option.copy, option.badge].filter(Boolean).join(" "))
      if (option.actionType) button.dataset.actionType = option.actionType

      const icon = document.createElement("span")
      icon.className = "automation-workflow-builder__step-option-icon"
      icon.innerHTML = `<i class="bi ${option.icon}"></i>`

      const text = document.createElement("span")
      text.className = "automation-workflow-builder__step-option-copy"

      const label = document.createElement("strong")
      label.textContent = option.title

      const description = document.createElement("span")
      description.textContent = option.copy

      if (option.badge) {
        const badge = document.createElement("em")
        badge.className = "automation-workflow-builder__step-option-badge"
        badge.textContent = option.badge
        text.append(label, badge, description)
      } else {
        text.append(label, description)
      }

      button.append(icon, text)
      group.appendChild(button)
    })

    return group
  }

  normalizedSearchText(value) {
    return value
      .toString()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .trim()
  }

  actionStepOptions(allowedTypes = null) {
    const entries = allowedTypes
      ? allowedTypes.filter((value) => this.catalog.actions?.[value]).map((value) => [value, this.catalog.actions[value]])
      : Object.entries(this.catalog.actions || {})

    return entries
      .filter(([value]) => value !== "wait" && !this.verticalDistributionActions().includes(value))
      .map(([value, label]) => ({
        type: "action",
        actionType: value,
        icon: this.actionIcon(value),
        title: label,
        copy: this.actionDescription(value),
        badge: this.actionBadge(value)
      }))
  }

  actionOptionsFor(node) {
    const options = { ...(this.catalog.actions || {}) }
    const actionType = node.config?.action_type

    if (actionType && this.verticalDistributionActions().includes(actionType) && !options[actionType]) {
      options[actionType] = this.actionLabel(actionType)
    }

    return options
  }

  verticalDistributionActions() {
    return ["assign_agent"]
  }

  actionLabel(actionType) {
    return (this.catalog.actions || {})[actionType] || {
      assign_agent: "Reatribuição legada"
    }[actionType]
  }

  inlineAddElement(node) {
    const wrapper = document.createElement("div")
    wrapper.className = "automation-workflow-builder__inline-add"

    wrapper.appendChild(this.inlineAddButton(node, "sequential", "Adicionar próxima etapa", "bi-plus-lg"))
    wrapper.appendChild(this.inlineAddButton(node, "parallel", "Adicionar caminho paralelo", "bi-diagram-2"))
    return wrapper
  }

  inlineAddButton(node, mode, title, icon) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = `automation-workflow-builder__inline-add-btn automation-workflow-builder__inline-add-btn--${mode}`
    button.dataset.action = "automation-workflow-builder#addActionAfter"
    button.dataset.nodeId = node.id
    button.dataset.insertMode = mode
    button.title = title
    button.setAttribute("aria-label", title)
    button.innerHTML = `<i class="bi ${icon}"></i>`
    return button
  }

  connectorElement() {
    const connector = document.createElement("div")
    connector.className = "automation-workflow-builder__connector"
    connector.innerHTML = '<span></span>'
    return connector
  }

  field(label, field, value, type = "text") {
    const wrap = document.createElement("label")
    wrap.className = "automation-workflow-builder__field"

    const text = document.createElement("span")
    text.textContent = label

    const input = document.createElement("input")
    input.className = "ax-input"
    input.type = type
    input.value = value || ""
    input.dataset.field = field
    input.dataset.action = "input->automation-workflow-builder#updateNode"

    wrap.append(text, input)
    return wrap
  }

  checkboxField(label, field, checked, help = "") {
    const wrap = document.createElement("label")
    wrap.className = "automation-workflow-builder__check-field"

    const input = document.createElement("input")
    input.type = "checkbox"
    input.checked = [true, "true", "1", 1].includes(checked)
    input.dataset.field = field
    input.dataset.action = "change->automation-workflow-builder#updateNode"

    const copy = document.createElement("span")
    copy.innerHTML = `<strong>${label}</strong>${help ? `<small>${help}</small>` : ""}`

    wrap.append(input, copy)
    return wrap
  }

  entryPolicyPanel(node) {
    const panel = document.createElement("section")
    panel.className = "automation-workflow-builder__entry-panel"

    const header = document.createElement("div")
    header.className = "automation-workflow-builder__entry-header"
    header.innerHTML = `
      <span class="automation-workflow-builder__entry-icon"><i class="bi bi-people-fill"></i></span>
      <span>
        <small>Quando observar</small>
        <strong>Defina o momento da intervenção</strong>
      </span>
    `

    const selected = node.config?.entry_policy || "future"
    const options = this.entryPolicyDetails()
    const selectedDetail = options[selected] || options.future
    const select = document.createElement("div")
    select.className = `automation-workflow-builder__entry-select ${this.entryPolicyMenuOpen ? "is-open" : ""}`

    const trigger = document.createElement("button")
    trigger.type = "button"
    trigger.className = "automation-workflow-builder__entry-select-trigger"
    trigger.dataset.action = "automation-workflow-builder#toggleEntryPolicyMenu"
    trigger.setAttribute("aria-haspopup", "listbox")
    trigger.setAttribute("aria-expanded", this.entryPolicyMenuOpen ? "true" : "false")
    trigger.innerHTML = `
      <span class="automation-workflow-builder__entry-select-copy">
        <strong>${selectedDetail.title}</strong>
        <span>${selectedDetail.copy}</span>
      </span>
      <span class="automation-workflow-builder__entry-select-badge">${selectedDetail.badge}</span>
      <i class="bi bi-chevron-down"></i>
    `
    select.appendChild(trigger)

    if (this.entryPolicyMenuOpen) {
      const menu = document.createElement("div")
      menu.className = "automation-workflow-builder__entry-select-menu"
      menu.setAttribute("role", "listbox")

      Object.entries(options).forEach(([value, detail]) => {
        const option = document.createElement("button")
        option.type = "button"
        option.className = `automation-workflow-builder__entry-select-option ${value === selected ? "is-selected" : ""}`
        option.dataset.action = "automation-workflow-builder#chooseEntryPolicy"
        option.dataset.value = value
        option.setAttribute("role", "option")
        option.setAttribute("aria-selected", value === selected ? "true" : "false")
        option.innerHTML = `
          <span class="automation-workflow-builder__entry-select-option-main">
            <strong>${detail.title}</strong>
            <span>${detail.copy}</span>
          </span>
          <em>${detail.badge}</em>
        `
        menu.appendChild(option)
      })

      select.appendChild(menu)
    }

    const info = document.createElement("p")
    info.className = "automation-workflow-builder__entry-note"
    info.innerHTML = `<i class="bi bi-info-circle"></i><span>${selectedDetail.note}</span>`

    panel.append(header, select, info)
    return panel
  }

  selectField(label, field, value, options, config = {}) {
    const wrap = document.createElement("label")
    wrap.className = `automation-workflow-builder__field ${config.compact ? "automation-workflow-builder__field--compact" : ""}`

    const text = document.createElement("span")
    text.textContent = label

    const select = document.createElement("select")
    select.className = "ax-select ax-autocomplete-select"
    select.dataset.controller = "tom-select"
    select.dataset.placeholder = config.placeholder || label
    select.dataset.tomSelectOptionsValue = JSON.stringify({
      searchField: ["text"]
    })
    select.dataset.field = field
    select.dataset.action = "change->automation-workflow-builder#updateNode"

    Object.entries(options || {}).forEach(([optionValue, optionLabel]) => {
      const option = document.createElement("option")
      option.value = optionValue
      option.textContent = optionLabel
      option.selected = optionValue === value
      select.appendChild(option)
    })

    wrap.append(text, select)
    return wrap
  }

  renderEntryEventFields(node) {
    if (node.config?.trigger === "scheduled_routine") {
      this.inspectorTarget.appendChild(this.selectField("Frequência", "schedule_frequency", node.config?.schedule_frequency, {
        every_n_minutes: "A cada intervalo",
        daily: "Todo dia",
        weekly: "Semanalmente",
        monthly: "Mensalmente"
      }, { placeholder: "Selecione a frequência" }))

      if ((node.config?.schedule_frequency || "every_n_minutes") === "every_n_minutes") {
        this.inspectorTarget.appendChild(this.field("Intervalo em minutos", "interval", node.config?.interval || "60", "number"))
      } else {
        this.inspectorTarget.appendChild(this.field("Horário", "time_of_day", node.config?.time_of_day || "09:00", "time"))

        if (node.config?.schedule_frequency === "weekly") {
          this.inspectorTarget.appendChild(this.selectField("Dia da semana", "weekdays", node.config?.weekdays, {
            "": "Qualquer dia",
            "1": "Segunda-feira",
            "2": "Terça-feira",
            "3": "Quarta-feira",
            "4": "Quinta-feira",
            "5": "Sexta-feira",
            "6": "Sábado",
            "0": "Domingo"
          }, { placeholder: "Selecione o dia" }))
        }

        if (node.config?.schedule_frequency === "monthly") {
          this.inspectorTarget.appendChild(this.field("Dia do mês", "month_day", node.config?.month_day || "1", "number"))
        }
      }

      this.inspectorTarget.appendChild(this.selectField("Etapa atual", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      this.inspectorTarget.appendChild(this.selectField("Origem do lead", "source", node.config?.source, { "": "Qualquer origem", ...this.catalog.sources }, { placeholder: "Qualquer origem" }))
      this.inspectorTarget.appendChild(this.entryEventNotice("Rotinas agendadas rodam pelo monitor periódico da automação. Use filtros para limitar quais leads entram em cada execução."))
    } else if (node.config?.trigger === "lead_stage_changed") {
      this.inspectorTarget.appendChild(this.selectField("De etapa", "from_stage", node.config?.from_stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      this.inspectorTarget.appendChild(this.selectField("Para etapa", "to_stage", node.config?.to_stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      this.inspectorTarget.appendChild(this.entryEventNotice("A automação roda quando a mudança de etapa bater com esses critérios. Deixe em branco quando qualquer etapa servir."))
    } else if (node.config?.trigger === "lead_created") {
      this.inspectorTarget.appendChild(this.selectField("Etapa inicial", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      this.inspectorTarget.appendChild(this.selectField("Origem do lead", "source", node.config?.source, { "": "Qualquer origem", ...this.catalog.sources }, { placeholder: "Qualquer origem" }))
      this.inspectorTarget.appendChild(this.entryEventNotice("Use estes filtros quando a jornada deve iniciar apenas para leads criados em uma etapa ou origem específica."))
    } else if (node.config?.trigger === "lead_idle") {
      this.inspectorTarget.appendChild(this.field("Parado ha (horas)", "idle_hours", node.config?.idle_hours || "48", "number"))
      this.inspectorTarget.appendChild(this.selectField("Etapa atual", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      this.inspectorTarget.appendChild(this.selectField("Origem do lead", "source", node.config?.source, { "": "Qualquer origem", ...this.catalog.sources }, { placeholder: "Qualquer origem" }))
      this.inspectorTarget.appendChild(this.entryEventNotice("Lead parado é avaliado por rotina periódica. Etapa e origem filtram quais leads entram nessa observação."))
    } else if (node.config?.trigger === "whatsapp_received") {
      this.inspectorTarget.appendChild(this.selectField("Etapa atual", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      this.inspectorTarget.appendChild(this.field("Mensagem contem", "message_contains", node.config?.message_contains || ""))
      this.inspectorTarget.appendChild(this.field("Mensagem nao contem", "message_not_contains", node.config?.message_not_contains || ""))
      this.inspectorTarget.appendChild(this.entryEventNotice("O filtro usa o texto da mensagem recebida. Deixe os campos de texto vazios para aceitar qualquer resposta."))
    } else if (this.proposalEvents().includes(node.config?.trigger)) {
      this.inspectorTarget.appendChild(this.selectField("Etapa atual do lead", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      this.inspectorTarget.appendChild(this.entryEventNotice("Use este filtro quando a automação de proposta deve rodar somente para leads em uma etapa específica."))
    } else if (this.interestEvents().includes(node.config?.trigger)) {
      this.inspectorTarget.appendChild(this.selectField("Etapa atual", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      this.inspectorTarget.appendChild(this.selectField("Origem do lead", "source", node.config?.source, { "": "Qualquer origem", ...this.catalog.sources }, { placeholder: "Qualquer origem" }))
      if (node.config?.trigger === "matching_property_found") {
        this.inspectorTarget.appendChild(this.field("Score mínimo do imóvel", "minimum_score", node.config?.minimum_score || "65", "number"))
      }
      this.inspectorTarget.appendChild(this.entryEventNotice("Estes eventos vêm da Inteligência de Interesse: navegação pública, imóveis vistos, filtros usados e perfil real do lead após a conversão."))
    }
  }

  proposalEvents() {
    return ["proposal_viewed", "proposal_accepted", "proposal_rejected"]
  }

  interestEvents() {
    return [
      "interest_profile_detected",
      "matching_property_found",
      "lead_without_matching_property",
      "interest_profile_incomplete",
      "interested_property_price_dropped",
      "lead_repeated_similar_property_views"
    ]
  }

  entryEventNotice(message) {
    const notice = document.createElement("p")
    notice.className = "automation-workflow-builder__entry-note"
    notice.innerHTML = `<i class="bi bi-info-circle"></i><span>${message}</span>`
    return notice
  }

  literalSummaryPanel(node) {
    const panel = document.createElement("section")
    panel.className = "automation-workflow-builder__literal-summary"
    panel.dataset.literalSummary = "true"

    const icon = document.createElement("span")
    icon.className = "automation-workflow-builder__literal-summary-icon"
    icon.innerHTML = '<i class="bi bi-card-text"></i>'

    const copy = document.createElement("span")
    copy.className = "automation-workflow-builder__literal-summary-copy"

    const title = document.createElement("strong")
    title.textContent = "Resumo literal"

    const summary = document.createElement("small")
    summary.textContent = this.literalSummaryForNode(node)

    copy.append(title, summary)
    panel.append(icon, copy)
    return panel
  }

  refreshLiteralSummary() {
    const summary = this.inspectorTarget.querySelector("[data-literal-summary] small")
    if (!summary) return

    const node = this.selectedNode()
    summary.textContent = node ? this.literalSummaryForNode(node) : ""
  }

  literalSummaryForNode(node) {
    if (!node) return "Selecione uma etapa para ver o que será executado."

    if (node.type === "entry") return this.entryLiteralSummary(node)
    if (node.type === "wait") return this.waitLiteralSummary(node)
    if (node.type === "await_event") return this.awaitEventLiteralSummary(node)
    if (node.type === "action") return this.actionLiteralSummary(node)
    if (node.type === "condition") return this.conditionLiteralSummary(node)

    return "Configurar esta etapa para continuar o acompanhamento do lead."
  }

  entryLiteralSummary(node) {
    const trigger = node.config?.trigger
    const triggerLabel = this.valueLabel(this.catalog.triggers, trigger, "o evento observado")
    const policy = node.config?.entry_policy === "existing_and_future" ? "a base atual e os próximos eventos" : "somente novos eventos"

    if (trigger === "scheduled_routine") {
      const frequency = this.scheduledLiteralSummary(node)
      const filters = this.filterLiteralParts(node, ["stage", "source"]).join(" e ")
      return `Observar ${frequency}${filters ? ` para leads com ${filters}` : ""}, considerando ${policy}.`
    }

    if (trigger === "lead_stage_changed") {
      const from = this.valueLabel(this.catalog.statuses, node.config?.from_stage, "qualquer etapa")
      const to = this.valueLabel(this.catalog.statuses, node.config?.to_stage, "qualquer etapa")
      return `Iniciar esta automação quando o lead mudar de ${from} para ${to}, considerando ${policy}.`
    }

    if (trigger === "lead_created") {
      const filters = this.filterLiteralParts(node, ["stage", "source"]).join(" e ")
      return `Iniciar esta automação quando um lead for criado${filters ? ` com ${filters}` : ""}, considerando ${policy}.`
    }

    if (trigger === "lead_idle") {
      const hours = node.config?.idle_hours || "48"
      const filters = this.filterLiteralParts(node, ["stage", "source"]).join(" e ")
      return `Iniciar esta automação quando o lead ficar parado por ${hours} hora(s)${filters ? ` com ${filters}` : ""}, considerando ${policy}.`
    }

    if (trigger === "whatsapp_received") {
      const filters = this.filterLiteralParts(node, ["stage"]).join(" e ")
      const contains = node.config?.message_contains ? ` contendo "${node.config.message_contains}"` : ""
      const notContains = node.config?.message_not_contains ? ` e sem conter "${node.config.message_not_contains}"` : ""
      return `Iniciar esta automação quando o lead responder no WhatsApp${contains}${notContains}${filters ? ` com ${filters}` : ""}, considerando ${policy}.`
    }

    if (this.proposalEvents().includes(trigger)) {
      const stage = this.valueLabel(this.catalog.statuses, node.config?.stage, "")
      return `Iniciar esta automação quando acontecer "${triggerLabel}"${stage ? ` para leads na etapa ${stage}` : ""}, considerando ${policy}.`
    }

    if (this.interestEvents().includes(trigger)) {
      const filters = this.filterLiteralParts(node, ["stage", "source"]).join(" e ")
      const score = trigger === "matching_property_found" ? ` com score mínimo ${node.config?.minimum_score || "65"}` : ""
      return `Iniciar esta automação quando a Inteligência de Interesse detectar "${triggerLabel}"${score}${filters ? ` para leads com ${filters}` : ""}, considerando ${policy}.`
    }

    return `Iniciar esta automação quando acontecer "${triggerLabel}", considerando ${policy}.`
  }

  scheduledLiteralSummary(node) {
    const frequency = node.config?.schedule_frequency || "every_n_minutes"
    if (frequency === "daily") return `todo dia às ${node.config?.time_of_day || "09:00"}`
    if (frequency === "weekly") {
      const weekday = this.valueLabel({
        "": "qualquer dia",
        "1": "segunda-feira",
        "2": "terça-feira",
        "3": "quarta-feira",
        "4": "quinta-feira",
        "5": "sexta-feira",
        "6": "sábado",
        "0": "domingo"
      }, node.config?.weekdays, "qualquer dia")
      return `semanalmente em ${weekday} às ${node.config?.time_of_day || "09:00"}`
    }
    if (frequency === "monthly") return `mensalmente no dia ${node.config?.month_day || "1"} às ${node.config?.time_of_day || "09:00"}`
    return `a cada ${node.config?.interval || "60"} minuto(s)`
  }

  waitLiteralSummary(node) {
    const mode = node.config?.mode || "duration"

    if (mode === "datetime") {
      const runAt = node.config?.run_at || "a data e hora selecionada"
      return `Aguardar até ${runAt} antes de seguir para a próxima etapa.`
    }

    if (mode === "business_duration") {
      const amount = node.config?.amount || "1"
      const unit = this.unitLabel(node.config?.unit)
      const window = `${node.config?.business_start || "09:00"} até ${node.config?.business_end || "18:00"}`
      const weekends = this.booleanConfig(node.config?.skip_weekends, true) ? " pulando fins de semana" : ""
      return `Aguardar duração de ${amount} ${unit} dentro da janela comercial de ${window}${weekends} antes de seguir para a próxima etapa.`
    }

    if (mode === "next_business_window") {
      const window = `${node.config?.business_start || "09:00"} até ${node.config?.business_end || "18:00"}`
      const weekends = this.booleanConfig(node.config?.skip_weekends, true) ? " pulando fins de semana" : ""
      return `Aguardar a próxima janela comercial de ${window}${weekends} antes de seguir para a próxima etapa.`
    }

    const amount = node.config?.amount || "1"
    const unit = this.unitLabel(node.config?.unit)
    return `Aguardar duração de ${amount} ${unit} antes de seguir para a próxima etapa.`
  }

  awaitEventLiteralSummary(node) {
    const triggerLabel = this.valueLabel(this.awaitableEvents(), node.config?.trigger, "o evento esperado")
    const timeout = `${node.config?.timeout_amount || "1"} ${this.unitLabel(node.config?.timeout_unit)}`
    const details = []

    if (node.config?.trigger === "lead_stage_changed") {
      details.push(`de ${this.valueLabel(this.catalog.statuses, node.config?.from_stage, "qualquer etapa")}`)
      details.push(`para ${this.valueLabel(this.catalog.statuses, node.config?.to_stage, "qualquer etapa")}`)
    } else if (node.config?.trigger === "whatsapp_received") {
      if (node.config?.stage) details.push(`na etapa ${this.valueLabel(this.catalog.statuses, node.config.stage, node.config.stage)}`)
      if (node.config?.message_contains) details.push(`mensagem contendo "${node.config.message_contains}"`)
      if (node.config?.message_not_contains) details.push(`mensagem sem conter "${node.config.message_not_contains}"`)
    } else if (this.proposalEvents().includes(node.config?.trigger) && node.config?.stage) {
      details.push(`na etapa ${this.valueLabel(this.catalog.statuses, node.config.stage, node.config.stage)}`)
    } else if (this.interestEvents().includes(node.config?.trigger)) {
      details.push(...this.filterLiteralParts(node, ["stage", "source"]))
      if (node.config?.trigger === "matching_property_found") details.push(`score mínimo ${node.config?.minimum_score || "65"}`)
    }

    return `Aguardar "${triggerLabel}"${details.length ? ` com ${details.join(" e ")}` : ""} por até ${timeout}; se acontecer antes, seguir imediatamente.`
  }

  actionLiteralSummary(node) {
    const actionType = node.config?.action_type || "create_task"
    const actionLabel = this.actionLabel(actionType) || "intervenção"
    let summary

    if (actionType === "create_task") {
      const title = node.config?.title || node.config?.message || "sem título definido"
      summary = `Criar tarefa "${title}" para o responsável atual do lead, com vencimento em ${node.config?.due_in_hours || "24"} hora(s). ${this.taskFallbackLiteral(node)}`
    } else if (actionType === "send_whatsapp") {
      summary = node.config?.message ? "Enviar WhatsApp para o lead com a mensagem configurada." : "Configurar a mensagem de WhatsApp que será enviada ao lead."
    } else if (actionType === "send_whatsapp_template") {
      const template = this.valueLabel(this.catalog.templates, node.config?.template, "um modelo ainda não selecionado")
      summary = `Enviar modelo WhatsApp "${template}" para o lead.`
    } else if (actionType === "move_stage") {
      const stage = this.valueLabel(this.catalog.automation_stages || this.catalog.statuses, node.config?.to, "uma etapa ainda não selecionada")
      summary = `Mover o lead para a etapa "${stage}" como apoio ao acompanhamento.`
    } else if (actionType === "assign_agent") {
      summary = "Ação legada de atribuição de corretor; novas automações devem evitar assumir regra primária de distribuição."
    } else if (actionType === "add_note") {
      summary = node.config?.body ? "Registrar a nota interna configurada no histórico do lead." : "Configurar a nota interna que será registrada no histórico do lead."
    } else if (actionType === "create_interest_curation_task") {
      const title = node.config?.title || "Curar imóveis para o lead"
      summary = `Criar tarefa "${title}" para curadoria de imóveis pelo responsável atual do lead, com vencimento em ${node.config?.due_in_hours || "4"} hora(s). ${this.taskFallbackLiteral(node)}`
    } else if (actionType === "add_interest_note") {
      summary = "Registrar no histórico do lead o perfil de interesse detectado pela plataforma."
    } else if (actionType === "suggest_matching_properties") {
      summary = `Sugerir até ${node.config?.limit || "5"} imóvel(is) compatíveis e registrar a curadoria para a operação.`
    } else if (actionType === "notify_broker_interest_opportunity") {
      const title = node.config?.title || "Oportunidade de interesse para o lead"
      summary = `Criar alerta em tarefa "${title}" para o responsável atual do lead, vencendo em ${node.config?.due_in_hours || "2"} hora(s). ${this.taskFallbackLiteral(node)}`
    } else if (actionType === "prepare_matching_properties_whatsapp") {
      summary = `Preparar WhatsApp com até ${node.config?.limit || "3"} imóvel(is) compatíveis para revisão ou envio conforme configuração. Se gerar tarefa de revisão, ${this.taskFallbackLiteral(node).toLowerCase()}`
    } else if (actionType === "generate_interest_ai_summary") {
      const leadMessage = this.booleanConfig(node.config?.include_lead_message, true) ? " incluindo sugestão de mensagem ao lead" : ""
      summary = `Gerar resumo de interesse com IA${leadMessage}.`
    } else {
      summary = `Executar "${actionLabel}" com os dados configurados nesta etapa.`
    }

    const retry = this.retryLiteralSummary(node)
    const stop = this.endsFlow(node) ? " Depois desta intervenção, encerrar o acompanhamento deste caminho." : ""
    return `${summary}${retry ? ` ${retry}` : ""}${stop}`
  }

  retryLiteralSummary(node) {
    if (!this.booleanConfig(node.config?.retry_enabled, false)) return ""

    const attempts = node.config?.retry_attempts || "3"
    const amount = node.config?.retry_delay_amount || "15"
    const unit = this.unitLabel(node.config?.retry_delay_unit)
    return `Se falhar, retentar até ${attempts} vez(es), aguardando ${amount} ${unit} entre tentativas.`
  }

  taskFallbackLiteral(node) {
    const fallback = this.valueLabel(this.catalog.brokers, node.config?.fallback_admin_user_id, "")
    if (fallback) return `Se o lead estiver sem responsável, atribuir para ${fallback}.`

    return "Se o lead estiver sem responsável e nenhum fallback for escolhido, usar o primeiro usuário ativo como compatibilidade legada."
  }

  conditionLiteralSummary(node) {
    const operator = node.config?.operator === "or" ? "pelo menos um dos critérios" : "todos os critérios"
    const filters = this.filterLiteralParts(node, ["stage", "source"])
    if (node.config?.summary) filters.push(`critério manual "${node.config.summary}"`)

    if (!filters.length) {
      return `Continuar para a próxima etapa quando ${operator} configurados forem atendidos. Defina ao menos um critério para deixar esta condição objetiva.`
    }

    return `Continuar somente quando ${operator} forem atendidos: ${filters.join("; ")}.`
  }

  filterLiteralParts(node, fields) {
    const parts = []
    fields.forEach((field) => {
      if (field === "stage" && node.config?.stage) parts.push(`etapa ${this.valueLabel(this.catalog.statuses, node.config.stage, node.config.stage)}`)
      if (field === "source" && node.config?.source) parts.push(`origem ${this.valueLabel(this.catalog.sources, node.config.source, node.config.source)}`)
    })
    return parts
  }

  valueLabel(options, value, fallback = "") {
    if (value === undefined || value === null || value === "") return fallback
    return options?.[value] || value || fallback
  }

  booleanConfig(value, fallback = false) {
    if (value === undefined || value === null || value === "") return fallback
    return [true, "true", "1", 1].includes(value)
  }

  entryPolicyOptions() {
    return {
      future: "Somente novos eventos",
      existing_and_future: "Base atual e novos eventos"
    }
  }

  entryPolicyDetails() {
    return {
      future: {
        title: "Somente novos encaixes",
        badge: "Padrao",
        copy: "A intervenção roda apenas para leads que atenderem às condições depois da ativação.",
        note: "Use esta opção para acompanhar eventos futuros sem mexer nos leads que já estão em andamento."
      },
      existing_and_future: {
        title: "Base atual e novos encaixes",
        badge: "Inclui atuais",
        copy: "A intervenção considera leads que já atendem às condições agora e os que atenderem depois.",
        note: "Use esta opção quando o acompanhamento também deve avaliar leads que já estão no processo no momento da ativação."
      }
    }
  }

  renderWaitFields(node) {
    const mode = node.config?.mode || "duration"

    this.inspectorTarget.appendChild(this.selectField("Tipo de espera", "mode", mode, {
      duration: "Aguardar duração",
      datetime: "Até data e hora",
      business_duration: "Duração em horário comercial",
      next_business_window: "Próxima janela comercial"
    }, { placeholder: "Selecione o tipo" }))

    if (mode === "datetime") {
      this.inspectorTarget.appendChild(this.field("Executar em", "run_at", node.config?.run_at || "", "datetime-local"))
      this.inspectorTarget.appendChild(this.entryEventNotice("Se a data/hora já tiver passado quando a etapa rodar, a automação continua imediatamente."))
      return
    }

    if (mode !== "next_business_window") {
      this.inspectorTarget.appendChild(this.selectField("Unidade", "unit", node.config?.unit, {
        minutes: "Minutos",
        hours: "Horas",
        days: "Dias"
      }, { placeholder: "Selecione a unidade" }))
      this.inspectorTarget.appendChild(this.field("Quantidade", "amount", node.config?.amount || "1", "number"))
    }

    if (mode === "business_duration" || mode === "next_business_window") {
      this.inspectorTarget.appendChild(this.field("Início da janela", "business_start", node.config?.business_start || "09:00", "time"))
      this.inspectorTarget.appendChild(this.field("Fim da janela", "business_end", node.config?.business_end || "18:00", "time"))
      this.inspectorTarget.appendChild(this.checkboxField("Ignorar fins de semana", "skip_weekends", node.config?.skip_weekends ?? true, "Se estiver marcado, sábado e domingo são pulados."))
      this.inspectorTarget.appendChild(this.entryEventNotice("A janela comercial usa o horário da plataforma. Feriados e calendários por loja podem entrar depois como calendário próprio."))
    }
  }

  renderAwaitEventFields(node) {
    this.inspectorTarget.appendChild(this.selectField("Evento esperado", "trigger", node.config?.trigger, this.awaitableEvents(), { placeholder: "Selecione o evento" }))

    if (node.config?.trigger === "lead_stage_changed") {
      this.inspectorTarget.appendChild(this.selectField("De etapa", "from_stage", node.config?.from_stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      this.inspectorTarget.appendChild(this.selectField("Para etapa", "to_stage", node.config?.to_stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
    } else if (node.config?.trigger === "whatsapp_received") {
      this.inspectorTarget.appendChild(this.selectField("Etapa atual", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      this.inspectorTarget.appendChild(this.field("Mensagem contém", "message_contains", node.config?.message_contains || ""))
      this.inspectorTarget.appendChild(this.field("Mensagem não contém", "message_not_contains", node.config?.message_not_contains || ""))
    } else if (this.proposalEvents().includes(node.config?.trigger)) {
      this.inspectorTarget.appendChild(this.selectField("Etapa atual do lead", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
    } else if (this.interestEvents().includes(node.config?.trigger)) {
      this.inspectorTarget.appendChild(this.selectField("Etapa atual", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      this.inspectorTarget.appendChild(this.selectField("Origem do lead", "source", node.config?.source, { "": "Qualquer origem", ...this.catalog.sources }, { placeholder: "Qualquer origem" }))
      if (node.config?.trigger === "matching_property_found") {
        this.inspectorTarget.appendChild(this.field("Score mínimo do imóvel", "minimum_score", node.config?.minimum_score || "65", "number"))
      }
    }

    this.inspectorTarget.appendChild(this.field("Timeout", "timeout_amount", node.config?.timeout_amount || "1", "number"))
    this.inspectorTarget.appendChild(this.selectField("Unidade do timeout", "timeout_unit", node.config?.timeout_unit, {
      minutes: "Minutos",
      hours: "Horas",
      days: "Dias"
    }, { placeholder: "Selecione a unidade" }))
    this.inspectorTarget.appendChild(this.entryEventNotice("Se o evento acontecer antes do timeout, o fluxo continua. Se não acontecer, continua quando o timeout vencer."))
  }

  awaitableEvents() {
    const options = { ...(this.catalog.triggers || {}) }
    delete options.scheduled_routine
    delete options.lead_idle
    return options
  }

  renderActionFields(node) {
    const actionType = node.config?.action_type || "create_task"

    if (actionType === "create_task") {
      this.inspectorTarget.appendChild(this.field("Titulo da tarefa", "title", node.config?.title || node.config?.message || ""))
      this.inspectorTarget.appendChild(this.field("Vencimento em horas", "due_in_hours", node.config?.due_in_hours || "24", "number"))
      this.renderTaskAssigneeFallbackField(node)
    } else if (actionType === "send_whatsapp") {
      this.inspectorTarget.appendChild(this.textArea("Mensagem WhatsApp", "message", node.config?.message || ""))
    } else if (actionType === "send_whatsapp_template") {
      this.inspectorTarget.appendChild(this.selectField("Modelo WhatsApp", "template", node.config?.template, this.catalog.templates, { placeholder: "Selecione o modelo" }))
    } else if (actionType === "move_stage") {
      this.inspectorTarget.appendChild(this.selectField("Mover para etapa", "to", node.config?.to, this.catalog.automation_stages || this.catalog.statuses, { placeholder: "Selecione a etapa" }))
      this.inspectorTarget.appendChild(this.moveStageNotice())
    } else if (actionType === "assign_agent") {
      this.inspectorTarget.appendChild(this.legacyVerticalActionNotice())
    } else if (actionType === "add_note") {
      this.inspectorTarget.appendChild(this.textArea("Nota interna", "body", node.config?.body || node.config?.message || ""))
    } else if (actionType === "create_interest_curation_task") {
      this.inspectorTarget.appendChild(this.field("Titulo da tarefa", "title", node.config?.title || "Curar imóveis para o lead"))
      this.inspectorTarget.appendChild(this.field("Vencimento em horas", "due_in_hours", node.config?.due_in_hours || "4", "number"))
      this.renderTaskAssigneeFallbackField(node)
      this.inspectorTarget.appendChild(this.textArea("Orientação para o responsável", "notes", node.config?.notes || "Validar imóveis compatíveis antes de enviar ao cliente."))
    } else if (actionType === "add_interest_note") {
      this.inspectorTarget.appendChild(this.textArea("Nota interna", "body", node.config?.body || "Registrar perfil de interesse detectado automaticamente."))
    } else if (actionType === "suggest_matching_properties") {
      this.inspectorTarget.appendChild(this.field("Quantidade máxima de sugestões", "limit", node.config?.limit || "5", "number"))
      this.inspectorTarget.appendChild(this.entryEventNotice("A sugestão registra uma nota interna com imóveis compatíveis. O envio ao cliente continua sendo decisão da operação."))
    } else if (actionType === "notify_broker_interest_opportunity") {
      this.inspectorTarget.appendChild(this.field("Titulo da tarefa", "title", node.config?.title || "Oportunidade de interesse para o lead"))
      this.inspectorTarget.appendChild(this.field("Vencimento em horas", "due_in_hours", node.config?.due_in_hours || "2", "number"))
      this.renderTaskAssigneeFallbackField(node)
      this.inspectorTarget.appendChild(this.entryEventNotice("Cria uma tarefa para o responsável atual do lead agir sobre uma oportunidade detectada pela navegação e pelos imóveis compatíveis."))
    } else if (actionType === "prepare_matching_properties_whatsapp") {
      this.inspectorTarget.appendChild(this.field("Quantidade de imóveis", "limit", node.config?.limit || "3", "number"))
      this.inspectorTarget.appendChild(this.textArea("Introdução da mensagem", "message_prefix", node.config?.message_prefix || "Separei algumas opções que combinam com o que você está buscando."))
      this.renderTaskAssigneeFallbackField(node)
      this.inspectorTarget.appendChild(this.entryEventNotice("Se revisão humana estiver ativa, a plataforma cria rascunho/nota. Envio direto só acontece quando permitido nas configurações."))
    } else if (actionType === "generate_interest_ai_summary") {
      this.inspectorTarget.appendChild(this.checkboxField("Incluir sugestão de mensagem ao lead", "include_lead_message", node.config?.include_lead_message ?? true, "Quando marcado, a nota inclui também um texto sugerido para contato."))
      this.inspectorTarget.appendChild(this.entryEventNotice("Usa OpenAI quando configurada em Integrações > IA. Sem token, gera um resumo determinístico com os dados disponíveis."))
    } else {
      this.inspectorTarget.appendChild(this.field("Texto / titulo / observacao", "message", node.config?.message || ""))
    }

    this.renderRetryFields(node)
  }

  renderTaskAssigneeFallbackField(node) {
    this.inspectorTarget.appendChild(this.selectField(
      "Fallback se lead estiver sem responsável",
      "fallback_admin_user_id",
      node.config?.fallback_admin_user_id,
      this.taskFallbackOptions(),
      { placeholder: "Escolha quem recebe se não houver responsável" }
    ))
    this.inspectorTarget.appendChild(this.entryEventNotice("A tarefa sempre tenta usar primeiro o responsável atual do lead. Este fallback só é usado quando o lead estiver sem responsável."))
  }

  taskFallbackOptions() {
    return { "": "Compatibilidade legada: primeiro usuário ativo", ...(this.catalog.brokers || {}) }
  }

  renderRetryFields(node) {
    this.inspectorTarget.appendChild(this.checkboxField("Retentar se esta intervenção falhar", "retry_enabled", node.config?.retry_enabled, "Útil para WhatsApp, integrações e ações sujeitas a falha temporária."))

    if (![true, "true", "1", 1].includes(node.config?.retry_enabled)) return

    this.inspectorTarget.appendChild(this.field("Máximo de retentativas", "retry_attempts", node.config?.retry_attempts || "3", "number"))
    this.inspectorTarget.appendChild(this.field("Intervalo da retentativa", "retry_delay_amount", node.config?.retry_delay_amount || "15", "number"))
    this.inspectorTarget.appendChild(this.selectField("Unidade do intervalo", "retry_delay_unit", node.config?.retry_delay_unit, {
      minutes: "Minutos",
      hours: "Horas",
      days: "Dias"
    }, { placeholder: "Selecione a unidade" }))
  }

  legacyVerticalActionNotice() {
    const notice = document.createElement("section")
    notice.className = "automation-workflow-builder__legacy-action"
    notice.innerHTML = `
      <i class="bi bi-diagram-3"></i>
      <span>
        <strong>Ação vertical de distribuição</strong>
        <small>Esta ação é legada e não deve ser usada em novas automações. Responsável, fila, aceite, represamento e destino do lead pertencem à Distribuição de Leads.</small>
      </span>
    `
    return notice
  }

  moveStageNotice() {
    const notice = document.createElement("section")
    notice.className = "automation-workflow-builder__legacy-action"
    notice.innerHTML = `
      <i class="bi bi-info-circle"></i>
      <span>
        <strong>Etapa de acompanhamento</strong>
        <small>A automação não move para aceite ou represamento. Esses estados são controlados pela Distribuição de Leads.</small>
      </span>
    `
    return notice
  }


  finalActionField(node) {
    const wrap = document.createElement("label")
    wrap.className = "automation-workflow-builder__final-action"

    const input = document.createElement("input")
    input.type = "checkbox"
    input.checked = this.endsFlow(node)
    input.dataset.field = "stop_flow"
    input.dataset.action = "change->automation-workflow-builder#updateNode"

    const marker = document.createElement("span")
    marker.className = "automation-workflow-builder__final-action-marker"
    marker.innerHTML = '<i class="bi bi-check2"></i>'

    const copy = document.createElement("span")
    copy.className = "automation-workflow-builder__final-action-copy"
    copy.innerHTML = `
      <strong>Encerrar acompanhamento após esta intervenção</strong>
      <span>Quando marcado, a automação termina assim que esta intervenção for executada.</span>
    `

    wrap.append(input, marker, copy)
    return wrap
  }

  textArea(label, field, value) {
    const wrap = document.createElement("label")
    wrap.className = "automation-workflow-builder__field"

    const text = document.createElement("span")
    text.textContent = label

    const input = document.createElement("textarea")
    input.className = "ax-input automation-workflow-builder__textarea"
    input.value = value || ""
    input.dataset.field = field
    input.dataset.action = "input->automation-workflow-builder#updateNode"

    wrap.append(text, input)
    return wrap
  }

  entryPolicyExplanation(value) {
    if (value === "existing_and_future") {
      return {
      title: "Base atual e novos eventos",
      copy: "Ao ativar a automação, ela também avalia leads que já atendem às condições agora.",
      secondaryTitle: "Somente novos eventos",
      secondaryCopy: "Nesta opção alternativa, a automação acompanha apenas eventos futuros."
      }
    }

    return {
      title: "Somente novos eventos",
      copy: "Ao ativar a automação, ela acompanha apenas leads que atenderem às condições depois da ativação.",
      secondaryTitle: "Base atual e novos eventos",
      secondaryCopy: "Nesta opção alternativa, a automação também avalia leads que já atendem às condições agora."
    }
  }

  buildNode(type) {
    const id = `${type}_${Date.now()}`
    const defaults = {
      entry: { label: "Quando observar", config: { trigger: "lead_created", entry_policy: "future" } },
      wait: { label: "Espera", config: { mode: "duration", amount: "1", unit: "days", skip_weekends: true } },
      await_event: { label: "Aguardar evento", config: { trigger: "whatsapp_received", timeout_amount: "1", timeout_unit: "days" } },
      action: { label: "Intervenção", config: { action_type: "create_task", message: "" } },
      condition: { label: "Condição", config: { operator: "and", summary: "" } }
    }[type] || { label: "Bloco", config: {} }

    return { id, type, label: defaults.label, config: defaults.config }
  }

  selectedNode() {
    return this.definition.nodes.find((node) => node.id === this.selectedNodeId)
  }

  sync() {
    this.definitionTarget.value = JSON.stringify(this.definition)
  }

  buildLinearEdges() {
    return this.definition.nodes.slice(0, -1).map((node, index) => ({
      from: node.id,
      to: this.definition.nodes[index + 1].id
    }))
  }

  insertNodeAfter(afterId, node, mode = "sequential") {
    const afterIndex = this.definition.nodes.findIndex((item) => item.id === afterId)
    const insertIndex = afterIndex >= 0 ? afterIndex + 1 : this.definition.nodes.length
    this.definition.nodes.splice(insertIndex, 0, node)

    if (!afterId) return

    const outgoing = this.outgoingEdges(afterId)
    if (mode === "parallel") {
      this.addEdge(afterId, node.id)
      return
    }

    this.definition.edges = this.definition.edges.filter((edge) => edge.from !== afterId)
    this.addEdge(afterId, node.id)
    outgoing.forEach((edge) => {
      if (edge.to !== node.id) this.addEdge(node.id, edge.to)
    })
  }

  addEdge(from, to) {
    if (!from || !to || from === to) return
    if (this.definition.edges.some((edge) => edge.from === from && edge.to === to)) return

    this.definition.edges.push({ from, to })
  }

  incomingEdges(nodeId) {
    return (this.definition.edges || []).filter((edge) => edge.to === nodeId)
  }

  outgoingEdges(nodeId) {
    return (this.definition.edges || []).filter((edge) => edge.from === nodeId)
  }

  nextNodeIds(nodeId) {
    return this.outgoingEdges(nodeId).map((edge) => edge.to)
  }

  nodeById(nodeId) {
    return this.definition.nodes.find((node) => node.id === nodeId)
  }

  workflowLevels() {
    const entry = this.definition.nodes.find((node) => node.type === "entry") || this.definition.nodes[0]
    if (!entry) return []

    const levels = []
    const visited = new Set()
    let currentIds = [entry.id]

    while (currentIds.length > 0 && levels.length < 24) {
      const columnNodes = currentIds
        .map((id) => this.nodeById(id))
        .filter(Boolean)
        .filter((node) => !visited.has(node.id))

      if (columnNodes.length === 0) break

      levels.push(columnNodes)
      columnNodes.forEach((node) => visited.add(node.id))

      const nextIds = []
      columnNodes.forEach((node) => {
        this.nextNodeIds(node.id).forEach((id) => {
          if (!visited.has(id) && !nextIds.includes(id)) nextIds.push(id)
        })
      })
      currentIds = this.sortNodeIdsByDefinitionOrder(nextIds)
    }

    const unvisited = this.definition.nodes.filter((node) => !visited.has(node.id))
    if (unvisited.length > 0) levels.push(unvisited)

    return levels
  }

  sortNodeIdsByDefinitionOrder(ids) {
    return [...ids].sort((left, right) => {
      return this.definition.nodes.findIndex((node) => node.id === left) - this.definition.nodes.findIndex((node) => node.id === right)
    })
  }

  reorderNodeNear(nodeId, targetId, position) {
    const nodeIndex = this.definition.nodes.findIndex((node) => node.id === nodeId)
    const targetIndex = this.definition.nodes.findIndex((node) => node.id === targetId)
    if (nodeIndex < 0 || targetIndex < 0 || nodeIndex === targetIndex) return

    const [node] = this.definition.nodes.splice(nodeIndex, 1)
    const freshTargetIndex = this.definition.nodes.findIndex((item) => item.id === targetId)
    this.definition.nodes.splice(position === "before" ? freshTargetIndex : freshTargetIndex + 1, 0, node)
  }

  normalizeDefinition(definition) {
    const normalized = definition && typeof definition === "object" ? definition : this.defaultDefinition()
    normalized.nodes = Array.isArray(normalized.nodes) ? normalized.nodes : []
    normalized.edges = Array.isArray(normalized.edges) ? normalized.edges : []
    normalized.viewport = normalized.viewport || { x: 0, y: 0, zoom: 1 }

    const exitIds = normalized.nodes.filter((node) => node?.type === "exit").map((node) => node.id)
    normalized.nodes = normalized.nodes.filter((node) => node?.type !== "exit")
    normalized.edges = normalized.edges.filter((edge) => !exitIds.includes(edge?.from) && !exitIds.includes(edge?.to))

    if (!normalized.nodes.some((node) => node?.type === "entry")) {
      normalized.nodes.unshift(this.buildNode("entry"))
    }

    this.definition = normalized
    if (this.definition.edges.length === 0 && this.definition.nodes.length > 1) {
      this.definition.edges = this.buildLinearEdges()
    }
    return normalized
  }

  lastInsertAnchorId() {
    return this.definition.nodes[this.definition.nodes.length - 1]?.id
  }

  parseJson(raw, fallback) {
    try {
      return JSON.parse(raw)
    } catch (_error) {
      return fallback
    }
  }

  defaultDefinition() {
    return {
      schema_version: 1,
      nodes: [this.buildNode("entry")],
      edges: [],
      viewport: { x: 0, y: 0, zoom: 1 }
    }
  }

  nodeTitle(node) {
    return {
      entry: "Quando observar",
      wait: "Espera",
      await_event: "Aguardar evento",
      action: "Intervenção",
      condition: "Condição"
    }[node.type] || "Etapa"
  }

  nodeIcon(node) {
    return {
      entry: "bi-people-fill",
      wait: "bi-clock-fill",
      await_event: "bi-broadcast-pin",
      action: "bi-lightning-charge-fill",
      condition: "bi-signpost-split-fill"
    }[node.type] || "bi-square-fill"
  }

  actionIcon(actionType) {
    return {
      create_task: "bi-check2-square",
      send_whatsapp: "bi-whatsapp",
      send_whatsapp_template: "bi-chat-square-text",
      move_stage: "bi-arrow-right-circle",
      assign_agent: "bi-person-x",
      add_note: "bi-journal-text",
      create_interest_curation_task: "bi-house-heart",
      add_interest_note: "bi-stars",
      suggest_matching_properties: "bi-building-check",
      notify_broker_interest_opportunity: "bi-bell",
      prepare_matching_properties_whatsapp: "bi-whatsapp",
      generate_interest_ai_summary: "bi-magic"
    }[actionType] || "bi-lightning-charge"
  }

  actionDescription(actionType) {
    return {
      create_task: "Cria uma tarefa para o time acompanhar o lead no prazo definido.",
      send_whatsapp: "Envia uma mensagem livre pelo WhatsApp quando a etapa chegar aqui.",
      send_whatsapp_template: "Dispara um modelo WhatsApp aprovado e reutilizável.",
      move_stage: "Atualiza a etapa operacional do lead como apoio ao acompanhamento.",
      assign_agent: "Ação vertical legada. Use Distribuição de Leads para responsável, fila e aceite.",
      add_note: "Registra uma nota interna no histórico do lead.",
      create_interest_curation_task: "Cria uma tarefa para o responsável do lead curar imóveis aderentes ao perfil.",
      add_interest_note: "Registra no histórico o perfil de interesse detectado pela navegação e pelos dados do lead.",
      suggest_matching_properties: "Busca imóveis compatíveis e registra sugestões para a operação revisar.",
      notify_broker_interest_opportunity: "Cria uma tarefa de oportunidade para o responsável atual do lead.",
      prepare_matching_properties_whatsapp: "Prepara uma mensagem com imóveis sugeridos, respeitando revisão humana.",
      generate_interest_ai_summary: "Gera classificação frio, morno ou quente com resumo inteligente do interesse."
    }[actionType] || "Executa uma intervenção automática no lead."
  }

  actionBadge(actionType) {
    return {
      create_task: "tarefa",
      send_whatsapp: "mensagem",
      send_whatsapp_template: "modelo",
      move_stage: "etapa",
      add_note: "histórico",
      create_interest_curation_task: "curadoria",
      add_interest_note: "interesse",
      suggest_matching_properties: "match",
      notify_broker_interest_opportunity: "alerta",
      prepare_matching_properties_whatsapp: "revisão",
      generate_interest_ai_summary: "IA"
    }[actionType]
  }

  nodeSummary(node) {
    if (node.type === "entry") {
      const trigger = this.catalog.triggers?.[node.config?.trigger] || "Selecione o evento observado"
      const eventSummary = this.entryEventSummary(node)
      return eventSummary ? `${trigger} · ${eventSummary}` : trigger
    }
    if (node.type === "wait") return this.waitSummary(node)
    if (node.type === "await_event") {
      const trigger = this.catalog.triggers?.[node.config?.trigger] || "evento"
      return `${trigger} ou timeout de ${node.config?.timeout_amount || 1} ${this.unitLabel(node.config?.timeout_unit)}`
    }
    if (node.type === "action") {
      const label = this.actionLabel(node.config?.action_type) || "Selecione a intervenção"
      return this.endsFlow(node) ? `${label} · encerra acompanhamento` : label
    }
    if (node.type === "condition") return node.config?.operator === "or" ? "OU - pelo menos um criterio" : "E - todos os criterios"
    return ""
  }

  entryEventSummary(node) {
    if (node.config?.trigger === "lead_stage_changed") {
      const from = node.config?.from_stage || "qualquer etapa"
      const to = node.config?.to_stage || "qualquer etapa"
      return `de ${from} para ${to}`
    }

    if (node.config?.trigger === "lead_created") {
      const parts = []
      if (node.config?.stage) parts.push(node.config.stage)
      if (node.config?.source) parts.push(node.config.source)
      return parts.join(" · ")
    }

    if (node.config?.trigger === "lead_idle") {
      const hours = node.config?.idle_hours || "48"
      const stage = node.config?.stage ? ` · ${node.config.stage}` : ""
      const source = node.config?.source ? ` · ${node.config.source}` : ""
      return `${hours}h sem ação${stage}${source}`
    }

    if (node.config?.trigger === "scheduled_routine") {
      const frequency = {
        every_n_minutes: `a cada ${node.config?.interval || 60} min`,
        daily: `todo dia às ${node.config?.time_of_day || "09:00"}`,
        weekly: `semanalmente às ${node.config?.time_of_day || "09:00"}`,
        monthly: `mensalmente dia ${node.config?.month_day || 1}`
      }[node.config?.schedule_frequency || "every_n_minutes"]
      const stage = node.config?.stage ? ` · ${node.config.stage}` : ""
      const source = node.config?.source ? ` · ${node.config.source}` : ""
      return `${frequency}${stage}${source}`
    }

    if (node.config?.trigger === "whatsapp_received") {
      const parts = []
      if (node.config?.stage) parts.push(node.config.stage)
      if (node.config?.message_contains) parts.push(`contém "${node.config.message_contains}"`)
      if (node.config?.message_not_contains) parts.push(`não contém "${node.config.message_not_contains}"`)
      return parts.join(" · ")
    }

    if (this.proposalEvents().includes(node.config?.trigger)) {
      return node.config?.stage ? `lead em ${node.config.stage}` : ""
    }

    if (this.interestEvents().includes(node.config?.trigger)) {
      const parts = []
      if (node.config?.stage) parts.push(node.config.stage)
      if (node.config?.source) parts.push(node.config.source)
      if (node.config?.minimum_score && node.config?.trigger === "matching_property_found") parts.push(`score >= ${node.config.minimum_score}`)
      return parts.join(" · ")
    }

    return ""
  }

  endsFlow(node) {
    return node?.type === "action" && [true, "true", "1", 1].includes(node.config?.stop_flow)
  }

  unitLabel(unit) {
    return { minutes: "minuto(s)", hours: "hora(s)", days: "dia(s)" }[unit] || "dia(s)"
  }

  waitSummary(node) {
    const mode = node.config?.mode || "duration"

    if (mode === "datetime") return node.config?.run_at ? `até ${node.config.run_at}` : "até data/hora"
    if (mode === "business_duration") return `${node.config?.amount || 1} ${this.unitLabel(node.config?.unit)} em horário comercial`
    if (mode === "next_business_window") return "próxima janela comercial"

    return `${node.config?.amount || 1} ${this.unitLabel(node.config?.unit)}`
  }
}
