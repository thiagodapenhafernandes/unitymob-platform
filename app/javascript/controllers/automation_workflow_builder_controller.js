import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["definition", "canvas", "inspector", "inspectorTitle", "catalog", "aside"]

  connect() {
    this.catalog = this.parseJson(this.catalogTarget.textContent, { triggers: {}, actions: {}, statuses: {}, automation_stages: {}, sources: {}, brokers: {}, templates: {}, distribution_rules: {}, whatsapp_senders: [], whatsapp_flow_templates: [] })
    this.definition = this.normalizeDefinition(this.parseJson(this.definitionTarget.value, this.defaultDefinition()))
    this.selectedNodeId = this.definition.nodes?.[0]?.id
    this.webhookMapDraftRows = {}
    this.redrawConnections = this.redrawConnections.bind(this)
    this.restoreAsideWidth()
    window.addEventListener("resize", this.redrawConnections)
    this.sync()
    this.render()
    // Automação nova (só a entrada): o primeiro passo é escolher como ela começa.
    if (this.definition.nodes.length === 1) this.openDrawer()
  }

  disconnect() {
    window.removeEventListener("resize", this.redrawConnections)
    if (this.connectionsFrame) window.cancelAnimationFrame(this.connectionsFrame)
    this.stopResizeAside()
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
    const preset = event.currentTarget.dataset.preset
    const conversation = event.currentTarget.dataset.conversation
    const node = this.buildNode(type)

    if (node.type === "action" && actionType) {
      node.config.action_type = actionType
      node.label = this.catalog.actions?.[actionType] || node.label
      this.normalizeActionConfig(node, "action_type")
    }
    if (preset) this.applyStepPreset(node, preset)
    if (conversation) this.applyConversationDefaults(node, conversation)
    if (node.type === "action" && actionType === "transfer_to_attendant") {
      node.config.topic = node.config.topic || "Atendimento automático"
      node.config.distribution_rule_id = node.config.distribution_rule_id || this.defaultDistributionRuleId()
    }

    this.insertNodeAfter(this.pendingInsertion?.afterId, node, this.pendingInsertion?.mode || "sequential")
    if (conversation && conversation !== "template_buttons") this.scaffoldQuestion(node)
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

  startResizeAside(event) {
    if (!this.hasAsideTarget) return

    event.preventDefault()
    this.asideResizeState = {
      right: this.asideTarget.getBoundingClientRect().right
    }
    this.boundResizeAside = this.boundResizeAside || ((resizeEvent) => this.resizeAside(resizeEvent))
    this.boundStopResizeAside = this.boundStopResizeAside || (() => this.stopResizeAside())
    document.body.classList.add("automation-workflow-builder-resizing")
    window.addEventListener("pointermove", this.boundResizeAside)
    window.addEventListener("pointerup", this.boundStopResizeAside, { once: true })
    window.addEventListener("pointercancel", this.boundStopResizeAside, { once: true })
  }

  resizeAside(event) {
    if (!this.asideResizeState) return

    const width = this.asideResizeState.right - event.clientX
    this.setAsideWidth(width)
  }

  stopResizeAside() {
    if (this.boundResizeAside) window.removeEventListener("pointermove", this.boundResizeAside)
    if (this.boundStopResizeAside) {
      window.removeEventListener("pointerup", this.boundStopResizeAside)
      window.removeEventListener("pointercancel", this.boundStopResizeAside)
    }
    document.body.classList.remove("automation-workflow-builder-resizing")

    if (this.asideResizeState && this.hasAsideTarget) {
      const width = Number.parseInt(this.element.style.getPropertyValue("--automation-workflow-builder-aside-width"), 10)
      if (Number.isFinite(width)) this.storeAsideWidth(width)
    }
    this.asideResizeState = null
  }

  restoreAsideWidth() {
    const stored = Number.parseInt(window.localStorage?.getItem(this.asideWidthStorageKey()) || "", 10)
    if (Number.isFinite(stored)) this.setAsideWidth(stored, { persist: false })
  }

  setAsideWidth(width, { persist = true } = {}) {
    const nextWidth = this.clampAsideWidth(width)
    this.element.style.setProperty("--automation-workflow-builder-aside-width", `${nextWidth}px`)
    if (persist) this.storeAsideWidth(nextWidth)
  }

  storeAsideWidth(width) {
    window.localStorage?.setItem(this.asideWidthStorageKey(), String(this.clampAsideWidth(width)))
  }

  asideWidthStorageKey() {
    return "unitymob:automation-workflow-builder:aside-width"
  }

  clampAsideWidth(width) {
    const numeric = Number.isFinite(width) ? width : 390
    const max = Math.min(720, Math.max(340, window.innerWidth - 520))
    return Math.round(Math.min(max, Math.max(300, numeric)))
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
    this.scheduleConnectionsDraw()
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
    const value = event.currentTarget.type === "checkbox" ? event.currentTarget.checked : this.inputValue(event.currentTarget)

    if (field === "__start_category") {
      this.changeStartCategory(node, value)
      this.sync()
      this.render()
      return
    }

    if (field === "label") {
      node.label = value
    } else {
      node.config = node.config || {}
      node.config[field] = value
      if (node.type === "entry") {
        this.normalizeEntryConfigForTrigger(node)
        this.afterEntryChange(node, field)
      }
      if (node.type === "await_event") this.normalizeAwaitEventConfigForTrigger(node)
      if (node.type === "response_router" && field === "category") this.normalizeResponseRouterForCategory(node)
      if (node.type === "response_condition" && field === "category") this.normalizeResponseConditionForCategory(node)
      if (node.type === "action") this.normalizeActionConfig(node, field)
      if (node.type === "action" && field === "options" && node.config.scaffold) this.syncQuestionOptions(node)
    }

    this.sync()
    this.renderCanvas()
    this.refreshLiteralSummary()
    this.refreshValidity()
    if (event.currentTarget.tagName === "SELECT" || ["retry_enabled", "retry_question", "use_as_receptive"].includes(field)) this.renderInspector()
  }

  inputValue(input) {
    if (input.tagName === "SELECT" && input.multiple) {
      return Array.from(input.selectedOptions).map((option) => option.value).filter(Boolean)
    }

    return input.value
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

    // Anima só o que é novo (ou tudo na primeira pintura, em cascata); re-render por digitação não pisca.
    const firstPaint = !this.seenNodeIds
    const seen = this.seenNodeIds || new Set()
    const selectionChanged = this.lastCanvasSelectedId !== this.selectedNodeId
    this.lastCanvasSelectedId = this.selectedNodeId

    const layout = this.workflowLayout()
    layout.levels.forEach((nodes, index) => {
      const visibleNodes = nodes.filter(Boolean)
      const column = document.createElement("div")
      column.className = `automation-workflow-builder__column ${visibleNodes.length > 1 ? "automation-workflow-builder__column--parallel" : ""}`
      column.style.gridTemplateRows = `repeat(${layout.rowCount}, minmax(86px, auto))`

      nodes.forEach((node) => {
        const slot = document.createElement("div")
        slot.className = "automation-workflow-builder__slot"
        if (node) {
          const element = this.nodeElement(node, visibleNodes)
          if (!seen.has(node.id)) {
            element.classList.add("is-entering")
            element.style.setProperty("--enter-delay", `${firstPaint ? index * 70 : 0}ms`)
          } else if (selectionChanged && node.id === this.selectedNodeId) {
            element.classList.add("is-selected-pop")
          }
          slot.appendChild(element)
          if (!this.endsFlow(node)) slot.appendChild(this.inlineAddElement(node))
        } else {
          slot.classList.add("automation-workflow-builder__slot--empty")
        }
        column.appendChild(slot)
      })

      this.canvasTarget.appendChild(column)
      if (index < layout.levels.length - 1) this.canvasTarget.appendChild(this.connectorElement(layout, index))
    })

    this.seenNodeIds = new Set(this.definition.nodes.map((item) => item.id))
    this.applyCanvasZoom()
    this.scheduleConnectionsDraw()
  }

  renderInspector() {
    const node = this.selectedNode()
    this.inspectorTarget.replaceChildren()

    const swapKey = `${this.inspectorMode}:${node?.id || ""}`
    if (this.lastInspectorKey !== swapKey) {
      this.lastInspectorKey = swapKey
      this.inspectorTarget.classList.remove("is-swapping")
      void this.inspectorTarget.offsetWidth // reinicia a animação
      this.inspectorTarget.classList.add("is-swapping")
    }
    if (this.hasAsideTarget) this.asideTarget.dataset.tone = node ? this.nodeTone(node) : "entry"

    if (this.inspectorMode === "step_chooser") {
      this.inspectorTitleTarget.textContent = "Adicionar intervenção"
      this.inspectorTarget.appendChild(this.stepChooserPanel())
      return
    }

    this.inspectorTitleTarget.textContent = node ? this.nodeTitle(node) : "Acompanhamento"

    if (!node) return

    if (node.type === "entry") {
      this.renderEntryInspector(node)
      return
    }

    this.inspectorTarget.appendChild(this.blockToolbar(node))
    this.inspectorTarget.appendChild(this.field("Nome do bloco", "label", node.label || this.nodeTitle(node), "text", { required: true, maxlength: 80 }))
    this.inspectorTarget.appendChild(this.literalSummaryPanel(node))
    const buttonContext = this.buttonContextFor(node)
    if (buttonContext) this.inspectorTarget.appendChild(this.buttonContextPanel(buttonContext))

    if (node.type === "action") {
      if (node.config?.action_type) {
        this.inspectorTarget.appendChild(this.actionTypeSummary(node))
      } else {
        this.inspectorTarget.appendChild(this.selectField("Tipo de intervenção", "action_type", node.config?.action_type, this.actionOptionsFor(node), { placeholder: "Selecione a intervenção" }))
      }
      this.renderActionFields(node)
      this.inspectorTarget.appendChild(this.finalActionField(node))
    } else if (node.type === "wait") {
      this.renderWaitFields(node)
    } else if (node.type === "await_event") {
      this.renderAwaitEventFields(node)
    } else if (node.type === "await_whatsapp_response") {
      this.renderAwaitWhatsappResponseFields(node)
    } else if (node.type === "response_condition") {
      this.renderResponseConditionFields(node)
    } else if (node.type === "response_fallback") {
      this.renderResponseFallbackFields(node)
    } else if (node.type === "response_router") {
      this.renderResponseRouterFields(node)
    } else if (node.type === "condition") {
      this.inspectorTarget.appendChild(this.selectField("Operador", "operator", node.config?.operator, {
        and: "E - todos os criterios",
        or: "OU - pelo menos um criterio"
      }, { placeholder: "Selecione o operador" }))
      this.inspectorTarget.appendChild(this.selectField("Etapa do lead", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      this.inspectorTarget.appendChild(this.selectField("Origem do lead", "source", node.config?.source, { "": "Qualquer origem", ...this.catalog.sources }, { placeholder: "Qualquer origem" }))
      this.inspectorTarget.appendChild(this.field("Resumo dos criterios", "summary", node.config?.summary || ""))
    }

    this.refreshValidity()
  }

  // Cabeçalho do bloco: status (Pronto/Pendente) + duplicar + remover (confirmação em 2 cliques).
  blockToolbar(node) {
    const bar = document.createElement("div")
    bar.className = "automation-workflow-builder__block-toolbar"

    const status = document.createElement("span")
    status.className = "automation-workflow-builder__status"
    status.dataset.blockStatus = "true"
    status.setAttribute("role", "status")

    const actions = document.createElement("span")
    actions.className = "automation-workflow-builder__block-actions"

    const duplicate = document.createElement("button")
    duplicate.type = "button"
    duplicate.className = "automation-workflow-builder__icon-btn"
    duplicate.title = "Duplicar etapa em paralelo"
    duplicate.setAttribute("aria-label", "Duplicar etapa")
    duplicate.innerHTML = '<i class="bi bi-copy"></i>'
    duplicate.dataset.action = "automation-workflow-builder#duplicateNode"

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "automation-workflow-builder__icon-btn automation-workflow-builder__icon-btn--danger"
    remove.title = "Remover etapa"
    remove.setAttribute("aria-label", "Remover etapa")
    remove.innerHTML = '<i class="bi bi-trash"></i>'
    remove.addEventListener("click", (event) => {
      if (remove.dataset.confirm !== "true") {
        remove.dataset.confirm = "true"
        remove.classList.add("is-confirming")
        remove.innerHTML = '<i class="bi bi-trash"></i><span>Confirmar remoção</span>'
        remove.timer = setTimeout(() => {
          delete remove.dataset.confirm
          remove.classList.remove("is-confirming")
          remove.innerHTML = '<i class="bi bi-trash"></i>'
        }, 3500)
        return
      }
      clearTimeout(remove.timer)
      this.removeNode(event)
    })

    actions.append(duplicate, remove)
    bar.append(status, actions)
    return bar
  }

  duplicateNode(event) {
    event?.preventDefault()
    const node = this.selectedNode()
    const from = node && this.incomingEdges(node.id)[0]?.from
    if (!node || node.type === "entry" || !from) return

    const copy = JSON.parse(JSON.stringify(node))
    copy.id = this.uniqueNodeId(node.type)
    copy.label = `${node.label || this.nodeTitle(node)} (cópia)`
    this.insertNodeAfter(from, copy, "parallel")
    this.selectedNodeId = copy.id
    this.sync()
    this.render()
  }

  // Marca campos obrigatórios vazios e atualiza o selo do bloco sem recriar o inspector (mantém o foco).
  refreshValidity() {
    const controls = Array.from(this.inspectorTarget.querySelectorAll("[data-required]"))
    let pending = 0
    controls.forEach((control) => {
      const empty = String(control.value ?? "").trim() === ""
      if (empty) pending += 1
      control.closest(".automation-workflow-builder__field")?.classList.toggle("is-invalid", empty)
      control.setAttribute("aria-invalid", empty ? "true" : "false")
    })

    const status = this.inspectorTarget.querySelector("[data-block-status]")
    if (!status) return
    status.classList.toggle("is-pending", pending > 0)
    status.innerHTML = pending > 0
      ? `<i class="bi bi-exclamation-circle"></i>${pending === 1 ? "1 campo pendente" : `${pending} campos pendentes`}`
      : '<i class="bi bi-check-circle"></i>Pronto'
  }

  normalizeEntryConfigForTrigger(node) {
    const trigger = node.config?.trigger
    const keep = ["trigger", "entry_policy", "distribution_rule_ids"]

    if (trigger === "lead_stage_changed") keep.push("from_stage", "to_stage")
    if (trigger === "lead_created") keep.push("stage", "source")
    if (trigger === "lead_idle") keep.push("idle_hours", "stage", "source")
    if (trigger === "whatsapp_received") keep.push("stage", "message_contains", "message_not_contains")
    if (trigger === "whatsapp_flow_button") keep.push("whatsapp_sender_number_id", "whatsapp_template_id", "use_as_receptive")
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

  normalizeResponseRouterForCategory(node) {
    const category = node.config?.category || "template_buttons"
    const allowedFields = Object.keys(this.responseRouterFieldOptions(category))
    const fallbackField = allowedFields[0] || "message.body"
    this.responseRoutes(node).forEach((route) => {
      this.responseConditions(route).forEach((condition) => {
        if (!allowedFields.includes(condition.field)) condition.field = fallbackField
      })
    })
  }

  normalizeResponseConditionForCategory(node) {
    const category = node.config?.category || "template_buttons"
    const allowedFields = Object.keys(this.responseRouterFieldOptions(category))
    if (!allowedFields.includes(node.config?.field)) {
      node.config.field = this.defaultResponseField(category)
    }
  }

  normalizeActionConfig(node, changedField) {
    if (node.config?.action_type === "capture_answer") {
      this.normalizeCaptureConfig(node, changedField)
      return
    }

    if (node.config?.action_type === "send_whatsapp_template" && changedField === "template") this.afterTemplateChosen(node)

    if (node.config?.action_type === "set_flow_result") {
      if (changedField === "action_type") {
        node.config.result = node.config.result || "no_attendance"
      }
      if (node.config.result === "generates_attendance" && !node.config.distribution_rule_id) {
        node.config.distribution_rule_id = this.defaultDistributionRuleId()
      }
      if (node.config.result !== "generates_attendance") {
        delete node.config.distribution_rule_id
      }
      return
    }

    if (node.config?.action_type !== "update_lead_lifecycle") return
    if (changedField === "action_type") {
      node.config.lifecycle_action = node.config.lifecycle_action || "mark_no_interest"
      node.config.to = node.config.to || this.defaultLifecycleStage(node.config.lifecycle_action)
    }
    if (changedField === "lifecycle_action") {
      node.config.to = this.defaultLifecycleStage(node.config.lifecycle_action)
    }
  }

  // ----- Guardar resposta do cliente -----
  captureOperatorFor(type) {
    return { email: "valid_email", phone: "valid_phone", number: "valid_number" }[type] || "present"
  }

  captureAnswerTypes() {
    return { text: "Texto livre", email: "E-mail", phone: "Telefone", number: "Número" }
  }

  captureTargetLabel(node) {
    const target = node.config?.lead_target
    if (target === "name") return "Nome"
    if (target === "email") return "E-mail"
    if (target === "custom") return node.config?.custom_label || node.config?.custom_key || "campo personalizado"
    return ""
  }

  normalizeCaptureConfig(node, changedField) {
    node.config = node.config || {}
    if (changedField === "action_type") {
      node.config.variable = node.config.variable || "resposta"
      node.config.answer_type = node.config.answer_type || "text"
      node.config.lead_target = node.config.lead_target || "none"
    }
    if (changedField === "answer_type") {
      const type = node.config.answer_type
      if (node.config.lead_target === "email" && type !== "email") node.config.lead_target = "none"
      if (node.config.lead_target === "name" && type !== "text") node.config.lead_target = "none"
    }
    if (changedField === "variable") node.config.variable = this.slugify(node.config.variable)
    this.syncCaptureCondition(node)
  }

  slugify(value) {
    return String(value || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 40)
  }

  // A condição que leva a este bloco valida o mesmo tipo de resposta (e-mail válido, telefone válido...).
  syncCaptureCondition(node) {
    this.incomingEdges(node.id).map((edge) => this.nodeById(edge.from)).filter((item) => item?.type === "response_condition" && item.config?.capture_path).forEach((condition) => {
      condition.config.operator = this.captureOperatorFor(node.config?.answer_type)
      condition.label = { email: "Se respondeu um e-mail válido", phone: "Se respondeu um telefone válido", number: "Se respondeu um número" }[node.config?.answer_type] || "Se respondeu"
    })
  }

  // Variáveis guardadas por blocos do fluxo, para oferecer em mensagens e notas.
  capturedVariables() {
    const seen = new Set()
    return this.definition.nodes
      .filter((node) => node.type === "action" && node.config?.action_type === "capture_answer" && node.config?.variable)
      .map((node) => node.config.variable)
      .filter((variable) => !seen.has(variable) && seen.add(variable))
  }

  renderCaptureFields(node) {
    const type = node.config?.answer_type || "text"
    const variable = node.config?.variable || ""
    this.inspectorTarget.appendChild(this.field("Nome da variável", "variable", variable, "text", {
      required: true,
      maxlength: 40,
      placeholder: "email",
      info: "Como esta resposta será chamada neste fluxo. Use {{resposta.nome_da_variavel}} nas mensagens, notas e webhook seguintes.",
      hint: variable ? `Para usar depois: {{resposta.${this.slugify(variable)}}}` : "Só letras, números e _ (ex.: email, bairro, orcamento)."
    }))
    this.inspectorTarget.appendChild(this.selectField("Tipo de resposta", "answer_type", type, this.captureAnswerTypes(), {
      required: true,
      placeholder: "Selecione o tipo",
      info: "A resposta é validada por este tipo. Se não for válida, o cliente é avisado e a pergunta se repete (veja o caminho \"Não entendi\")."
    }))

    const targets = { none: "Só guardar neste fluxo" }
    if (type === "text") targets.name = "Nome do lead"
    if (type === "email") targets.email = "E-mail do lead"
    targets.custom = "Campo personalizado do lead"
    this.inspectorTarget.appendChild(this.selectField("Salvar também no cadastro do lead", "lead_target", node.config?.lead_target || "none", targets, {
      placeholder: "Só guardar neste fluxo",
      info: "Reaproveita os campos que o lead já tem. O valor anterior fica registrado na linha do tempo do lead."
    }))
    if (node.config?.lead_target === "custom") {
      this.inspectorTarget.appendChild(this.field("Nome do campo", "custom_key", node.config?.custom_key || "", "text", { required: true, maxlength: 40, placeholder: "bairro_de_interesse" }))
      this.inspectorTarget.appendChild(this.field("Rótulo exibido", "custom_label", node.config?.custom_label || "", "text", { maxlength: 60, placeholder: "Bairro de interesse" }))
    }
    this.inspectorTarget.appendChild(this.entryEventNotice("Telefone e número não substituem o telefone do lead: ficam na variável ou em um campo personalizado."))
  }

  // ----- Template com botões no meio do fluxo -----
  flowTemplateByName(name) {
    return (this.catalog.whatsapp_flow_templates || []).find((template) => template.name === name) || null
  }

  // Template cujo menu uma etapa está tratando: o enviado mais perto acima dela (ou o do início).
  templateForNode(node) {
    const visited = new Set()
    const queue = [node.id]
    while (queue.length) {
      const id = queue.shift()
      if (visited.has(id)) continue
      visited.add(id)
      const current = this.nodeById(id)
      if (current?.type === "action" && current.config?.action_type === "send_whatsapp_template") {
        const template = this.flowTemplateByName(current.config.template)
        if (template) return template
      }
      if (current?.type === "entry") return this.entryTemplate()
      this.incomingEdges(id).forEach((edge) => queue.push(edge.from))
    }
    return null
  }

  templateButtonPaths(template) {
    const conditions = template.scaffold.nodes.filter((item) => item.type === "response_condition")
    const replies = template.scaffold.nodes.filter((item) => item.type === "action")
    const clone = (value) => JSON.parse(JSON.stringify(value))
    return conditions.map((condition, index) => [
      this.buildUniqueNode("response_condition", condition.label, { ...clone(condition.config), option_path: true }),
      this.buildUniqueNode("action", replies[index]?.label || `Responder: ${condition.config.button_text}`, { ...clone(replies[index]?.config || { action_type: "send_whatsapp", message: "Obrigado!" }), default_reply: true })
    ])
  }

  // Ao escolher um template de botões num bloco "template e tratar botões", os caminhos nascem sozinhos.
  afterTemplateChosen(node) {
    const template = this.flowTemplateByName(node.config.template)
    if (!template || !node.config.template_flow || node.config.scaffold) return

    this.mapTemplateButtons(node, template)
  }

  mapTemplateButtons(node, template) {
    this.clearScaffold(node)
    this.scaffoldQuestion(node, { paths: this.templateButtonPaths(template) })
    node.config.template_scaffold_name = template.name
  }

  clearScaffold(node) {
    const created = new Set(node.config?.scaffold?.created || [])
    if (created.size) {
      this.definition.nodes = this.definition.nodes.filter((item) => !created.has(item.id))
      this.definition.edges = this.definition.edges.filter((edge) => !created.has(edge.from) && !created.has(edge.to))
    }
    delete node.config.scaffold
  }

  renderTemplateActionFields(node) {
    const flowTemplates = this.catalog.whatsapp_flow_templates || []
    const options = node.config?.template_flow ? Object.fromEntries(flowTemplates.map((template) => [template.name, template.name])) : this.catalog.templates
    this.inspectorTarget.appendChild(this.selectField("Modelo WhatsApp", "template", node.config?.template, options, {
      placeholder: "Selecione o modelo",
      required: true,
      emptyHint: { message: "Nenhum modelo com botões de resposta aprovado.", href: "/admin/whatsapp/templates", linkLabel: "Cadastrar modelo" }
    }))

    const template = this.flowTemplateByName(node.config?.template)
    if (!template) {
      if (node.config?.template) this.inspectorTarget.appendChild(this.entryEventNotice("Este modelo não tem botões de resposta: ele é enviado e o fluxo segue em frente."))
      return
    }

    this.inspectorTarget.appendChild(this.templatePreview(template))
    this.inspectorTarget.appendChild(this.templateMappingControl(node, template))
  }

  templateMappingControl(node, template) {
    const mapped = Boolean(node.config?.scaffold)
    const stale = mapped && node.config.template_scaffold_name && node.config.template_scaffold_name !== template.name
    const wrap = document.createElement("div")
    wrap.className = "automation-workflow-builder__field"

    const note = mapped
      ? (stale ? `Os caminhos abaixo são do modelo “${node.config.template_scaffold_name}”. Refaça para usar os botões deste.` : "Cada botão do modelo virou um caminho abaixo. Escolha o que acontece em cada um.")
      : "Crie um caminho para cada botão do modelo: o fluxo espera o clique e segue por ele."
    wrap.appendChild(this.entryEventNotice(note))

    const button = document.createElement("button")
    button.type = "button"
    button.className = "automation-workflow-builder__options-add"
    const label = mapped ? "Refazer caminhos pelos botões do modelo" : "Criar um caminho para cada botão"
    button.innerHTML = `<i class="bi bi-diagram-3"></i>${label}`
    button.addEventListener("click", () => {
      if (mapped && button.dataset.confirm !== "true") {
        button.dataset.confirm = "true"
        button.innerHTML = '<i class="bi bi-exclamation-triangle"></i>Descarta os caminhos atuais. Clique para confirmar'
        button.timer = setTimeout(() => { delete button.dataset.confirm; button.innerHTML = `<i class="bi bi-diagram-3"></i>${label}` }, 4000)
        return
      }
      clearTimeout(button.timer)
      this.mapTemplateButtons(node, template)
      this.sync()
      this.render()
    })
    wrap.appendChild(button)
    return wrap
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
    button.dataset.tone = this.nodeTone(node)

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

    if (anchor?.type === "await_whatsapp_response") {
      this.appendStepChooserGroup(panel, "Modelos de caminho", "Atalhos para as respostas mais comuns do WhatsApp.", [
        { type: "response_condition", icon: "bi-menu-button-wide", title: "Botão: Saiba mais", copy: "Segue quando o lead clicar no botão Saiba mais.", preset: "button_more" },
        { type: "response_condition", icon: "bi-hand-thumbs-down", title: "Botão: Não tenho interesse", copy: "Segue quando o lead clicar no botão de desinteresse.", preset: "button_not_interest" },
        { type: "response_condition", icon: "bi-person-headset", title: "Pediu atendimento humano", copy: "Segue quando o texto indicar pedido de atendimento.", preset: "human_help" },
        { type: "response_fallback", icon: "bi-hourglass-split", title: "Sem resposta até timeout", copy: "Caminho para quando o prazo vencer sem resposta.", preset: "timeout_fallback" },
        { type: "response_fallback", icon: "bi-question-diamond", title: "Resposta não reconhecida", copy: "Caminho para respostas fora do padrão esperado.", preset: "unknown_fallback" }
      ])
      this.appendStepChooserGroup(panel, "Caminhos de resposta", "Use caminhos paralelos para deixar a decisão visível no canvas.", [
        { type: "response_condition", icon: "bi-ui-checks-grid", title: "Condição de resposta", copy: "Segue este caminho quando botão, texto, guardrail ou status casar." },
        { type: "response_fallback", icon: "bi-signpost-2", title: "Fallback de resposta", copy: "Segue quando não houver resposta ou quando nenhuma condição reconhecer a resposta." }
      ])
    }

    this.appendStepChooserGroup(panel, "Operação", "Tarefas e registros internos para organizar o atendimento.", this.actionStepOptions(["set_flow_result", "create_task", "add_note", "move_stage", "update_lead_lifecycle"]))
    this.appendStepChooserGroup(panel, "Conversa com o cliente", "Pergunte, deixe o cliente escolher e passe para um atendente quando precisar.", [
      ...this.actionStepOptions(["send_whatsapp_buttons", "send_whatsapp_list"]).map((option) => ({ ...option, conversation: option.actionType === "send_whatsapp_list" ? "list" : "buttons" })),
      { type: "action", actionType: "send_whatsapp", conversation: "text", icon: "bi-chat-left-text", title: "Perguntar com resposta livre", copy: "Envia uma pergunta e segue quando o cliente responder com qualquer texto.", badge: "pergunta" },
      ...(this.catalog.whatsapp_flow_templates?.length ? [{ type: "action", actionType: "send_whatsapp_template", conversation: "template_buttons", icon: "bi-layout-text-window-reverse", title: "Enviar template e tratar botões", copy: "Escolha um template aprovado: cada botão dele vira um caminho, com o preview ao lado.", badge: "template" }] : []),
      ...this.actionStepOptions(["transfer_to_attendant"])
    ])
    this.appendStepChooserGroup(panel, "Capturar dados", "Guarde o que o cliente responde para usar no fluxo e no cadastro do lead.", [
      { type: "action", actionType: "send_whatsapp", conversation: "capture", icon: "bi-input-cursor-text", title: "Perguntar e guardar resposta", copy: "Pergunta, valida (e-mail, telefone, número ou texto), repete se estiver errado e guarda a resposta.", badge: "dados" },
      ...this.actionStepOptions(["capture_answer"])
    ])
    this.appendStepChooserGroup(panel, "Comunicação", "Mensagens enviadas ao lead durante a jornada.", this.actionStepOptions(["send_whatsapp", "send_whatsapp_template"]))
    this.appendStepChooserGroup(panel, "Integrações", "Saídas técnicas para sistemas externos.", this.actionStepOptions(["send_webhook"]))
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
      { type: "await_whatsapp_response", icon: "bi-whatsapp", title: "Aguardar resposta WhatsApp", copy: "Espera a próxima resposta do lead e libera caminhos condicionais no canvas." },
      { type: "response_condition", icon: "bi-ui-checks-grid", title: "Condição de resposta", copy: "Continua apenas se a resposta recebida casar com botão, texto, guardrail ou status." },
      { type: "response_fallback", icon: "bi-signpost-2", title: "Fallback de resposta", copy: "Caminho visual para timeout ou resposta fora do padrão." },
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

    group.dataset.tone = this.nodeTone({ type: options[0].type, config: { action_type: options[0].actionType } })

    options.forEach((option, index) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "automation-workflow-builder__step-option"
      button.dataset.action = "automation-workflow-builder#chooseStep"
      button.dataset.type = option.type
      button.dataset.tone = this.nodeTone({ type: option.type, config: { action_type: option.actionType } })
      button.style.setProperty("--i", index)
      button.dataset.searchText = this.normalizedSearchText([option.title, option.copy, option.badge].filter(Boolean).join(" "))
      if (option.actionType) button.dataset.actionType = option.actionType
      if (option.preset) button.dataset.preset = option.preset
      if (option.conversation) button.dataset.conversation = option.conversation

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

  // ----- Perguntas: uma etapa de pergunta cria sozinha "aguardar resposta" + um caminho por opção -----
  questionOptions(node) {
    return String(node.config?.options || "").split(/\r?\n/).map((line) => line.trim()).filter(Boolean).filter((line, index, all) => all.indexOf(line) === index)
  }

  applyConversationDefaults(node, kind) {
    if (kind === "buttons") {
      node.label = "Perguntar com botões"
      node.config = { ...node.config, action_type: "send_whatsapp_buttons", message: "Como podemos ajudar?", options: "Sim\nNão" }
    } else if (kind === "list") {
      node.label = "Perguntar com lista"
      node.config = { ...node.config, action_type: "send_whatsapp_list", message: "Escolha uma opção:", list_button: "Ver opções", options: "Opção 1\nOpção 2\nOpção 3" }
    } else if (kind === "capture") {
      node.label = "Perguntar e guardar resposta"
      node.config = { ...node.config, action_type: "send_whatsapp", message: "Qual é o seu e-mail?", ask_free_text: true, capture: true }
    } else if (kind === "template_buttons") {
      node.label = "Enviar template e tratar botões"
      node.config = { ...node.config, action_type: "send_whatsapp_template", template_flow: true }
    } else {
      node.label = "Perguntar (resposta livre)"
      node.config = { ...node.config, action_type: "send_whatsapp", message: "Qual é a sua dúvida?", ask_free_text: true }
    }
  }

  uniqueNodeId(type) {
    this.nodeSeq = (this.nodeSeq || 0) + 1
    return `${type}_${Date.now()}_${this.nodeSeq}`
  }

  buildUniqueNode(type, label, config) {
    const node = this.buildNode(type)
    node.id = this.uniqueNodeId(type)
    node.label = label
    node.config = { ...node.config, ...config }
    return node
  }

  optionCondition(option) {
    return this.buildUniqueNode("response_condition", `Se resposta: ${option}`, {
      category: "template_buttons", field: "interaction.button_text", operator: "equals", value: option, option_path: true
    })
  }

  optionReply(option) {
    return this.buildUniqueNode("action", `Responder: ${option}`, {
      action_type: "send_whatsapp", message: `Perfeito! Você escolheu “${option}”. Edite esta mensagem e continue a conversa.`, default_reply: true
    })
  }

  // Insere um bloco numa posição da lista (a ordem da lista define a ordem dos caminhos no canvas) e liga a origem.
  attachNode(node, fromId, atIndex) {
    this.definition.nodes.splice(atIndex, 0, node)
    this.addEdge(fromId, node.id)
    return atIndex + 1
  }

  // Cria: pergunta -> aguardar resposta -> um caminho por opção (+ "não entendi" e "sem resposta").
  scaffoldQuestion(question, { paths: overridePaths = null } = {}) {
    const existingIds = new Set(this.definition.nodes.map((node) => node.id))
    const wait = this.buildUniqueNode("await_whatsapp_response", "Aguardar resposta", { timeout_amount: "2", timeout_unit: "hours" })
    this.insertNodeAfter(question.id, wait, "sequential")
    let at = this.definition.nodes.findIndex((node) => node.id === wait.id) + 1

    const options = question.config.ask_free_text ? [] : this.questionOptions(question)
    const paths = overridePaths || (question.config.capture ? [this.capturePath()] : options.length ? options.map((option) => [this.optionCondition(option), this.optionReply(option)]) : [[
      this.buildUniqueNode("response_condition", "Se respondeu", { category: "lead_text", field: "message.body", operator: "present", value: "", option_path: true }),
      this.buildUniqueNode("action", "Responder", { action_type: "send_whatsapp", message: "Obrigado! Edite esta mensagem e continue a conversa.", default_reply: true })
    ]])
    const ids = []
    paths.forEach((chain) => {
      let from = wait.id
      chain.forEach((node) => {
        at = this.attachNode(node, from, at)
        from = node.id
      })
      ids.push(chain[0].id)
    })

    const unknown = this.buildUniqueNode("response_fallback", "Não entendi (repete a pergunta)", { fallback_type: "no_match", retry_question: true, max_attempts: "2" })
    const unknownReply = this.buildUniqueNode("action", "Avisar que não entendeu", { action_type: "send_whatsapp", message: "Não entendi sua resposta. Vou perguntar de novo.", default_reply: true })
    at = this.attachNode(unknown, wait.id, at)
    at = this.attachNode(unknownReply, unknown.id, at)

    const exhausted = this.buildUniqueNode("response_fallback", "Depois de 2 tentativas", { fallback_type: "exhausted" })
    const exhaustedReply = this.buildUniqueNode("action", "Avisar que vai chamar alguém", { action_type: "send_whatsapp", message: "Vou chamar um atendente para te ajudar.", default_reply: true })
    at = this.attachNode(exhausted, wait.id, at)
    at = this.attachNode(exhaustedReply, exhausted.id, at)
    const queueId = this.defaultDistributionRuleId()
    if (queueId) {
      const handoff = this.buildUniqueNode("action", "Passar para atendente", { action_type: "transfer_to_attendant", distribution_rule_id: queueId, topic: "Atendimento automático", default_reply: true })
      at = this.attachNode(handoff, exhaustedReply.id, at)
    }

    const timeout = this.buildUniqueNode("response_fallback", "Sem resposta", { fallback_type: "timeout" })
    const timeoutReply = this.buildUniqueNode("action", "Lembrar o cliente", { action_type: "send_whatsapp", message: "Ainda posso te ajudar? É só responder por aqui.", default_reply: true })
    at = this.attachNode(timeout, wait.id, at)
    this.attachNode(timeoutReply, timeout.id, at)

    const created = this.definition.nodes.map((node) => node.id).filter((id) => !existingIds.has(id))
    question.config.scaffold = { wait: wait.id, options: ids, created }
  }

  // Pergunta que guarda a resposta: condição (tipo válido) -> guardar -> agradecer.
  capturePath() {
    return [
      this.buildUniqueNode("response_condition", "Se respondeu um e-mail válido", { category: "lead_text", field: "message.body", operator: "valid_email", value: "", option_path: true, capture_path: true }),
      this.buildUniqueNode("action", "Guardar resposta", { action_type: "capture_answer", variable: "email", answer_type: "email", lead_target: "email", default_reply: true }),
      this.buildUniqueNode("action", "Agradecer", { action_type: "send_whatsapp", message: "Obrigado! Anotei o seu e-mail: {{resposta.email}}", default_reply: true })
    ]
  }

  defaultReplyOf(conditionId) {
    return this.nextNodeIds(conditionId).map((id) => this.nodeById(id)).find((item) => item?.config?.default_reply)
  }

  // Ao editar as opções da pergunta, os caminhos acompanham (nome, valor e mensagem padrão; novos e removidos).
  syncQuestionOptions(question) {
    const scaffold = question.config.scaffold
    const options = this.questionOptions(question)
    const existing = (scaffold.options || []).map((id) => this.nodeById(id)).filter(Boolean)

    options.forEach((option, index) => {
      const condition = existing[index]
      if (condition) {
        condition.label = `Se resposta: ${option}`
        condition.config.value = option
        const reply = this.defaultReplyOf(condition.id)
        if (reply) {
          reply.label = `Responder: ${option}`
          reply.config.message = `Perfeito! Você escolheu “${option}”. Edite esta mensagem e continue a conversa.`
        }
        return
      }

      const last = existing[existing.length - 1]
      const anchorId = (last && (this.defaultReplyOf(last.id)?.id || last.id)) || scaffold.wait
      let at = this.definition.nodes.findIndex((node) => node.id === anchorId) + 1
      const created = this.optionCondition(option)
      at = this.attachNode(created, scaffold.wait, at)
      this.attachNode(this.optionReply(option), created.id, at)
      scaffold.options.push(created.id)
      existing.push(created)
    })

    existing.slice(options.length).forEach((condition) => {
      const removable = [condition, ...this.nextNodeIds(condition.id).map((id) => this.nodeById(id)).filter((item) => item?.config?.default_reply)]
      removable.forEach((item) => {
        this.definition.nodes = this.definition.nodes.filter((node) => node.id !== item.id)
        this.definition.edges = this.definition.edges.filter((edge) => edge.from !== item.id && edge.to !== item.id)
      })
      scaffold.options = scaffold.options.filter((id) => id !== condition.id)
    })
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

    if (node.type === "await_whatsapp_response") {
      wrapper.classList.add("automation-workflow-builder__inline-add--response")
      wrapper.appendChild(this.inlineTypedAddButton(node, "response_condition", "Condição", "bi-ui-checks-grid", "Adicionar condição de resposta"))
      wrapper.appendChild(this.inlineTypedAddButton(node, "response_fallback", "Fallback", "bi-signpost-2", "Adicionar fallback de resposta"))
      wrapper.appendChild(this.inlineAddButton(node, "parallel", "Mais opções", "bi-plus-lg"))
      return wrapper
    }

    wrapper.appendChild(this.inlineAddButton(node, "sequential", "Adicionar próxima etapa", "bi-plus-lg"))
    wrapper.appendChild(this.inlineAddButton(node, "parallel", "Adicionar caminho paralelo", "bi-diagram-2"))
    return wrapper
  }

  inlineTypedAddButton(node, type, label, icon, title) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "automation-workflow-builder__inline-add-choice"
    button.dataset.action = "automation-workflow-builder#addTypedNodeAfter"
    button.dataset.nodeId = node.id
    button.dataset.type = type
    button.title = title
    button.setAttribute("aria-label", title)
    button.innerHTML = `<i class="bi ${icon}"></i><span>${label}</span>`
    return button
  }

  addTypedNodeAfter(event) {
    if (event) event.preventDefault()

    const afterId = event.currentTarget.dataset.nodeId
    const type = event.currentTarget.dataset.type
    const node = this.buildNode(type)
    this.insertNodeAfter(afterId, node, "parallel")
    this.selectedNodeId = node.id
    this.openDrawer()
    this.sync()
    this.render()
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

  connectorElement(layout = { rowCount: 1, levels: [] }, levelIndex = 0) {
    const connector = document.createElement("div")
    connector.className = "automation-workflow-builder__connector"
    connector.style.gridTemplateRows = `repeat(${layout.rowCount || 1}, minmax(86px, auto))`

    for (let row = 0; row < (layout.rowCount || 1); row += 1) {
      const track = document.createElement("span")
      connector.appendChild(track)
    }

    return connector
  }

  scheduleConnectionsDraw() {
    if (this.connectionsFrame) window.cancelAnimationFrame(this.connectionsFrame)
    this.connectionsFrame = window.requestAnimationFrame(() => this.redrawConnections())
  }

  redrawConnections() {
    this.connectionsFrame = null
    if (!this.hasCanvasTarget) return

    this.canvasTarget.querySelector(".automation-workflow-builder__connections")?.remove()

    const edges = this.definition.edges || []
    if (edges.length === 0) return

    const width = Math.max(this.canvasTarget.scrollWidth, this.canvasTarget.offsetWidth)
    const height = Math.max(this.canvasTarget.scrollHeight, this.canvasTarget.offsetHeight)
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    svg.classList.add("automation-workflow-builder__connections")
    svg.setAttribute("width", width)
    svg.setAttribute("height", height)
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`)
    svg.setAttribute("aria-hidden", "true")

    const selectedPathNodeIds = this.selectedWorkflowPathNodeIds()

    edges.forEach((edge) => {
      const source = this.nodeConnectionElement(edge.from)
      const target = this.nodeConnectionElement(edge.to)
      if (!source || !target) return

      const from = this.connectionPoint(source, "right")
      const to = this.connectionPoint(target, "left")
      if (!from || !to) return

      const active = this.edgeInSelectedPath(edge, selectedPathNodeIds)
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
      path.setAttribute("d", this.connectionPath(from, to))
      path.setAttribute("class", this.connectionPathClass(active))
      svg.appendChild(path)

      const label = this.connectionLabel(edge)
      if (label) svg.appendChild(this.connectionLabelElement(label, from, to, active))
    })

    this.canvasTarget.prepend(svg)
  }

  nodeConnectionElement(nodeId) {
    return this.canvasTarget.querySelector(`.automation-workflow-builder__node-wrap[data-node-id="${this.escapeSelectorValue(nodeId)}"]`)
  }

  escapeSelectorValue(value) {
    const text = value?.toString() || ""
    if (window.CSS?.escape) return window.CSS.escape(text)

    return text.replace(/["\\]/g, "\\$&")
  }

  connectionPoint(element, side) {
    const position = this.elementPositionInsideCanvas(element)
    if (!position) return null

    return {
      x: side === "right" ? position.left + position.width : position.left,
      y: position.top + (position.height / 2)
    }
  }

  elementPositionInsideCanvas(element) {
    let left = 0
    let top = 0
    let current = element

    while (current && current !== this.canvasTarget) {
      left += current.offsetLeft || 0
      top += current.offsetTop || 0
      current = current.offsetParent
    }

    if (current !== this.canvasTarget) return null

    return {
      left,
      top,
      width: element.offsetWidth,
      height: element.offsetHeight
    }
  }

  connectionPath(from, to) {
    const gap = Math.max(42, Math.min(140, Math.abs(to.x - from.x) * 0.48))
    const c1x = from.x + gap
    const c2x = to.x - gap

    return `M ${from.x} ${from.y} C ${c1x} ${from.y}, ${c2x} ${to.y}, ${to.x} ${to.y}`
  }

  connectionPathClass(active) {
    return `automation-workflow-builder__connection${active ? " is-active" : ""}`
  }

  selectedWorkflowPathNodeIds() {
    if (!this.selectedNodeId) return new Set()

    const ids = new Set([this.selectedNodeId])
    this.collectConnectedNodeIds(this.selectedNodeId, ids, "incoming")
    this.collectConnectedNodeIds(this.selectedNodeId, ids, "outgoing")
    return ids
  }

  collectConnectedNodeIds(nodeId, ids, direction) {
    const edges = direction === "incoming" ? this.incomingEdges(nodeId) : this.outgoingEdges(nodeId)

    edges.forEach((edge) => {
      const nextId = direction === "incoming" ? edge.from : edge.to
      if (!nextId || ids.has(nextId)) return

      ids.add(nextId)
      this.collectConnectedNodeIds(nextId, ids, direction)
    })
  }

  edgeInSelectedPath(edge, selectedPathNodeIds) {
    return selectedPathNodeIds.has(edge.from) && selectedPathNodeIds.has(edge.to)
  }

  connectionLabel(edge) {
    const source = this.nodeById(edge.from)
    const target = this.nodeById(edge.to)
    if (!source || !target) return null

    if (["response_condition", "response_fallback"].includes(target.type)) {
      return this.shortConnectionLabel(target.label || this.nodeTitle(target))
    }

    if (this.outgoingEdges(source.id).length > 1) {
      return this.shortConnectionLabel(target.label || this.nodeTitle(target))
    }

    return null
  }

  shortConnectionLabel(value) {
    const label = value
      .toString()
      .replace(/^se\s+bot[aã]o:\s*/i, "")
      .replace(/^bot[aã]o:\s*/i, "")
      .replace(/^se\s+/i, "")
      .replace(/\s+/g, " ")
      .trim()

    if (!label) return null
    return label.length > 26 ? `${label.slice(0, 23).trim()}...` : label
  }

  connectionLabelElement(label, from, to, active) {
    const group = document.createElementNS("http://www.w3.org/2000/svg", "g")
    group.setAttribute("class", `automation-workflow-builder__connection-label${active ? " is-active" : ""}`)

    const distance = Math.abs(to.x - from.x)
    if (distance < 90) return group

    const x = to.x - Math.min(78, Math.max(42, distance * 0.22))
    const yOffset = to.y >= from.y ? -15 : 15
    const y = to.y + yOffset

    const text = document.createElementNS("http://www.w3.org/2000/svg", "text")
    text.setAttribute("x", x)
    text.setAttribute("y", y)
    text.setAttribute("text-anchor", "middle")
    text.textContent = label

    group.append(text)
    return group
  }

  field(label, field, value, type = "text", config = {}) {
    const wrap = document.createElement("label")
    wrap.className = "automation-workflow-builder__field"

    const input = document.createElement("input")
    input.className = "ax-input"
    input.type = type
    input.value = value || ""
    input.dataset.field = field
    input.dataset.action = "input->automation-workflow-builder#updateNode"
    if (config.placeholder) input.placeholder = config.placeholder
    if (config.min !== undefined) input.min = config.min
    if (config.max !== undefined) input.max = config.max
    if (config.maxlength) input.maxLength = config.maxlength

    wrap.append(this.fieldLabel(label, config.info, config.required), input)
    this.decorateControl(wrap, input, config)
    return wrap
  }

  // Recursos compartilhados por field/textArea/selectField: obrigatório, atalhos, variáveis, contador, dica.
  decorateControl(wrap, input, config = {}) {
    if (config.required) {
      input.dataset.required = "true"
      input.setAttribute("aria-required", "true")
    }

    if (config.presets?.length) wrap.appendChild(this.presetChips(input, config.presets, config.presetSuffix))
    if (config.variables) wrap.appendChild(this.variableChips(input))
    if (config.maxlength || config.counter) wrap.appendChild(this.characterCounter(input, config.maxlength))
    if (config.hint) {
      const hint = document.createElement("small")
      hint.className = "automation-workflow-builder__field-hint"
      hint.textContent = config.hint
      wrap.appendChild(hint)
    }
  }

  presetChips(input, presets, suffix = "") {
    const row = document.createElement("span")
    row.className = "automation-workflow-builder__chips"
    row.setAttribute("role", "group")
    row.setAttribute("aria-label", "Atalhos de valor")

    const buttons = presets.map(([text, value]) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "automation-workflow-builder__chip"
      button.textContent = text
      button.addEventListener("click", () => {
        input.value = value
        input.dispatchEvent(new Event("input", { bubbles: true }))
      })
      return [button, String(value)]
    })
    const markActive = () => buttons.forEach(([button, value]) => button.classList.toggle("is-active", input.value === value))
    input.addEventListener("input", markActive)
    markActive()

    row.append(...buttons.map(([button]) => button))
    if (suffix) {
      const unit = document.createElement("em")
      unit.textContent = suffix
      row.appendChild(unit)
    }
    return row
  }

  // Tokens suportados por Automation::ActionExecutor#render_text.
  variableChips(input) {
    const row = document.createElement("span")
    row.className = "automation-workflow-builder__chips automation-workflow-builder__chips--variables"
    row.setAttribute("role", "group")
    row.setAttribute("aria-label", "Inserir variável")

    ;[["Nome", "{{nome}}"], ["Corretor", "{{corretor}}"], ["Telefone", "{{telefone}}"], ["E-mail", "{{email}}"], ["Origem", "{{origem}}"]].forEach(([text, token]) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "automation-workflow-builder__chip"
      button.title = `Inserir ${token}`
      button.innerHTML = `<i class="bi bi-braces"></i>${this.escapeHtml(text)}`
      button.addEventListener("click", () => {
        const start = input.selectionStart ?? input.value.length
        const end = input.selectionEnd ?? input.value.length
        input.setRangeText(token, start, end, "end")
        input.focus()
        input.dispatchEvent(new Event("input", { bubbles: true }))
      })
      row.appendChild(button)
    })

    this.capturedVariables().forEach((variable) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "automation-workflow-builder__chip automation-workflow-builder__chip--captured"
      button.title = "Resposta guardada neste fluxo"
      button.innerHTML = `<i class="bi bi-input-cursor-text"></i>${this.escapeHtml(variable)}`
      button.addEventListener("click", () => {
        const token = `{{resposta.${variable}}}`
        const start = input.selectionStart ?? input.value.length
        const end = input.selectionEnd ?? input.value.length
        input.setRangeText(token, start, end, "end")
        input.focus()
        input.dispatchEvent(new Event("input", { bubbles: true }))
      })
      row.appendChild(button)
    })
    return row
  }

  characterCounter(input, limit) {
    const counter = document.createElement("small")
    counter.className = "automation-workflow-builder__counter"
    const update = () => {
      const size = input.value.length
      counter.textContent = limit ? `${size}/${limit}` : `${size} caracteres`
      counter.classList.toggle("is-over", Boolean(limit) && size > limit)
    }
    input.addEventListener("input", update)
    update()
    return counter
  }

  checkboxField(label, field, checked, help = "") {
    const wrap = document.createElement("label")
    wrap.className = "automation-workflow-builder__switch"

    const input = document.createElement("input")
    input.type = "checkbox"
    input.setAttribute("role", "switch")
    input.checked = [true, "true", "1", 1].includes(checked)
    input.dataset.field = field
    input.dataset.action = "change->automation-workflow-builder#updateNode"

    const track = document.createElement("span")
    track.className = "automation-workflow-builder__switch-track"
    track.setAttribute("aria-hidden", "true")

    const copy = document.createElement("span")
    copy.className = "automation-workflow-builder__switch-copy"
    copy.innerHTML = `<strong>${label}</strong>${help ? `<small>${help}</small>` : ""}`

    wrap.append(input, track, copy)
    return wrap
  }

  selectField(label, field, value, options, config = {}) {
    const wrap = document.createElement("label")
    wrap.className = `automation-workflow-builder__field ${config.compact ? "automation-workflow-builder__field--compact" : ""}`

    const select = document.createElement("select")
    select.className = "ax-select ax-autocomplete-select"
    select.dataset.controller = "tom-select"
    select.dataset.placeholder = config.placeholder || label
    select.dataset.tomSelectOptionsValue = JSON.stringify({
      searchField: ["text"]
    })
    select.dataset.field = field
    select.dataset.action = "change->automation-workflow-builder#updateNode"
    if (config.disabled) select.disabled = true

    // Chaves numéricas de objeto vêm antes de "" em JS: sem isto o placeholder ia para o fim e o 1º item parecia escolhido.
    const entries = Object.entries(options || {})
    const current = String(value ?? "")
    ;[...entries.filter(([key]) => key === ""), ...entries.filter(([key]) => key !== "")].forEach(([optionValue, optionLabel]) => {
      const option = document.createElement("option")
      option.value = optionValue
      option.textContent = optionLabel
      option.selected = String(optionValue) === current
      select.appendChild(option)
    })

    wrap.append(this.fieldLabel(label, config.info, config.required), select)
    if (config.required) select.dataset.required = "true"
    const hasOptions = Object.keys(options || {}).some((key) => key !== "")
    if (config.emptyHint && !hasOptions) wrap.appendChild(this.emptyOptionsNotice(config.emptyHint))
    return wrap
  }

  emptyOptionsNotice({ message, href, linkLabel }) {
    const notice = document.createElement("small")
    notice.className = "automation-workflow-builder__field-hint automation-workflow-builder__field-hint--warn"
    notice.innerHTML = `<i class="bi bi-exclamation-triangle"></i> ${this.escapeHtml(message)}`
    if (href) {
      const link = document.createElement("a")
      link.href = href
      link.target = "_blank"
      link.rel = "noopener"
      link.textContent = linkLabel || "Cadastrar"
      notice.append(" ", link)
    }
    return notice
  }

  multiSelectField(label, field, values, options, config = {}) {
    const wrap = document.createElement("label")
    wrap.className = `automation-workflow-builder__field ${config.compact ? "automation-workflow-builder__field--compact" : ""}`

    const select = document.createElement("select")
    select.className = "ax-select ax-autocomplete-select"
    select.multiple = true
    select.dataset.controller = "tom-select"
    select.dataset.placeholder = config.placeholder || label
    select.dataset.tomSelectOptionsValue = JSON.stringify({
      plugins: ["remove_button"],
      searchField: ["text"]
    })
    select.dataset.field = field
    select.dataset.action = "change->automation-workflow-builder#updateNode"

    const selectedValues = new Set(Array(values).map(String).filter(Boolean))
    Object.entries(options || {}).forEach(([optionValue, optionLabel]) => {
      const option = document.createElement("option")
      option.value = optionValue
      option.textContent = optionLabel
      option.selected = selectedValues.has(String(optionValue))
      select.appendChild(option)
    })

    wrap.append(this.fieldLabel(label, config.info), select)
    return wrap
  }

  fieldLabel(label, info = "", required = false) {
    const text = document.createElement("span")
    text.className = "automation-workflow-builder__field-label"

    const labelText = document.createElement("span")
    labelText.textContent = label
    text.appendChild(labelText)

    if (required) {
      const mark = document.createElement("b")
      mark.className = "automation-workflow-builder__required"
      mark.textContent = "*"
      mark.title = "Obrigatório"
      text.appendChild(mark)
    }

    if (info) {
      const help = document.createElement("button")
      help.type = "button"
      help.className = "automation-workflow-builder__field-info"
      help.dataset.controller = "ax-tooltip"
      help.dataset.axTooltipTextValue = info
      help.setAttribute("aria-label", `Ajuda: ${label}`)
      help.innerHTML = '<i class="bi bi-info-circle"></i>'
      text.appendChild(help)
    }

    return text
  }

  renderEntryEventFields(node, container = this.inspectorTarget) {
    if (node.config?.trigger === "scheduled_routine") {
      container.appendChild(this.selectField("Frequência", "schedule_frequency", node.config?.schedule_frequency, {
        every_n_minutes: "A cada intervalo",
        daily: "Todo dia",
        weekly: "Semanalmente",
        monthly: "Mensalmente"
      }, { placeholder: "Selecione a frequência" }))

      if ((node.config?.schedule_frequency || "every_n_minutes") === "every_n_minutes") {
        container.appendChild(this.field("Intervalo em minutos (mínimo 1)", "interval", node.config?.interval || "60", "number"))
      } else {
        container.appendChild(this.field("Horário", "time_of_day", node.config?.time_of_day || "09:00", "time"))

        if (node.config?.schedule_frequency === "weekly") {
          container.appendChild(this.selectField("Dia da semana", "weekdays", node.config?.weekdays, {
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
          container.appendChild(this.field("Dia do mês", "month_day", node.config?.month_day || "1", "number"))
        }
      }

      container.appendChild(this.selectField("Etapa atual", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      container.appendChild(this.selectField("Origem do lead", "source", node.config?.source, { "": "Qualquer origem", ...this.catalog.sources }, { placeholder: "Qualquer origem" }))
      container.appendChild(this.entryEventNotice("Rotinas agendadas rodam pelo monitor periódico da automação. Use filtros para limitar quais leads entram em cada execução."))
    } else if (node.config?.trigger === "lead_stage_changed") {
      container.appendChild(this.selectField("De etapa", "from_stage", node.config?.from_stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      container.appendChild(this.selectField("Para etapa", "to_stage", node.config?.to_stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      container.appendChild(this.entryEventNotice("A automação roda quando a mudança de etapa bater com esses critérios. Deixe em branco quando qualquer etapa servir."))
    } else if (node.config?.trigger === "lead_created") {
      container.appendChild(this.selectField("Etapa inicial", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      container.appendChild(this.selectField("Origem do lead", "source", node.config?.source, { "": "Qualquer origem", ...this.catalog.sources }, { placeholder: "Qualquer origem" }))
      container.appendChild(this.entryEventNotice("Use estes filtros quando a jornada deve iniciar apenas para leads criados em uma etapa ou origem específica."))
    } else if (node.config?.trigger === "lead_idle") {
      container.appendChild(this.field("Parado ha (horas)", "idle_hours", node.config?.idle_hours || "48", "number"))
      container.appendChild(this.selectField("Etapa atual", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      container.appendChild(this.selectField("Origem do lead", "source", node.config?.source, { "": "Qualquer origem", ...this.catalog.sources }, { placeholder: "Qualquer origem" }))
      container.appendChild(this.entryEventNotice("Lead parado é avaliado por rotina periódica. Etapa e origem filtram quais leads entram nessa observação."))
    } else if (node.config?.trigger === "whatsapp_received") {
      container.appendChild(this.selectField("Etapa atual", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      container.appendChild(this.field("Mensagem contem", "message_contains", node.config?.message_contains || ""))
      container.appendChild(this.field("Mensagem nao contem", "message_not_contains", node.config?.message_not_contains || ""))
      container.appendChild(this.entryEventNotice("O filtro usa o texto da mensagem recebida. Deixe os campos de texto vazios para aceitar qualquer resposta."))
    } else if (this.proposalEvents().includes(node.config?.trigger)) {
      container.appendChild(this.selectField("Etapa atual do lead", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      container.appendChild(this.entryEventNotice("Use este filtro quando a automação de proposta deve rodar somente para leads em uma etapa específica."))
    } else if (this.interestEvents().includes(node.config?.trigger)) {
      container.appendChild(this.selectField("Etapa atual", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, { placeholder: "Qualquer etapa" }))
      container.appendChild(this.selectField("Origem do lead", "source", node.config?.source, { "": "Qualquer origem", ...this.catalog.sources }, { placeholder: "Qualquer origem" }))
      if (node.config?.trigger === "matching_property_found") {
        container.appendChild(this.field("Score mínimo do imóvel", "minimum_score", node.config?.minimum_score || "65", "number"))
      }
      container.appendChild(this.entryEventNotice("Estes eventos vêm da Inteligência de Interesse: navegação pública, imóveis vistos, filtros usados e perfil real do lead após a conversão."))
    }
  }

  // Tipos de início: escolhidos antes do evento e das demais opções. A categoria é derivada do gatilho (não é salva).
  startCategories() {
    const categories = {
      lead: { label: "Lead", triggers: ["lead_created", "lead_stage_changed", "lead_assigned", "lead_idle"] },
      whatsapp: { label: "WhatsApp", triggers: ["whatsapp_flow_button", "whatsapp_received", ...Object.keys(this.catalog.triggers || {}).filter((key) => key.startsWith("whatsapp_campaign_"))] },
      proposal: { label: "Proposta", triggers: this.proposalEvents() },
      interest: { label: "Interesse em imóveis", triggers: this.interestEvents() },
      schedule: { label: "Rotina agendada", triggers: ["scheduled_routine"] }
    }
    const known = new Set(Object.values(categories).flatMap((item) => item.triggers))
    const others = Object.keys(this.catalog.triggers || {}).filter((key) => !known.has(key))
    if (others.length) categories.other = { label: "Outros", triggers: others }
    return categories
  }

  startCategoryOf(trigger) {
    const categories = this.startCategories()
    return Object.keys(categories).find((key) => categories[key].triggers.includes(trigger)) || "lead"
  }

  changeStartCategory(node, category) {
    const item = this.startCategories()[category]
    if (!item || item.triggers.includes(node.config?.trigger)) return

    node.config = node.config || {}
    node.config.trigger = item.triggers.find((key) => this.catalog.triggers?.[key]) || item.triggers[0]
    this.normalizeEntryConfigForTrigger(node)
    this.afterEntryChange(node, "trigger")
  }

  // Reações do início por botão: um único número já vem escolhido; trocar de número descarta template de outro WABA;
  // escolher o template monta o caminho por botão quando o canvas ainda só tem a entrada.
  afterEntryChange(node, field) {
    if (node.config?.trigger !== "whatsapp_flow_button") return

    const senders = this.catalog.whatsapp_senders || []
    if (field === "trigger" && !node.config.whatsapp_sender_number_id && senders.length === 1) {
      node.config.whatsapp_sender_number_id = String(senders[0].id)
    }
    if (field === "whatsapp_sender_number_id" && node.config.whatsapp_template_id &&
        !this.flowTemplatesFor(node).some((template) => String(template.id) === String(node.config.whatsapp_template_id))) {
      delete node.config.whatsapp_template_id
    }
    if (field === "whatsapp_template_id") {
      // Trocou de template: remapeia os botões sozinho se os caminhos ainda são os gerados (sem edição do usuário).
      if (this.definition.nodes.length > 1 && this.isPristineScaffold(node)) this.resetToEntry(node)
      this.applyTemplateScaffold(node)
    }
  }

  resetToEntry(entry) {
    this.definition.nodes = this.definition.nodes.filter((node) => node.id === entry.id)
    this.definition.edges = []
  }

  // true quando as etapas (fora a entrada) são idênticas ao scaffold de algum template: nada foi editado.
  isPristineScaffold(entry) {
    const rest = JSON.stringify(this.definition.nodes.filter((node) => node.id !== entry.id))
    return (this.catalog.whatsapp_flow_templates || []).some((template) =>
      JSON.stringify(template.scaffold.nodes.filter((node) => node.type !== "entry")) === rest
    )
  }

  flowTemplatesFor(node) {
    const sender = (this.catalog.whatsapp_senders || []).find((item) => String(item.id) === String(node.config?.whatsapp_sender_number_id))
    return (this.catalog.whatsapp_flow_templates || []).filter((template) => !sender?.waba_id || !template.waba_id || template.waba_id === sender.waba_id)
  }

  // Preview do template: HTML renderizado pelo servidor com a mesma partial de /admin/whatsapp/fluxos-resposta.
  templatePreview(template, activeKey = null) {
    const box = document.createElement("div")
    box.className = "automation-workflow-builder__template-preview"
    box.innerHTML = template.preview_html || ""
    if (activeKey) {
      box.classList.add("has-active-button")
      box.querySelectorAll("[data-button-key]").forEach((button) => button.classList.toggle("is-active", button.dataset.buttonKey === String(activeKey)))
    }
    return box
  }

  // Template + botão a que uma etapa pertence (a própria condição de botão ou a mais próxima acima dela).
  entryTemplate() {
    const entry = this.definition.nodes.find((item) => item.type === "entry")
    return (this.catalog.whatsapp_flow_templates || []).find((item) => String(item.id) === String(entry?.config?.whatsapp_template_id)) || null
  }

  buttonContextFor(node) {
    const template = this.templateForNode(node)
    if (!template || node.type === "entry") return null

    const visited = new Set()
    const queue = [node.id]
    while (queue.length) {
      const id = queue.shift()
      if (visited.has(id)) continue
      visited.add(id)
      const current = this.nodeById(id)
      if (current?.type === "response_condition" && current.config?.button_key) return { template, key: current.config.button_key, label: current.config.button_text }
      this.incomingEdges(id).forEach((edge) => queue.push(edge.from))
    }
    return null
  }

  buttonContextPanel(context) {
    const section = document.createElement("section")
    section.className = "automation-workflow-builder__button-context"
    section.innerHTML = `<small><i class="bi bi-hand-index"></i> Caminho do botão <strong>${this.escapeHtml(context.label || "")}</strong></small>`
    section.appendChild(this.templatePreview(context.template, context.key))
    return section
  }

  // Refaz os caminhos pelos botões do template atual (descarta as etapas existentes; confirma com 2º clique).
  remapButtonsControl(entry, template) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "automation-workflow-builder__options-add"
    button.innerHTML = '<i class="bi bi-arrow-repeat"></i>Refazer caminhos pelos botões do template'
    button.addEventListener("click", () => {
      if (button.dataset.confirm !== "true") {
        button.dataset.confirm = "true"
        button.innerHTML = '<i class="bi bi-exclamation-triangle"></i>Descarta as etapas atuais. Clique para confirmar'
        button.timer = setTimeout(() => {
          delete button.dataset.confirm
          button.innerHTML = '<i class="bi bi-arrow-repeat"></i>Refazer caminhos pelos botões do template'
        }, 4000)
        return
      }
      clearTimeout(button.timer)
      this.resetToEntry(entry)
      this.applyTemplateScaffold(entry)
      this.sync()
      this.render()
    })
    return button
  }

  applyTemplateScaffold(entry) {
    const template = (this.catalog.whatsapp_flow_templates || []).find((item) => String(item.id) === String(entry.config?.whatsapp_template_id))
    if (!template || this.definition.nodes.length > 1) return

    const scaffold = JSON.parse(JSON.stringify(template.scaffold))
    this.definition.nodes.push(...scaffold.nodes.filter((node) => node.type !== "entry"))
    this.definition.edges.push(...scaffold.edges.map((edge) => ({ ...edge, from: edge.from === "entry_1" ? entry.id : edge.from })))
  }

  // Inspector da entrada em passos, na ordem em que a decisão acontece. O que é raro fica recolhido no fim.
  renderEntryInspector(node) {
    const category = this.startCategoryOf(node.config?.trigger)
    const categories = this.startCategories()
    const steps = []
    const step = (title, ...children) => steps.push(this.entryStep(steps.length + 1, title, children))

    step("Fonte", this.selectField("Como esta automação começa?", "__start_category", category, Object.fromEntries(Object.entries(categories).map(([key, item]) => [key, item.label])), {
      placeholder: "Selecione o tipo de início",
      info: "Escolha primeiro a fonte; os próximos passos mudam de acordo com ela."
    }))

    const eventOptions = Object.fromEntries(categories[category].triggers.filter((key) => this.catalog.triggers?.[key]).map((key) => [key, this.catalog.triggers[key]]))
    const eventField = this.selectField(category === "whatsapp" ? "O que dispara?" : "Evento observado", "trigger", node.config?.trigger, eventOptions, { placeholder: "Selecione o evento" })

    if (node.config?.trigger === "whatsapp_flow_button") {
      step("Gatilho", eventField)
      this.whatsappFlowSteps(node).forEach((args) => step(...args))
    } else {
      const fields = document.createElement("div")
      this.renderEntryEventFields(node, fields)
      step(category === "whatsapp" ? "Gatilho" : "Evento", eventField, ...fields.children)
    }

    this.inspectorTarget.append(...steps)
    this.inspectorTarget.appendChild(this.entryStep(steps.length + 1, "Regras de distribuição", [this.distributionRuleChips(node)]))

    const advanced = document.createElement("details")
    advanced.className = "automation-workflow-builder__entry-advanced"
    advanced.innerHTML = "<summary><i class=\"bi bi-sliders\"></i><span>Política de entrada e nome do bloco</span></summary>"
    advanced.append(this.entryPolicyPanel(node), this.field("Nome do bloco", "label", node.label || this.nodeTitle(node)), this.literalSummaryPanel(node))
    this.inspectorTarget.appendChild(advanced)
  }

  // Filtro por regra de distribuição: chips clicáveis; nenhum marcado = vale para qualquer regra.
  distributionRuleChips(node) {
    const rules = Object.entries(this.catalog.distribution_rules || {})
    const wrap = document.createElement("div")
    wrap.className = "automation-workflow-builder__field"
    wrap.appendChild(this.fieldLabel("Limitar a leads destas regras", "Sem seleção, a automação vale para leads de qualquer regra de distribuição."))

    if (!rules.length) {
      wrap.appendChild(this.emptyOptionsNotice(this.noDistributionRulesHint()))
      return wrap
    }

    const selected = new Set(Array(node.config?.distribution_rule_ids || []).map(String))
    const row = document.createElement("div")
    row.className = "automation-workflow-builder__chips"
    row.setAttribute("role", "group")
    row.setAttribute("aria-label", "Regras de distribuição")
    const status = document.createElement("small")
    status.className = "automation-workflow-builder__field-hint"
    const refreshStatus = () => { status.textContent = selected.size ? `${selected.size} de ${rules.length} regras selecionadas` : "Vale para qualquer regra." }

    rules.forEach(([id, name]) => {
      const chip = document.createElement("button")
      chip.type = "button"
      chip.className = "automation-workflow-builder__chip"
      chip.textContent = name
      chip.setAttribute("aria-pressed", selected.has(String(id)))
      chip.classList.toggle("is-active", selected.has(String(id)))
      chip.addEventListener("click", () => {
        selected.has(String(id)) ? selected.delete(String(id)) : selected.add(String(id))
        chip.classList.toggle("is-active", selected.has(String(id)))
        chip.setAttribute("aria-pressed", selected.has(String(id)))
        node.config = node.config || {}
        node.config.distribution_rule_ids = Array.from(selected)
        this.sync()
        this.renderCanvas()
        this.refreshLiteralSummary()
        refreshStatus()
      })
      row.appendChild(chip)
    })
    refreshStatus()
    wrap.append(row, status)
    return wrap
  }

  entryStep(number, title, children) {
    const section = document.createElement("section")
    section.className = "automation-workflow-builder__step"

    const head = document.createElement("header")
    head.className = "automation-workflow-builder__step-head"
    head.innerHTML = `<span class="automation-workflow-builder__step-num">${number}</span><strong>${title}</strong>`

    const body = document.createElement("div")
    body.className = "automation-workflow-builder__step-body"
    body.append(...children)

    section.append(head, body)
    return section
  }

  // Passos do início por botão de template: número -> template do número (botões viram cartões) -> receptivo.
  whatsappFlowSteps(node) {
    const senders = this.catalog.whatsapp_senders || []
    if (!senders.length) {
      return [["Número de WhatsApp", this.entryEventNotice("Nenhum número de WhatsApp ativo. Conecte um número em Integrações › WhatsApp para começar por um template.")]]
    }

    if (!node.config?.whatsapp_sender_number_id && senders.length === 1) {
      node.config = node.config || {}
      node.config.whatsapp_sender_number_id = String(senders[0].id)
      this.sync()
    }

    const sender = senders.find((item) => String(item.id) === String(node.config?.whatsapp_sender_number_id))
    const senderOptions = { "": "Selecione o número", ...Object.fromEntries(senders.map((item) => [item.id, `${item.label} · ${item.phone}`])) }
    const steps = [["Número de WhatsApp", this.selectField("Número", "whatsapp_sender_number_id", node.config?.whatsapp_sender_number_id, senderOptions, { placeholder: "Selecione o número" })]]
    if (!sender) return steps

    const templates = this.flowTemplatesFor(node)
    if (!templates.length) {
      steps.push(["Receptivo", ...this.receptiveControls(node, sender, null)])
      steps.push(["Template", this.entryEventNotice("Este número não tem templates aprovados com botão de resposta.")])
      return steps
    }

    const templateOptions = { "": "Selecione o template", ...Object.fromEntries(templates.map((template) => [template.id, template.name])) }
    const chosen = templates.find((template) => String(template.id) === String(node.config?.whatsapp_template_id))
    const templateChildren = [this.selectField("Template deste número", "whatsapp_template_id", node.config?.whatsapp_template_id, templateOptions, { placeholder: "Selecione o template", required: this.booleanConfig(node.config?.use_as_receptive, false) })]
    if (chosen) {
      const buttons = chosen.scaffold.nodes.filter((item) => item.type === "response_condition").map((item) => item.config?.button_text).filter(Boolean)
      const next = this.definition.nodes.length > 1 ? "Se os caminhos não correspondem a estes botões, use “Refazer caminhos pelos botões do template”." : "Cada botão virou um cartão no canvas: escolha o que fazer com ele."
      templateChildren.push(this.entryEventNotice(`Botões: ${buttons.join(", ")}. ${next}`))
      templateChildren.push(this.templatePreview(chosen))
      if (this.definition.nodes.length > 1) templateChildren.push(this.remapButtonsControl(node, chosen))
    }
    steps.push(["Receptivo", ...this.receptiveControls(node, sender, chosen)])
    steps.push(["Template", ...templateChildren])

    return steps
  }

  // O switch fica sempre visível depois do número. Só trava quando há motivo (e o motivo aparece junto).
  receptiveControls(node, sender, template) {
    const owner = template?.existing_flow && template.existing_flow.workflow_id !== this.catalog.workflow_id ? template.existing_flow : null
    let blocked = ""
    if (owner) blocked = `Este template já é usado pelo fluxo de resposta “${owner.name}”. Edite ou remova esse fluxo em Fluxos de Resposta, ou escolha outro template.`
    else if (template && !template.receptive_ok) blocked = "Para ser receptivo, classifique o template como “Fluxos de resposta” ou “Atendimento” em Templates."

    // Bloqueado não pode ficar ligado: a publicação falharia.
    if (blocked && this.booleanConfig(node.config?.use_as_receptive, false)) {
      node.config.use_as_receptive = false
      this.sync()
    }

    const help = template
      ? `Quando alguém escrever para ${sender.label} · ${sender.phone}, este fluxo envia o menu do template e cada botão segue o caminho montado aqui. Vale ao publicar.`
      : `Quando alguém escrever para ${sender.label} · ${sender.phone}, este fluxo envia o menu do template. Escolha o template abaixo.`
    const toggle = this.checkboxField("Usar como receptivo deste número", "use_as_receptive", node.config?.use_as_receptive, help)
    const controls = [toggle]

    if (blocked) {
      toggle.classList.add("is-disabled")
      toggle.querySelector("input").disabled = true
      const notice = this.entryEventNotice(blocked)
      if (owner?.id) {
        const link = document.createElement("a")
        link.href = `/admin/whatsapp/fluxos-resposta/${owner.id}/edit`
        link.target = "_blank"
        link.rel = "noopener"
        link.textContent = "Abrir fluxo"
        notice.append(" ", link)
      }
      controls.push(notice)
      return controls
    }

    const current = sender.receptive_flow
    if (node.config?.use_as_receptive && current && current.workflow_id !== this.catalog.workflow_id) {
      controls.push(this.entryEventNotice(`Hoje este número usa o fluxo “${current.name}” como receptivo. Ao publicar, ele será substituído por este.`))
    }
    return controls
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

  actionTypeSummary(node) {
    const actionType = node.config?.action_type
    const panel = document.createElement("section")
    panel.className = "automation-workflow-builder__fixed-type"

    const label = document.createElement("span")
    label.className = "automation-workflow-builder__field-label"
    label.textContent = "Tipo de intervenção"

    const value = document.createElement("span")
    value.className = "automation-workflow-builder__fixed-type-value"

    const icon = document.createElement("i")
    icon.className = `bi ${this.actionIcon(actionType)}`

    const title = document.createElement("strong")
    title.textContent = this.actionLabel(actionType)

    const description = document.createElement("small")
    description.textContent = this.actionDescription(actionType)

    value.append(icon, title)
    value.title = description.textContent

    panel.append(label, value)
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
    if (node.type === "await_whatsapp_response") return this.awaitWhatsappResponseLiteralSummary(node)
    if (node.type === "response_condition") return this.responseConditionLiteralSummary(node)
    if (node.type === "response_fallback") return this.responseFallbackLiteralSummary(node)
    if (node.type === "response_router") return this.responseRouterLiteralSummary(node)
    if (node.type === "action") return this.actionLiteralSummary(node)
    if (node.type === "condition") return this.conditionLiteralSummary(node)

    return "Configurar esta etapa para continuar o acompanhamento do lead."
  }

  entryLiteralSummary(node) {
    const trigger = node.config?.trigger
    const triggerLabel = this.valueLabel(this.catalog.triggers, trigger, "o evento observado")
    const policy = node.config?.entry_policy === "existing_and_future" ? "a base atual e os próximos eventos" : "somente novos eventos"
    const distributionRules = this.distributionRulesLiteralPart(node)

    if (trigger === "scheduled_routine") {
      const frequency = this.scheduledLiteralSummary(node)
      const filters = this.filterLiteralParts(node, ["stage", "source"]).join(" e ")
      return `Observar ${frequency}${filters ? ` para leads com ${filters}` : ""}${distributionRules ? ` em ${distributionRules}` : ""}, considerando ${policy}.`
    }

    if (trigger === "lead_stage_changed") {
      const from = this.valueLabel(this.catalog.statuses, node.config?.from_stage, "qualquer etapa")
      const to = this.valueLabel(this.catalog.statuses, node.config?.to_stage, "qualquer etapa")
      return `Iniciar esta automação quando o lead mudar de ${from} para ${to}${distributionRules ? ` em ${distributionRules}` : ""}, considerando ${policy}.`
    }

    if (trigger === "lead_created") {
      const filters = this.filterLiteralParts(node, ["stage", "source"]).join(" e ")
      return `Iniciar esta automação quando um lead for criado${filters ? ` com ${filters}` : ""}${distributionRules ? ` em ${distributionRules}` : ""}, considerando ${policy}.`
    }

    if (trigger === "lead_idle") {
      const hours = node.config?.idle_hours || "48"
      const filters = this.filterLiteralParts(node, ["stage", "source"]).join(" e ")
      return `Iniciar esta automação quando o lead ficar parado por ${hours} hora(s)${filters ? ` com ${filters}` : ""}${distributionRules ? ` em ${distributionRules}` : ""}, considerando ${policy}.`
    }

    if (trigger === "whatsapp_received") {
      const filters = this.filterLiteralParts(node, ["stage"]).join(" e ")
      const contains = node.config?.message_contains ? ` contendo "${node.config.message_contains}"` : ""
      const notContains = node.config?.message_not_contains ? ` e sem conter "${node.config.message_not_contains}"` : ""
      return `Iniciar esta automação quando o lead responder no WhatsApp${contains}${notContains}${filters ? ` com ${filters}` : ""}${distributionRules ? ` em ${distributionRules}` : ""}, considerando ${policy}.`
    }

    if (this.proposalEvents().includes(trigger)) {
      const stage = this.valueLabel(this.catalog.statuses, node.config?.stage, "")
      return `Iniciar esta automação quando acontecer "${triggerLabel}"${stage ? ` para leads na etapa ${stage}` : ""}${distributionRules ? ` em ${distributionRules}` : ""}, considerando ${policy}.`
    }

    if (this.interestEvents().includes(trigger)) {
      const filters = this.filterLiteralParts(node, ["stage", "source"]).join(" e ")
      const score = trigger === "matching_property_found" ? ` com score mínimo ${node.config?.minimum_score || "65"}` : ""
      return `Iniciar esta automação quando a Inteligência de Interesse detectar "${triggerLabel}"${score}${filters ? ` para leads com ${filters}` : ""}${distributionRules ? ` em ${distributionRules}` : ""}, considerando ${policy}.`
    }

    return `Iniciar esta automação quando acontecer "${triggerLabel}"${distributionRules ? ` em ${distributionRules}` : ""}, considerando ${policy}.`
  }

  distributionRulesLiteralPart(node) {
    const names = this.selectedDistributionRuleNames(node)
    if (!names.length) return ""

    return `regras ${names.join(", ")}`
  }

  selectedDistributionRuleNames(node) {
    return Array(node.config?.distribution_rule_ids)
      .map((id) => this.catalog.distribution_rules?.[id])
      .filter(Boolean)
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

  responseRouterLiteralSummary(node) {
    const category = this.responseRouterCategoryOptions()[node.config?.category || "template_buttons"]
    const routes = this.responseRoutes(node)
    const timeout = `${node.config?.timeout_amount || "1"} ${this.unitLabel(node.config?.timeout_unit)}`
    const stage = node.config?.stage ? ` para leads na etapa ${this.valueLabel(this.catalog.statuses, node.config.stage, node.config.stage)}` : ""
    return `Aguardar resposta no WhatsApp${stage} por até ${timeout}; classificar como ${category} e executar o primeiro dos ${routes.length} fluxo(s) que casar.`
  }

  awaitWhatsappResponseLiteralSummary(node) {
    const timeout = `${node.config?.timeout_amount || "1"} ${this.unitLabel(node.config?.timeout_unit)}`
    const stage = node.config?.stage ? ` na etapa ${this.valueLabel(this.catalog.statuses, node.config.stage, node.config.stage)}` : ""
    const contains = node.config?.message_contains ? ` contendo "${node.config.message_contains}"` : ""
    return `Aguardar resposta WhatsApp${stage}${contains} por até ${timeout} e gravar a resposta para os caminhos condicionais.`
  }

  responseConditionLiteralSummary(node) {
    const field = this.valueLabel(this.responseRouterFieldOptions(node.config?.category || "template_buttons"), node.config?.field, "campo da resposta")
    const operator = this.valueLabel(this.responseRouterOperatorOptions(), node.config?.operator || "equals", "Igual")
    const value = node.config?.value ? ` "${node.config.value}"` : ""
    return `Continuar este caminho se ${field} ${operator.toLowerCase()}${value}.`
  }

  responseFallbackLiteralSummary(node) {
    const detail = this.responseFallbackDetails()[node.config?.fallback_type || "no_match"]
    return `Continuar este caminho quando ocorrer: ${detail?.title || "Resposta não reconhecida"}.`
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
    } else if (actionType === "send_whatsapp_buttons" || actionType === "send_whatsapp_list") {
      const count = this.questionOptions(node).length
      summary = `Perguntar ao cliente com ${actionType === "send_whatsapp_list" ? "uma lista" : "botões"} (${count} opç${count === 1 ? "ão" : "ões"}) e seguir pelo caminho da resposta.`
    } else if (actionType === "transfer_to_attendant") {
      const queue = this.valueLabel(this.catalog.distribution_rules, node.config?.distribution_rule_id, "uma fila ainda não selecionada")
      summary = `Passar a conversa para um atendente da fila "${queue}", levando as respostas do cliente como anotação.`
    } else if (actionType === "capture_answer") {
      const variable = node.config?.variable ? `{{resposta.${node.config.variable}}}` : "uma variável ainda não nomeada"
      const target = this.captureTargetLabel(node)
      summary = `Guardar a resposta do cliente em ${variable}${target ? ` e no campo "${target}" do lead` : ""}.`
    } else if (actionType === "send_whatsapp_template") {
      const template = this.valueLabel(this.catalog.templates, node.config?.template, "um modelo ainda não selecionado")
      summary = `Enviar modelo WhatsApp "${template}" para o lead.`
    } else if (actionType === "send_webhook") {
      summary = node.config?.url ? `Enviar webhook para ${node.config.url}.` : "Configurar o endpoint que receberá o evento da automação."
    } else if (actionType === "set_flow_result") {
      const result = node.config?.result || "no_attendance"
      const resultLabel = this.valueLabel(this.flowResultOptions(), result, "Não gera atendimento")
      const destination = this.valueLabel(this.catalog.distribution_rules, node.config?.distribution_rule_id, "")
      summary = result === "generates_attendance"
        ? `Definir resultado como "${resultLabel}" e enviar para "${destination || "um destino ainda não selecionado"}".`
        : `Definir resultado como "${resultLabel}" e registrar que este caminho não gera atendimento.`
    } else if (actionType === "move_stage") {
      const stage = this.valueLabel(this.catalog.automation_stages || this.catalog.statuses, node.config?.to, "uma etapa ainda não selecionada")
      summary = `Mover o lead para a etapa "${stage}" como apoio ao acompanhamento.`
    } else if (actionType === "update_lead_lifecycle") {
      const action = this.valueLabel(this.lifecycleActionOptions(), node.config?.lifecycle_action || "mark_no_interest", "Atualizar ciclo de vida")
      const stage = this.valueLabel(this.catalog.automation_stages || this.catalog.statuses, node.config?.to || this.defaultLifecycleStage(node.config?.lifecycle_action), "uma etapa ainda não selecionada")
      summary = `${action} e mover o lead para "${stage}", registrando a decisão no histórico.`
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
        copy: "Ao publicar, avalia a base atual pelos filtros da entrada e continua observando novos eventos.",
        note: "Em respostas WhatsApp, propostas e mudanças de etapa, usa o evento histórico real mais recente de cada lead; não inventa eventos."
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
      this.inspectorTarget.appendChild(this.field("Executar em", "run_at", node.config?.run_at || "", "datetime-local", { required: true }))
      this.inspectorTarget.appendChild(this.entryEventNotice("Se a data/hora já tiver passado quando a etapa rodar, a automação continua imediatamente."))
      return
    }

    if (mode !== "next_business_window") {
      this.inspectorTarget.appendChild(this.selectField("Unidade", "unit", node.config?.unit, {
        minutes: "Minutos",
        hours: "Horas",
        days: "Dias"
      }, { placeholder: "Selecione a unidade" }))
      this.inspectorTarget.appendChild(this.field("Quantidade", "amount", node.config?.amount || "1", "number", { min: 1, required: true, presets: [["1", "1"], ["2", "2"], ["3", "3"], ["7", "7"], ["15", "15"], ["30", "30"]] }))
    }

    if (mode === "business_duration" || mode === "next_business_window") {
      this.inspectorTarget.appendChild(this.field("Início da janela", "business_start", node.config?.business_start || "09:00", "time"))
      this.inspectorTarget.appendChild(this.field("Fim da janela", "business_end", node.config?.business_end || "18:00", "time"))
      this.inspectorTarget.appendChild(this.checkboxField("Ignorar fins de semana", "skip_weekends", node.config?.skip_weekends ?? true, "Se estiver marcado, sábado e domingo são pulados."))
      this.inspectorTarget.appendChild(this.entryEventNotice("A janela comercial usa o horário da plataforma. Feriados e calendários por loja podem entrar depois como calendário próprio."))
    }
  }

  renderAwaitEventFields(node) {
    this.inspectorTarget.appendChild(this.selectField("Evento esperado", "trigger", node.config?.trigger, this.awaitableEvents(), { placeholder: "Selecione o evento", required: true }))

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

    this.inspectorTarget.appendChild(this.field("Timeout", "timeout_amount", node.config?.timeout_amount || "1", "number", { min: 1, presets: [["1", "1"], ["2", "2"], ["3", "3"], ["7", "7"]] }))
    this.inspectorTarget.appendChild(this.selectField("Unidade do timeout", "timeout_unit", node.config?.timeout_unit, {
      minutes: "Minutos",
      hours: "Horas",
      days: "Dias"
    }, { placeholder: "Selecione a unidade" }))
    this.inspectorTarget.appendChild(this.entryEventNotice("Se o evento acontecer antes do timeout, o fluxo continua. Se não acontecer, continua quando o timeout vencer."))
  }

  renderAwaitWhatsappResponseFields(node) {
    this.inspectorTarget.appendChild(this.selectField("Etapa atual", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, {
      placeholder: "Qualquer etapa",
      info: "Use quando a espera só deve aceitar respostas de leads que ainda estão em uma etapa específica."
    }))
    this.inspectorTarget.appendChild(this.field("Mensagem contém", "message_contains", node.config?.message_contains || "", "text", {
      info: "Filtro opcional no texto recebido. Deixe vazio para aceitar qualquer resposta do WhatsApp."
    }))
    this.inspectorTarget.appendChild(this.field("Mensagem não contém", "message_not_contains", node.config?.message_not_contains || "", "text", {
      info: "Filtro opcional para ignorar respostas com termos indesejados."
    }))
    this.inspectorTarget.appendChild(this.field("Timeout", "timeout_amount", node.config?.timeout_amount || "1", "number", {
      min: 1,
      presets: [["1", "1"], ["2", "2"], ["3", "3"], ["7", "7"]],
      info: "Tempo máximo aguardando a resposta antes de liberar o caminho de fallback por timeout."
    }))
    this.inspectorTarget.appendChild(this.selectField("Unidade do timeout", "timeout_unit", node.config?.timeout_unit || "days", {
      minutes: "Minutos",
      hours: "Horas",
      days: "Dias"
    }, {
      placeholder: "Selecione a unidade",
      info: "Unidade usada para calcular quando o caminho de timeout deve seguir."
    }))
    this.inspectorTarget.appendChild(this.entryEventNotice("Depois deste bloco, adicione caminhos paralelos com Condição de resposta e Fallback de resposta."))
  }

  renderResponseConditionFields(node) {
    const category = node.config?.category || "template_buttons"
    const template = this.templateForNode(node)
    const buttons = template ? template.scaffold.nodes.filter((item) => item.type === "response_condition") : []

    // Caminho de botão de template: o usuário só escolhe o botão; o resto (payload, operador, valor) é técnico.
    if (category === "template_buttons" && buttons.length) {
      this.inspectorTarget.appendChild(this.templateButtonPicker(node, buttons))
      const advanced = document.createElement("details")
      advanced.className = "automation-workflow-builder__entry-advanced"
      advanced.innerHTML = '<summary><i class="bi bi-sliders"></i><span>Configuração técnica (avançado)</span></summary>'
      this.appendResponseConditionTechnicalFields(node, category, advanced)
      this.inspectorTarget.appendChild(advanced)
      return
    }

    this.appendResponseConditionTechnicalFields(node, category, this.inspectorTarget)
  }

  // "Quando o cliente clicar em ..." com os botões do template como opções (já usados ficam sinalizados).
  templateButtonPicker(node, buttons) {
    const section = document.createElement("section")
    section.className = "automation-workflow-builder__field"
    section.appendChild(this.fieldLabel("Quando o cliente clicar em", "Escolha qual botão do template inicia este caminho. Tudo o que vem depois só roda para quem clicar nele.", true))

    const used = new Set(this.definition.nodes
      .filter((item) => item.type === "response_condition" && item.id !== node.id)
      .map((item) => String(item.config?.button_key || "")))

    const row = document.createElement("div")
    row.className = "automation-workflow-builder__chips"
    row.setAttribute("role", "radiogroup")
    row.setAttribute("aria-label", "Botão do template")
    buttons.forEach((buttonNode) => {
      const key = String(buttonNode.config.button_key)
      const chip = document.createElement("button")
      chip.type = "button"
      chip.setAttribute("role", "radio")
      const active = key === String(node.config?.button_key || "")
      chip.setAttribute("aria-checked", active)
      chip.className = `automation-workflow-builder__chip${active ? " is-active" : ""}`
      chip.innerHTML = `<i class="bi bi-reply"></i>${this.escapeHtml(buttonNode.config.button_text)}${used.has(key) ? ' <em title="Outro caminho já usa este botão">em uso</em>' : ""}`
      chip.addEventListener("click", () => {
        if (active) return
        node.config = { ...node.config, ...JSON.parse(JSON.stringify(buttonNode.config)) }
        node.label = buttonNode.label
        this.sync()
        this.render()
      })
      row.appendChild(chip)
    })
    section.appendChild(row)
    section.appendChild(this.entryEventNotice("Se o cliente clicar neste botão, o fluxo segue pelas etapas ligadas abaixo. Se clicar em outro, segue o caminho do outro botão."))
    return section
  }

  appendResponseConditionTechnicalFields(node, category, container) {
    const detail = this.responseRouterCategoryDetails()[category] || this.responseRouterCategoryDetails().template_buttons

    container.appendChild(this.selectField("Tipo de resposta", "category", category, this.responseRouterCategoryOptions(), {
      placeholder: "Selecione o tipo",
      info: "Define quais campos aparecem abaixo. Esta condição lê a resposta gravada pelo bloco Aguardar resposta WhatsApp."
    }))
    container.appendChild(this.responseRouterInfoPanel(detail))
    container.appendChild(this.selectField("Campo avaliado", "field", node.config?.field || this.defaultResponseField(category), this.responseRouterFieldOptions(category), {
      placeholder: "Selecione o campo",
      info: "Campo da resposta ou do lead que será comparado."
    }))
    container.appendChild(this.selectField("Operador", "operator", node.config?.operator || "equals", this.responseRouterOperatorOptions(), {
      placeholder: "Selecione o operador",
      info: "Como o campo recebido será comparado com o valor esperado."
    }))
    container.appendChild(this.field("Valor esperado", "value", node.config?.value || "", "text", {
      required: !this.valueFreeOperator(node.config?.operator || "equals"),
      info: "Texto, payload, status ou valor esperado. Quando o operador for Existe, pode ficar vazio."
    }))
    container.appendChild(this.entryEventNotice("Se esta condição casar, o caminho continua para as intervenções conectadas depois dela. Se não casar, este caminho para aqui."))
  }

  renderResponseFallbackFields(node) {
    const fallbackType = node.config?.fallback_type || "no_match"
    const detail = this.responseFallbackDetails()[fallbackType] || this.responseFallbackDetails().no_match

    this.inspectorTarget.appendChild(this.selectField("Tipo de fallback", "fallback_type", fallbackType, {
      timeout: "Sem resposta até timeout",
      no_match: "Resposta não reconhecida",
      exhausted: "Depois das tentativas"
    }, {
      placeholder: "Selecione o fallback",
      info: "Define quando este caminho alternativo deve rodar."
    }))
    this.inspectorTarget.appendChild(this.responseRouterInfoPanel(detail))
    if (fallbackType === "no_match") {
      this.inspectorTarget.appendChild(this.checkboxField("Repetir a pergunta depois do aviso", "retry_question", node.config?.retry_question, "Pergunta de novo até o limite abaixo. Depois disso, segue o caminho “Depois das tentativas”, se existir."))
      if (this.booleanConfig(node.config?.retry_question, false)) {
        this.inspectorTarget.appendChild(this.field("Repetir até quantas vezes (1 a 5)", "max_attempts", node.config?.max_attempts || "2", "number"))
      }
    }
    this.inspectorTarget.appendChild(this.entryEventNotice("Depois deste fallback, adicione a intervenção normal: perguntar novamente, criar tarefa, mover etapa ou registrar nota."))
  }

  renderResponseRouterFields(node) {
    this.ensureResponseRouterDefaults(node)
    const category = node.config?.category || "template_buttons"
    const detail = this.responseRouterCategoryDetails()[category] || this.responseRouterCategoryDetails().template_buttons

    this.inspectorTarget.appendChild(this.selectField("Tipo de resposta", "category", category, this.responseRouterCategoryOptions(), {
      placeholder: "Selecione o tipo",
      info: "Define quais campos ficam disponíveis para montar as condições. Use Botões do template para cliques, Texto livre para mensagens digitadas, Guardrails para exceções operacionais e Status para ciclo de vida."
    }))
    this.inspectorTarget.appendChild(this.responseRouterInfoPanel(detail))
    this.inspectorTarget.appendChild(this.selectField("Etapa atual", "stage", node.config?.stage, { "": "Qualquer etapa", ...this.catalog.statuses }, {
      placeholder: "Qualquer etapa",
      info: "Restringe a automação para respostas recebidas enquanto o lead estiver nesta etapa. Deixe vazio para aceitar qualquer etapa."
    }))
    this.inspectorTarget.appendChild(this.field("Timeout", "timeout_amount", node.config?.timeout_amount || "1", "number", {
      info: "Tempo máximo aguardando uma resposta do lead. Se vencer, a automação segue para a próxima etapa visual sem executar nenhum fluxo condicional."
    }))
    this.inspectorTarget.appendChild(this.selectField("Unidade do timeout", "timeout_unit", node.config?.timeout_unit || "days", {
      minutes: "Minutos",
      hours: "Horas",
      days: "Dias"
    }, {
      placeholder: "Selecione a unidade",
      info: "Unidade usada para calcular o prazo de espera da resposta."
    }))
    this.inspectorTarget.appendChild(this.responseRoutesSection(node, category))
  }

  responseRouterInfoPanel(detail) {
    const panel = document.createElement("section")
    panel.className = "automation-workflow-builder__response-info"
    panel.innerHTML = `
      <i class="bi ${this.escapeHtml(detail.icon)}"></i>
      <span>
        <strong>${this.escapeHtml(detail.title)}</strong>
        <small>${this.escapeHtml(detail.copy)}</small>
      </span>
    `
    return panel
  }

  responseRoutesSection(node, category) {
    const section = document.createElement("section")
    section.className = "automation-workflow-builder__response-section"

    const header = document.createElement("div")
    header.className = "automation-workflow-builder__response-section-header"
    header.innerHTML = `
      <span>
        <strong>Fluxos condicionais</strong>
        <small>O primeiro fluxo que casar com a resposta executa suas ações e depois a automação segue.</small>
      </span>
    `

    const list = document.createElement("div")
    list.className = "automation-workflow-builder__response-routes"
    this.responseRoutes(node).forEach((route, routeIndex) => {
      list.appendChild(this.responseRouteCard(node, route, routeIndex, category))
    })

    const add = document.createElement("button")
    add.type = "button"
    add.className = "ax-btn ax-btn--sm automation-workflow-builder__response-add"
    add.innerHTML = '<i class="bi bi-plus-lg"></i><span>Adicionar fluxo</span>'
    add.addEventListener("click", (event) => this.addResponseRoute(event))

    section.append(header, list, add)
    return section
  }

  responseRouteCard(node, route, routeIndex, category) {
    const card = document.createElement("article")
    card.className = "automation-workflow-builder__response-route"

    const header = document.createElement("div")
    header.className = "automation-workflow-builder__response-route-header"
    header.appendChild(this.responseRouteInput({
      routeIndex,
      field: "name",
      value: route.name,
      placeholder: `Fluxo ${routeIndex + 1}`,
      label: "Nome do fluxo",
      info: "Use um nome operacional, por exemplo: Clique em Saiba mais ou Pediu atendimento humano."
    }))

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "automation-workflow-builder__kv-remove"
    remove.title = "Remover fluxo"
    remove.setAttribute("aria-label", "Remover fluxo")
    remove.disabled = this.responseRoutes(node).length <= 1
    remove.innerHTML = '<i class="bi bi-trash"></i>'
    remove.addEventListener("click", (event) => this.removeResponseRoute(event, routeIndex))
    header.appendChild(remove)

    const conditionsTitle = this.responseMiniTitle("Condições", "Definem quando este fluxo deve ser executado.")
    const conditions = document.createElement("div")
    conditions.className = "automation-workflow-builder__response-list"
    this.responseConditions(route).forEach((condition, conditionIndex) => {
      conditions.appendChild(this.responseConditionRow(condition, routeIndex, conditionIndex, category))
    })

    const addCondition = this.responseInlineButton("Adicionar condição", "bi-plus-lg", (event) => this.addResponseCondition(event, routeIndex))
    const actionsTitle = this.responseMiniTitle("Ações", "Executadas quando as condições acima casarem.")
    const actions = document.createElement("div")
    actions.className = "automation-workflow-builder__response-list"
    this.responseActions(route).forEach((action, actionIndex) => {
      actions.appendChild(this.responseActionRow(action, routeIndex, actionIndex))
    })
    const addAction = this.responseInlineButton("Adicionar ação", "bi-plus-lg", (event) => this.addResponseAction(event, routeIndex))

    card.append(header, conditionsTitle, conditions, addCondition, actionsTitle, actions, addAction)
    return card
  }

  responseConditionRow(condition, routeIndex, conditionIndex, category) {
    const row = document.createElement("div")
    row.className = "automation-workflow-builder__response-condition"
    row.appendChild(this.responseSelectInput({
      routeIndex,
      conditionIndex,
      part: "condition",
      field: "field",
      label: "Campo",
      value: condition.field,
      options: this.responseRouterFieldOptions(category),
      info: "Campo da resposta ou do lead que será comparado nesta condição."
    }))
    row.appendChild(this.responseSelectInput({
      routeIndex,
      conditionIndex,
      part: "condition",
      field: "operator",
      label: "Operador",
      value: condition.operator || "equals",
      options: this.responseRouterOperatorOptions(),
      info: "Como o valor recebido deve ser comparado com o valor informado."
    }))
    row.appendChild(this.responseRouteInput({
      routeIndex,
      conditionIndex,
      part: "condition",
      field: "value",
      label: "Valor esperado",
      value: condition.value,
      placeholder: "Saiba mais",
      info: "Texto, status ou valor que precisa aparecer para este fluxo rodar. Em operador Existe, pode ficar vazio."
    }))
    row.appendChild(this.responseRemoveButton("Remover condição", (event) => this.removeResponseCondition(event, routeIndex, conditionIndex)))
    return row
  }

  responseActionRow(action, routeIndex, actionIndex) {
    const row = document.createElement("div")
    row.className = "automation-workflow-builder__response-action"
    const actionType = action.type || "send_whatsapp"
    row.appendChild(this.responseSelectInput({
      routeIndex,
      actionIndex,
      part: "action",
      field: "type",
      label: "Ação",
      value: actionType,
      options: this.responseActionOptions(),
      info: "O que a automação faz quando este fluxo condicional for escolhido."
    }))

    if (actionType === "move_stage") {
      row.appendChild(this.responseSelectInput({
        routeIndex,
        actionIndex,
        part: "action",
        field: "to",
        label: "Mover para",
        value: action.to,
        options: this.catalog.automation_stages || this.catalog.statuses,
        info: "Etapa operacional que será aplicada ao lead."
      }))
    } else {
      row.appendChild(this.responseRouteInput({
        routeIndex,
        actionIndex,
        part: "action",
        field: actionType === "add_note" ? "body" : "message",
        label: actionType === "add_note" ? "Nota" : "Mensagem",
        value: actionType === "add_note" ? action.body : action.message,
        placeholder: actionType === "add_note" ? "Registrar no histórico..." : "Perfeito. Vou te passar mais detalhes agora.",
        info: actionType === "add_note" ? "Texto registrado no histórico interno do lead." : "Mensagem livre enviada ao WhatsApp do lead."
      }))
    }

    row.appendChild(this.responseRemoveButton("Remover ação", (event) => this.removeResponseAction(event, routeIndex, actionIndex)))
    return row
  }

  responseMiniTitle(title, info) {
    const wrap = document.createElement("div")
    wrap.className = "automation-workflow-builder__response-mini-title"
    wrap.appendChild(this.fieldLabel(title, info))
    return wrap
  }

  responseInlineButton(label, icon, callback) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "automation-workflow-builder__response-inline-add"
    button.innerHTML = `<i class="bi ${icon}"></i><span>${this.escapeHtml(label)}</span>`
    button.addEventListener("click", callback)
    return button
  }

  responseRemoveButton(label, callback) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "automation-workflow-builder__kv-remove"
    button.title = label
    button.setAttribute("aria-label", label)
    button.innerHTML = '<i class="bi bi-trash"></i>'
    button.addEventListener("click", callback)
    return button
  }

  responseRouteInput({ routeIndex, conditionIndex, actionIndex, part = "route", field, label, value, placeholder, info }) {
    const wrap = document.createElement("label")
    wrap.className = "automation-workflow-builder__kv-field"
    const input = document.createElement("input")
    input.className = "ax-input"
    input.type = "text"
    input.value = value || ""
    input.placeholder = placeholder || ""
    input.dataset.responsePart = part
    input.dataset.routeIndex = routeIndex
    input.dataset.field = field
    if (conditionIndex !== undefined) input.dataset.conditionIndex = conditionIndex
    if (actionIndex !== undefined) input.dataset.actionIndex = actionIndex
    input.addEventListener("input", (event) => this.updateResponseRoute(event))
    wrap.append(this.fieldLabel(label, info), input)
    return wrap
  }

  responseSelectInput({ routeIndex, conditionIndex, actionIndex, part, field, label, value, options, info }) {
    const wrap = document.createElement("label")
    wrap.className = "automation-workflow-builder__kv-field"
    const select = document.createElement("select")
    select.className = "ax-select"
    select.dataset.responsePart = part
    select.dataset.routeIndex = routeIndex
    select.dataset.field = field
    if (conditionIndex !== undefined) select.dataset.conditionIndex = conditionIndex
    if (actionIndex !== undefined) select.dataset.actionIndex = actionIndex
    Object.entries(options || {}).forEach(([optionValue, optionLabel]) => {
      const option = document.createElement("option")
      option.value = optionValue
      option.textContent = optionLabel
      option.selected = optionValue === value
      select.appendChild(option)
    })
    select.addEventListener("change", (event) => this.updateResponseRoute(event, { rerender: true }))
    wrap.append(this.fieldLabel(label, info), select)
    return wrap
  }

  addResponseRoute(event) {
    if (event) event.preventDefault()
    const node = this.selectedNode()
    if (!node) return
    this.ensureResponseRouterDefaults(node)
    node.config.routes.push(this.defaultResponseRoute(node.config.category || "template_buttons", node.config.routes.length))
    this.persistResponseRouterChange()
  }

  removeResponseRoute(event, routeIndex) {
    if (event) event.preventDefault()
    const node = this.selectedNode()
    if (!node) return
    const routes = this.responseRoutes(node)
    if (routes.length <= 1) return
    routes.splice(routeIndex, 1)
    node.config.routes = routes
    this.persistResponseRouterChange()
  }

  addResponseCondition(event, routeIndex) {
    if (event) event.preventDefault()
    const node = this.selectedNode()
    if (!node) return
    const routes = this.responseRoutes(node)
    routes[routeIndex].conditions = this.responseConditions(routes[routeIndex])
    routes[routeIndex].conditions.push(this.defaultResponseCondition(node.config?.category || "template_buttons"))
    node.config.routes = routes
    this.persistResponseRouterChange()
  }

  removeResponseCondition(event, routeIndex, conditionIndex) {
    if (event) event.preventDefault()
    const node = this.selectedNode()
    if (!node) return
    const routes = this.responseRoutes(node)
    const conditions = this.responseConditions(routes[routeIndex])
    if (conditions.length <= 1) return
    conditions.splice(conditionIndex, 1)
    routes[routeIndex].conditions = conditions
    node.config.routes = routes
    this.persistResponseRouterChange()
  }

  addResponseAction(event, routeIndex) {
    if (event) event.preventDefault()
    const node = this.selectedNode()
    if (!node) return
    const routes = this.responseRoutes(node)
    routes[routeIndex].actions = this.responseActions(routes[routeIndex])
    routes[routeIndex].actions.push(this.defaultResponseAction())
    node.config.routes = routes
    this.persistResponseRouterChange()
  }

  removeResponseAction(event, routeIndex, actionIndex) {
    if (event) event.preventDefault()
    const node = this.selectedNode()
    if (!node) return
    const routes = this.responseRoutes(node)
    const actions = this.responseActions(routes[routeIndex])
    if (actions.length <= 1) return
    actions.splice(actionIndex, 1)
    routes[routeIndex].actions = actions
    node.config.routes = routes
    this.persistResponseRouterChange()
  }

  updateResponseRoute(event, options = {}) {
    const node = this.selectedNode()
    if (!node) return
    const target = event.currentTarget
    const routes = this.responseRoutes(node)
    const route = routes[Number.parseInt(target.dataset.routeIndex, 10)]
    if (!route) return

    const value = target.value
    if (target.dataset.responsePart === "condition") {
      const condition = this.responseConditions(route)[Number.parseInt(target.dataset.conditionIndex, 10)]
      if (condition) condition[target.dataset.field] = value
      route.conditions = this.responseConditions(route)
    } else if (target.dataset.responsePart === "action") {
      const action = this.responseActions(route)[Number.parseInt(target.dataset.actionIndex, 10)]
      if (action) {
        action[target.dataset.field] = value
        if (target.dataset.field === "type") {
          Object.keys(action).forEach((key) => {
            if (!["type"].includes(key)) delete action[key]
          })
        }
      }
      route.actions = this.responseActions(route)
    } else {
      route[target.dataset.field] = value
    }

    node.config.routes = routes
    this.sync()
    this.renderCanvas()
    this.refreshLiteralSummary()
    if (options.rerender) this.renderInspector()
  }

  persistResponseRouterChange() {
    this.sync()
    this.renderCanvas()
    this.refreshLiteralSummary()
    this.renderInspector()
  }

  ensureResponseRouterDefaults(node) {
    node.config = node.config || {}
    node.config.category = node.config.category || "template_buttons"
    node.config.timeout_amount = node.config.timeout_amount || "1"
    node.config.timeout_unit = node.config.timeout_unit || "days"
    if (!Array.isArray(node.config.routes) || !node.config.routes.length) {
      node.config.routes = [this.defaultResponseRoute(node.config.category, 0)]
    }
  }

  responseRoutes(node) {
    return Array.isArray(node.config?.routes) && node.config.routes.length ? node.config.routes : [this.defaultResponseRoute(node.config?.category || "template_buttons", 0)]
  }

  responseConditions(route) {
    return Array.isArray(route?.conditions) && route.conditions.length ? route.conditions : [this.defaultResponseCondition()]
  }

  responseActions(route) {
    return Array.isArray(route?.actions) && route.actions.length ? route.actions : [this.defaultResponseAction()]
  }

  defaultResponseRoute(category = "template_buttons", index = 0) {
    return {
      id: `route_${Date.now()}_${index}`,
      name: index === 0 ? "Fluxo principal" : `Fluxo ${index + 1}`,
      conditions: [this.defaultResponseCondition(category)],
      actions: [this.defaultResponseAction()]
    }
  }

  defaultResponseCondition(category = "template_buttons") {
    const firstField = Object.keys(this.responseRouterFieldOptions(category))[0] || "message.body"
    return { field: firstField, operator: "contains", value: "" }
  }

  defaultResponseAction() {
    return { type: "send_whatsapp", message: "" }
  }

  responseRouterCategoryOptions() {
    return {
      guardrails: "Guardrails",
      template_buttons: "Botões do template",
      lead_text: "Texto livre do lead",
      lifecycle: "Status e ciclo de vida"
    }
  }

  responseRouterCategoryDetails() {
    return {
      guardrails: {
        title: "Guardrails",
        icon: "bi-shield-check",
        copy: "Use para exceções de operação, como fora de horário ou retorno de integração com erro."
      },
      template_buttons: {
        title: "Botões do template",
        icon: "bi-menu-button-wide",
        copy: "Use quando a resposta esperada vem de um botão clicado no template WhatsApp."
      },
      lead_text: {
        title: "Texto livre do lead",
        icon: "bi-chat-left-text",
        copy: "Use quando o lead digita uma resposta e a automação precisa procurar palavras ou intenções."
      },
      lifecycle: {
        title: "Status e ciclo de vida",
        icon: "bi-arrow-repeat",
        copy: "Use quando a resposta precisa considerar etapa, status ou reativação do lead."
      }
    }
  }

  responseFallbackDetails() {
    return {
      timeout: {
        title: "Sem resposta até timeout",
        icon: "bi-hourglass-split",
        copy: "Este caminho roda quando o lead não responde dentro do prazo definido no bloco de espera."
      },
      no_match: {
        title: "Resposta não reconhecida",
        icon: "bi-question-diamond",
        copy: "Este caminho roda quando houve resposta, mas nenhuma condição irmã conectada ao mesmo ponto casou."
      },
      exhausted: {
        title: "Depois das tentativas",
        icon: "bi-arrow-repeat",
        copy: "Roda quando o cliente já errou o número de vezes definido em “Resposta não reconhecida”. Use para passar para um atendente."
      }
    }
  }

  responseRouterFieldOptions(category) {
    return {
      guardrails: {
        "guardrail.outside_hours": "Fora de horário",
        "guardrail.crm_error": "Retorno CRM com erro"
      },
      template_buttons: {
        "interaction.button_text": "Texto do botão clicado",
        "interaction.button_payload": "Payload do botão",
        "campaign.response_decision.action": "Decisão configurada na campanha",
        "campaign.response_decision.label": "Nome da decisão"
      },
      lead_text: {
        "message.body": "Mensagem digitada",
        "message.intent": "Intenção detectada"
      },
      lifecycle: {
        "lead.status": "Status atual do lead",
        "lead.lifecycle": "Ciclo de vida"
      }
    }[category] || { "message.body": "Mensagem digitada" }
  }

  defaultResponseField(category = "template_buttons") {
    return Object.keys(this.responseRouterFieldOptions(category))[0] || "message.body"
  }

  responseRouterOperatorOptions() {
    return {
      equals: "Igual",
      contains: "Contém",
      not_contains: "Não contém",
      present: "Existe",
      valid_email: "É um e-mail válido",
      valid_phone: "É um telefone válido",
      valid_number: "É um número"
    }
  }

  responseActionOptions() {
    return {
      send_whatsapp: "Enviar mensagem",
      add_note: "Registrar nota",
      move_stage: "Mover etapa"
    }
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
      this.inspectorTarget.appendChild(this.field("Titulo da tarefa", "title", node.config?.title || node.config?.message || "", "text", { required: true, placeholder: "Ex.: Ligar para o lead" }))
      this.inspectorTarget.appendChild(this.field("Vencimento em horas", "due_in_hours", node.config?.due_in_hours || "24", "number", { presets: [["2h", "2"], ["4h", "4"], ["24h", "24"], ["48h", "48"], ["3 dias", "72"]], presetSuffix: "horas", min: 1 }))
      this.renderTaskAssigneeFallbackField(node)
    } else if (actionType === "send_whatsapp") {
      this.inspectorTarget.appendChild(this.textArea("Mensagem WhatsApp", "message", node.config?.message || "", { required: true, variables: true, counter: true, rows: 4, placeholder: "Olá {{nome}}, tudo bem?" }))
    } else if (actionType === "send_whatsapp_buttons" || actionType === "send_whatsapp_list") {
      const list = actionType === "send_whatsapp_list"
      this.inspectorTarget.appendChild(this.textArea("Pergunta", "message", node.config?.message || "", { required: true, variables: true, maxlength: 1024, rows: 3, info: "O que o cliente vai ler. Use as variáveis abaixo para personalizar." }))
      if (list) this.inspectorTarget.appendChild(this.field("Texto do botão que abre a lista", "list_button", node.config?.list_button || "Ver opções", "text", { required: true, maxlength: 20, info: "Até 20 caracteres." }))
      this.inspectorTarget.appendChild(this.optionsListField(node, { max: list ? 10 : 3, maxlength: list ? 24 : 20 }))
    } else if (actionType === "transfer_to_attendant") {
      this.inspectorTarget.appendChild(this.selectField("Fila de atendimento", "distribution_rule_id", node.config?.distribution_rule_id, this.catalog.distribution_rules, { placeholder: "Selecione a fila", required: true, emptyHint: this.noDistributionRulesHint() }))
      this.inspectorTarget.appendChild(this.field("Assunto (o atendente vê na lista)", "topic", node.config?.topic || "Atendimento automático", "text", { maxlength: 80, info: "Aparece na lista de conversas e na gestão de atendimentos." }))
      this.inspectorTarget.appendChild(this.textArea("Mensagem ao finalizar o atendimento", "finish_message", node.config?.finish_message || "", { variables: true, rows: 3, info: "Enviada ao cliente quando o atendente clicar em Finalizar. Vazio usa a mensagem padrão." }))
    } else if (actionType === "capture_answer") {
      this.renderCaptureFields(node)
    } else if (actionType === "send_whatsapp_template") {
      this.renderTemplateActionFields(node)
    } else if (actionType === "send_webhook") {
      const webhookContext = this.webhookContextFor(node)
      this.inspectorTarget.appendChild(this.field("URL do webhook", "url", node.config?.url || "", "url", { required: true, placeholder: "https://exemplo.com/webhook" }))
      this.inspectorTarget.appendChild(this.selectField("Método", "http_method", node.config?.http_method || "post", {
        post: "POST",
        put: "PUT",
        patch: "PATCH"
      }, { placeholder: "Selecione o método" }))
      this.inspectorTarget.appendChild(this.webhookContextPanel(webhookContext))
      this.inspectorTarget.appendChild(this.webhookKeyValueSection({
        title: "Headers",
        description: "Cabeçalhos enviados junto com a requisição. Use um por linha, sem escrever JSON.",
        kind: "headers",
        rows: this.webhookRows(node, "headers"),
        keyLabel: "Header",
        valueLabel: "Valor",
        keyPlaceholder: "Authorization",
        valuePlaceholder: "Bearer {{event.payload.token}}",
        addLabel: "Adicionar header"
      }))
      this.inspectorTarget.appendChild(this.webhookKeyValueSection({
        title: "Payload",
        description: `Campos sugeridos para ${webhookContext.label.toLowerCase()}. Ajuste o de/para conforme o sistema de destino.`,
        kind: "payload",
        rows: this.webhookRows(node, "payload"),
        keyLabel: "Campo no JSON",
        valueLabel: "Valor / token",
        keyPlaceholder: webhookContext.payloadPlaceholder || "lead.nome",
        valuePlaceholder: webhookContext.valuePlaceholder || "{{lead.name}}",
        addLabel: "Adicionar campo"
      }))
      this.inspectorTarget.appendChild(this.webhookTestPanel())
      this.inspectorTarget.appendChild(this.webhookTokenReference(webhookContext))
    } else if (actionType === "set_flow_result") {
      const result = node.config?.result || "no_attendance"
      this.inspectorTarget.appendChild(this.selectField("Resultado do fluxo", "result", result, this.flowResultOptions(), {
        placeholder: "Selecione o resultado",
        info: "Define se este caminho cria uma consequência de atendimento ou apenas registra/encerra a resposta."
      }))
      if (result === "generates_attendance") {
        this.inspectorTarget.appendChild(this.selectField("Destino do atendimento", "distribution_rule_id", node.config?.distribution_rule_id, this.catalog.distribution_rules, {
          placeholder: "Selecione a regra",
          required: true,
          emptyHint: this.noDistributionRulesHint(),
          info: "Regra de distribuição que assume o atendimento quando este caminho gerar atendimento."
        }))
      }
      this.inspectorTarget.appendChild(this.textArea("Nota interna", "note", node.config?.note || "", {
        variables: true,
        rows: 3,
        info: "Texto opcional registrado junto do resultado do caminho."
      }))
      this.inspectorTarget.appendChild(this.entryEventNotice(this.flowResultNotice(result)))
    } else if (actionType === "move_stage") {
      this.inspectorTarget.appendChild(this.selectField("Mover para etapa", "to", node.config?.to, this.catalog.automation_stages || this.catalog.statuses, { placeholder: "Selecione a etapa", required: true }))
      this.inspectorTarget.appendChild(this.moveStageNotice())
    } else if (actionType === "update_lead_lifecycle") {
      this.inspectorTarget.appendChild(this.selectField("Ação no lead", "lifecycle_action", node.config?.lifecycle_action || "mark_no_interest", this.lifecycleActionOptions(), {
        placeholder: "Selecione a ação",
        info: "Define o significado operacional da mudança. A automação registra essa decisão no histórico do lead."
      }))
      this.inspectorTarget.appendChild(this.selectField("Etapa de destino", "to", node.config?.to || this.defaultLifecycleStage(node.config?.lifecycle_action), this.catalog.automation_stages || this.catalog.statuses, {
        placeholder: "Selecione a etapa",
        info: "Etapa aplicada ao lead quando esta intervenção executar. Ajuste para o padrão comercial da operação."
      }))
      this.inspectorTarget.appendChild(this.textArea("Nota interna", "note", node.config?.note || "", {
        variables: true,
        rows: 3,
        info: "Texto opcional registrado junto da mudança para explicar a decisão."
      }))
    } else if (actionType === "assign_agent") {
      this.inspectorTarget.appendChild(this.legacyVerticalActionNotice())
    } else if (actionType === "add_note") {
      this.inspectorTarget.appendChild(this.textArea("Nota interna", "body", node.config?.body || node.config?.message || "", { required: true, variables: true, rows: 3 }))
    } else if (actionType === "create_interest_curation_task") {
      this.inspectorTarget.appendChild(this.field("Titulo da tarefa", "title", node.config?.title || "Curar imóveis para o lead", "text", { required: true }))
      this.inspectorTarget.appendChild(this.field("Vencimento em horas", "due_in_hours", node.config?.due_in_hours || "4", "number", { presets: [["2h", "2"], ["4h", "4"], ["24h", "24"], ["48h", "48"], ["3 dias", "72"]], presetSuffix: "horas", min: 1 }))
      this.renderTaskAssigneeFallbackField(node)
      this.inspectorTarget.appendChild(this.textArea("Orientação para o responsável", "notes", node.config?.notes || "Validar imóveis compatíveis antes de enviar ao cliente.", { variables: true }))
    } else if (actionType === "add_interest_note") {
      this.inspectorTarget.appendChild(this.textArea("Nota interna", "body", node.config?.body || "Registrar perfil de interesse detectado automaticamente.", { variables: true, rows: 3 }))
    } else if (actionType === "suggest_matching_properties") {
      this.inspectorTarget.appendChild(this.field("Quantidade máxima de sugestões", "limit", node.config?.limit || "5", "number", { min: 1, max: 10, presets: [["3", "3"], ["5", "5"], ["10", "10"]] }))
      this.inspectorTarget.appendChild(this.entryEventNotice("A sugestão registra uma nota interna com imóveis compatíveis. O envio ao cliente continua sendo decisão da operação."))
    } else if (actionType === "notify_broker_interest_opportunity") {
      this.inspectorTarget.appendChild(this.field("Titulo da tarefa", "title", node.config?.title || "Oportunidade de interesse para o lead", "text", { required: true }))
      this.inspectorTarget.appendChild(this.field("Vencimento em horas", "due_in_hours", node.config?.due_in_hours || "2", "number", { presets: [["2h", "2"], ["4h", "4"], ["24h", "24"], ["48h", "48"], ["3 dias", "72"]], presetSuffix: "horas", min: 1 }))
      this.renderTaskAssigneeFallbackField(node)
      this.inspectorTarget.appendChild(this.entryEventNotice("Cria uma tarefa para o responsável atual do lead agir sobre uma oportunidade detectada pela navegação e pelos imóveis compatíveis."))
    } else if (actionType === "prepare_matching_properties_whatsapp") {
      this.inspectorTarget.appendChild(this.field("Quantidade de imóveis", "limit", node.config?.limit || "3", "number", { min: 1, max: 10, presets: [["1", "1"], ["3", "3"], ["5", "5"]] }))
      this.inspectorTarget.appendChild(this.textArea("Introdução da mensagem", "message_prefix", node.config?.message_prefix || "Separei algumas opções que combinam com o que você está buscando.", { variables: true, rows: 3 }))
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

  noDistributionRulesHint() {
    return { message: "Nenhuma regra de distribuição cadastrada.", href: "/admin/distribution_rules", linkLabel: "Cadastrar regra" }
  }

  // Editor de opções (botões/lista): uma linha por opção, com limite visível.
  // Grava em um input oculto `options` (texto separado por \n), mantendo o contrato do updateNode.
  optionsListField(node, { max, maxlength }) {
    const wrap = document.createElement("div")
    wrap.className = "automation-workflow-builder__field automation-workflow-builder__options"

    const hidden = document.createElement("input")
    hidden.type = "hidden"
    hidden.dataset.field = "options"
    hidden.dataset.action = "input->automation-workflow-builder#updateNode"

    const rows = String(node.config?.options || "").split("\n").map((item) => item.trim()).filter(Boolean)
    const list = document.createElement("ol")
    list.className = "automation-workflow-builder__options-list"
    const add = document.createElement("button")
    add.type = "button"
    add.className = "automation-workflow-builder__options-add"
    add.innerHTML = '<i class="bi bi-plus-lg"></i>Adicionar opção'

    const commit = () => {
      const values = Array.from(list.querySelectorAll("input")).map((input) => input.value.trim()).filter(Boolean)
      hidden.value = values.join("\n")
      hidden.dispatchEvent(new Event("input", { bubbles: true }))
      add.disabled = list.children.length >= max
      list.querySelectorAll("button[data-remove]").forEach((button) => { button.disabled = list.children.length <= 1 })
    }

    const addRow = (value = "") => {
      const item = document.createElement("li")
      const input = document.createElement("input")
      input.className = "ax-input"
      input.value = value
      input.maxLength = maxlength
      input.placeholder = `Opção ${list.children.length + 1}`
      input.setAttribute("aria-label", `Opção ${list.children.length + 1}`)
      input.addEventListener("input", commit)
      const count = document.createElement("small")
      const refresh = () => { count.textContent = `${input.value.length}/${maxlength}` }
      input.addEventListener("input", refresh)
      refresh()
      const remove = document.createElement("button")
      remove.type = "button"
      remove.dataset.remove = "true"
      remove.className = "automation-workflow-builder__icon-btn"
      remove.setAttribute("aria-label", "Remover opção")
      remove.innerHTML = '<i class="bi bi-x-lg"></i>'
      remove.addEventListener("click", () => { item.remove(); commit() })
      item.append(input, count, remove)
      list.appendChild(item)
      return input
    }

    ;(rows.length ? rows : [""]).forEach((value) => addRow(value))
    add.addEventListener("click", () => { addRow().focus(); commit() })

    const head = this.fieldLabel(`Opções (até ${max})`, "Cada opção vira um caminho abaixo, onde você edita as respostas.", true)
    wrap.append(head, list, add, hidden)
    hidden.value = rows.join("\n")
    hidden.dataset.required = "true"
    commit()
    return wrap
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

    this.inspectorTarget.appendChild(this.field("Máximo de retentativas", "retry_attempts", node.config?.retry_attempts || "3", "number", { min: 1, max: 10, presets: [["1", "1"], ["3", "3"], ["5", "5"]] }))
    this.inspectorTarget.appendChild(this.field("Intervalo da retentativa", "retry_delay_amount", node.config?.retry_delay_amount || "15", "number", { min: 1, presets: [["5", "5"], ["15", "15"], ["30", "30"], ["60", "60"]] }))
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

  flowResultOptions() {
    return {
      generates_attendance: "Gera atendimento",
      no_attendance: "Não gera atendimento"
    }
  }

  defaultDistributionRuleId() {
    return Object.keys(this.catalog.distribution_rules || {})[0] || ""
  }

  flowResultNotice(result) {
    if (result === "generates_attendance") {
      return "Este caminho registra que gerou atendimento e vincula o lead ao destino escolhido."
    }

    return "Este caminho registra que não gerou atendimento. Use ações depois dele para responder, encerrar ou registrar a tratativa."
  }

  lifecycleActionOptions() {
    return {
      mark_no_interest: "Marcar sem interesse",
      remove_no_interest: "Remover sem interesse",
      block_lead: "Bloquear lead",
      discard_lead: "Descartar lead",
      unsubscribe_lead: "Descadastrar lead/contato",
      reactivate_lead: "Reativar lead"
    }
  }

  defaultLifecycleStage(action) {
    if (action === "unsubscribe_lead") return "Descadastrado"
    return ["remove_no_interest", "reactivate_lead"].includes(action) ? "Em Atendimento" : "Descartado"
  }


  finalActionField(node) {
    return this.checkboxField("Encerrar acompanhamento após esta intervenção", "stop_flow", this.endsFlow(node), "Quando ativo, a automação termina assim que esta intervenção for executada.")
  }

  textArea(label, field, value, config = {}) {
    const wrap = document.createElement("label")
    wrap.className = "automation-workflow-builder__field"

    const input = document.createElement("textarea")
    input.className = "ax-input automation-workflow-builder__textarea"
    input.value = value || ""
    input.dataset.field = field
    input.dataset.action = "input->automation-workflow-builder#updateNode"
    if (config.placeholder) input.placeholder = config.placeholder
    input.rows = config.rows || 5

    // Cresce com o conteúdo (até 360px) para não cobrir/cortar notas maiores.
    const grow = () => {
      input.style.height = "auto"
      input.style.height = `${Math.min(input.scrollHeight + 2, 360)}px`
    }
    input.addEventListener("input", grow)
    requestAnimationFrame(grow)

    wrap.append(this.fieldLabel(label, config.info, config.required), input)
    this.decorateControl(wrap, input, config)
    return wrap
  }

  webhookKeyValueSection({ title, description, kind, rows, keyLabel, valueLabel, keyPlaceholder, valuePlaceholder, addLabel }) {
    const section = document.createElement("section")
    section.className = "automation-workflow-builder__kv-section"
    section.dataset.webhookMapKind = kind

    const header = document.createElement("div")
    header.className = "automation-workflow-builder__kv-header"
    header.innerHTML = `
      <span>
        <strong>${this.escapeHtml(title)}</strong>
        <small>${this.escapeHtml(description)}</small>
      </span>
    `

    const list = document.createElement("div")
    list.className = "automation-workflow-builder__kv-list"

    const normalizedRows = rows.length ? rows : [{ key: "", value: "" }]
    normalizedRows.forEach((row, index) => {
      list.appendChild(this.webhookKeyValueRow({
        kind,
        index,
        row,
        keyLabel,
        valueLabel,
        keyPlaceholder,
        valuePlaceholder,
        removable: normalizedRows.length > 1 || row.key || row.value
      }))
    })

    const add = document.createElement("button")
    add.type = "button"
    add.className = "ax-btn ax-btn--sm automation-workflow-builder__kv-add"
    add.dataset.kind = kind
    add.innerHTML = `<i class="bi bi-plus-lg"></i><span>${this.escapeHtml(addLabel)}</span>`
    add.addEventListener("click", (event) => this.addWebhookMapRow(event))

    section.append(header, list, add)
    return section
  }

  webhookKeyValueRow({ kind, index, row, keyLabel, valueLabel, keyPlaceholder, valuePlaceholder, removable }) {
    const item = document.createElement("div")
    item.className = "automation-workflow-builder__kv-row"
    item.dataset.webhookMapRow = kind

    const key = this.webhookMapInput({ kind, index, part: "key", label: keyLabel, value: row.key, placeholder: keyPlaceholder })
    const value = this.webhookMapInput({ kind, index, part: "value", label: valueLabel, value: row.value, placeholder: valuePlaceholder })

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "automation-workflow-builder__kv-remove"
    remove.dataset.kind = kind
    remove.dataset.index = index
    remove.title = "Remover linha"
    remove.setAttribute("aria-label", "Remover linha")
    remove.disabled = !removable
    remove.innerHTML = '<i class="bi bi-trash"></i>'
    remove.addEventListener("click", (event) => this.removeWebhookMapRow(event))

    item.append(key, value, remove)
    return item
  }

  webhookMapInput({ kind, index, part, label, value, placeholder }) {
    const wrap = document.createElement("label")
    wrap.className = "automation-workflow-builder__kv-field"

    const text = document.createElement("span")
    text.textContent = label

    const input = document.createElement("input")
    input.className = "ax-input"
    input.type = "text"
    input.value = value || ""
    input.placeholder = placeholder
    input.dataset.webhookMap = kind
    input.dataset.index = index
    input.dataset.part = part
    input.dataset.action = "input->automation-workflow-builder#updateWebhookMap"

    wrap.append(text, input)
    return wrap
  }

  addWebhookMapRow(event) {
    if (event) event.preventDefault()

    const kind = event.currentTarget.dataset.kind
    const rows = this.currentWebhookRows(kind)
    rows.push({ key: "", value: "" })
    this.storeWebhookDraftRows(kind, rows)
    this.markWebhookRowsCustomized(kind)
    this.applyWebhookRows(kind, rows)
    this.sync()
    this.renderCanvas()
    this.refreshLiteralSummary()
    this.renderInspector()
  }

  removeWebhookMapRow(event) {
    if (event) event.preventDefault()

    const kind = event.currentTarget.dataset.kind
    const index = Number.parseInt(event.currentTarget.dataset.index, 10)
    const rows = this.currentWebhookRows(kind)
    rows.splice(index, 1)
    const nextRows = rows.length ? rows : [{ key: "", value: "" }]
    this.storeWebhookDraftRows(kind, nextRows)
    this.markWebhookRowsCustomized(kind)
    this.applyWebhookRows(kind, nextRows)
    this.sync()
    this.renderCanvas()
    this.refreshLiteralSummary()
    this.renderInspector()
  }

  updateWebhookMap(event) {
    const kind = event.currentTarget.dataset.webhookMap
    const index = Number.parseInt(event.currentTarget.dataset.index, 10)
    const part = event.currentTarget.dataset.part
    const rows = this.currentWebhookRows(kind)

    rows[index] = rows[index] || { key: "", value: "" }
    rows[index][part] = event.currentTarget.value
    this.storeWebhookDraftRows(kind, rows)
    this.markWebhookRowsCustomized(kind)
    this.applyWebhookRows(kind, rows)
    this.sync()
    this.renderCanvas()
    this.refreshLiteralSummary()
  }

  currentWebhookRows(kind) {
    const rows = Array.from(this.inspectorTarget.querySelectorAll(`[data-webhook-map-row="${kind}"]`)).map((row) => {
      const key = row.querySelector(`[data-webhook-map="${kind}"][data-part="key"]`)?.value || ""
      const value = row.querySelector(`[data-webhook-map="${kind}"][data-part="value"]`)?.value || ""
      return { key, value }
    })

    return rows.length ? rows : [{ key: "", value: "" }]
  }

  applyWebhookRows(kind, rows) {
    const node = this.selectedNode()
    if (!node) return

    node.config = node.config || {}
    if (kind === "headers") {
      node.config.headers = this.serializeHeaderRows(rows)
    } else if (kind === "payload") {
      node.config.payload_template = this.serializePayloadRows(rows)
    }
  }

  webhookRows(node, kind) {
    const draft = this.webhookMapDraftRows?.[this.webhookDraftKey(node, kind)]
    if (draft) return draft

    if (kind === "headers") return this.headerRows(node.config?.headers)

    const configuredRows = this.payloadRows(node.config?.payload_template)
    const contextTrigger = this.contextTriggerFor(node)
    const context = this.webhookContextFor(node)

    if (configuredRows.length) {
      const previousContext = this.webhookContexts()[node.config?.webhook_context_trigger]
      const previousDefault = previousContext ? this.serializePayloadRows(previousContext.payloadRows) : ""
      const configuredPayload = this.serializePayloadRows(configuredRows)

      if (node.config?.webhook_context_trigger && node.config.webhook_context_trigger !== contextTrigger && configuredPayload === previousDefault) {
        this.applyDefaultWebhookPayload(node, contextTrigger, context.payloadRows)
        return context.payloadRows
      }

      return configuredRows
    }

    this.applyDefaultWebhookPayload(node, contextTrigger, context.payloadRows)
    return context.payloadRows
  }

  applyDefaultWebhookPayload(node, contextTrigger, rows) {
    node.config = node.config || {}
    node.config.payload_template = this.serializePayloadRows(rows)
    node.config.webhook_context_trigger = contextTrigger
    this.sync()
  }

  markWebhookRowsCustomized(kind) {
    if (kind !== "payload") return

    const node = this.selectedNode()
    if (node?.config) delete node.config.webhook_context_trigger
  }

  storeWebhookDraftRows(kind, rows) {
    const node = this.selectedNode()
    if (!node) return

    this.webhookMapDraftRows[this.webhookDraftKey(node, kind)] = rows.map((row) => ({
      key: (row.key || "").toString(),
      value: (row.value || "").toString()
    }))
  }

  webhookDraftKey(node, kind) {
    return `${node.id}:${kind}`
  }

  headerRows(value = "") {
    if (value && typeof value === "object" && !Array.isArray(value)) {
      return Object.entries(value).map(([key, rowValue]) => ({ key, value: rowValue?.toString() || "" }))
    }

    return value.toString().split(/\r?\n/).map((line) => {
      const [key, ...rest] = line.split(":")
      return { key: key?.trim() || "", value: rest.join(":").trim() }
    }).filter((row) => row.key || row.value)
  }

  payloadRows(value) {
    if (!value) return []

    let parsed = value
    if (typeof value === "string") {
      try {
        parsed = JSON.parse(value)
      } catch (_error) {
        return [{ key: "raw", value }]
      }
    }

    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return []
    return this.flattenPayloadObject(parsed)
  }

  flattenPayloadObject(object, prefix = "") {
    return Object.entries(object).flatMap(([key, value]) => {
      const path = prefix ? `${prefix}.${key}` : key
      if (value && typeof value === "object" && !Array.isArray(value)) {
        return this.flattenPayloadObject(value, path)
      }

      return [{ key: path, value: Array.isArray(value) ? JSON.stringify(value) : value?.toString() || "" }]
    })
  }

  serializeHeaderRows(rows) {
    return rows.map((row) => ({ key: row.key.trim(), value: row.value.trim() }))
      .filter((row) => row.key && row.value)
      .map((row) => `${row.key}: ${row.value}`)
      .join("\n")
  }

  serializePayloadRows(rows) {
    const payload = {}

    rows.map((row) => ({ key: row.key.trim(), value: row.value.trim() }))
      .filter((row) => row.key)
      .forEach((row) => this.assignPayloadValue(payload, row.key, row.value))

    return Object.keys(payload).length ? JSON.stringify(payload) : ""
  }

  assignPayloadValue(payload, dottedKey, value) {
    const keys = dottedKey.split(".").map((key) => key.trim()).filter(Boolean)
    if (!keys.length) return

    let cursor = payload
    keys.slice(0, -1).forEach((key) => {
      cursor[key] = cursor[key] && typeof cursor[key] === "object" && !Array.isArray(cursor[key]) ? cursor[key] : {}
      cursor = cursor[key]
    })
    cursor[keys[keys.length - 1]] = value
  }

  webhookContextFor(node) {
    const trigger = this.contextTriggerFor(node)
    const contexts = this.webhookContexts()
    return contexts[trigger] || contexts.default
  }

  contextTriggerFor(node) {
    const index = this.definition.nodes.findIndex((item) => item.id === node?.id)
    const previousNodes = index >= 0 ? this.definition.nodes.slice(0, index).reverse() : []
    const contextNode = previousNodes.find((item) => ["entry", "await_event"].includes(item.type) && item.config?.trigger)
    return contextNode?.config?.trigger || this.definition.nodes.find((item) => item.type === "entry")?.config?.trigger
  }

  webhookContexts() {
    const baseRows = [
      { key: "event.name", value: "{{event.name}}" },
      { key: "event.source", value: "{{event.source}}" },
      { key: "event.occurred_at", value: "{{event.occurred_at}}" },
      { key: "lead.id", value: "{{lead.id}}" },
      { key: "lead.name", value: "{{lead.name}}" },
      { key: "lead.phone", value: "{{lead.phone}}" },
      { key: "lead.email", value: "{{lead.email}}" },
      { key: "lead.origin", value: "{{lead.origin}}" },
      { key: "lead.status", value: "{{lead.status}}" },
      { key: "agent.name", value: "{{agent.name}}" }
    ]

    const baseTokens = [
      ["{{event.name}}", "Nome técnico do evento"],
      ["{{event.source}}", "Origem do evento"],
      ["{{event.occurred_at}}", "Data e hora do evento"],
      ["{{lead.id}}", "ID do lead"],
      ["{{lead.name}}", "Nome do lead"],
      ["{{lead.phone}}", "Telefone do lead"],
      ["{{lead.email}}", "E-mail do lead"],
      ["{{lead.origin}}", "Origem do lead"],
      ["{{lead.status}}", "Etapa atual do lead"],
      ["{{agent.name}}", "Responsável atual"]
    ]

    const withBase = (context) => ({
      ...context,
      payloadRows: [...baseRows, ...(context.payloadRows || [])],
      tokens: [...baseTokens, ...(context.tokens || [])],
      payloadPlaceholder: context.payloadPlaceholder || "lead.name",
      valuePlaceholder: context.valuePlaceholder || "{{lead.name}}"
    })

    const campaignRows = [
      { key: "campaign.id", value: "{{campaign.id}}" },
      { key: "campaign.name", value: "{{campaign.name}}" },
      { key: "campaign.status", value: "{{campaign.status}}" },
      { key: "campaign.template", value: "{{campaign.template}}" },
      { key: "message.id", value: "{{campaign_message.id}}" },
      { key: "message.status", value: "{{campaign_message.status}}" },
      { key: "message.phone_number", value: "{{campaign_message.phone_number}}" },
      { key: "message.external_message_id", value: "{{campaign_message.external_message_id}}" },
      { key: "recipient.id", value: "{{recipient.id}}" },
      { key: "recipient.name", value: "{{recipient.name}}" },
      { key: "recipient.phone", value: "{{recipient.phone}}" },
      { key: "recipient.email", value: "{{recipient.email}}" },
      { key: "recipient.conversion_status", value: "{{recipient.conversion_status}}" },
      { key: "reply.button_text", value: "{{event.payload.button_text}}" },
      { key: "reply.decision", value: "{{event.payload.response_decision.action}}" }
    ]
    const campaignTokens = [
      ["{{campaign.id}}", "ID do disparo"],
      ["{{campaign.name}}", "Nome do disparo"],
      ["{{campaign.status}}", "Status do disparo"],
      ["{{campaign.template}}", "Modelo usado"],
      ["{{campaign_message.id}}", "ID da mensagem"],
      ["{{campaign_message.status}}", "Status da mensagem"],
      ["{{campaign_message.phone_number}}", "Telefone enviado"],
      ["{{campaign_message.external_message_id}}", "ID externo da Meta"],
      ["{{recipient.id}}", "ID do destinatário"],
      ["{{recipient.name}}", "Nome do destinatário"],
      ["{{recipient.phone}}", "Telefone do destinatário"],
      ["{{recipient.email}}", "E-mail do destinatário"],
      ["{{recipient.conversion_status}}", "Status de conversão do destinatário"],
      ["{{event.payload.button_text}}", "Botão clicado"],
      ["{{event.payload.response_decision.action}}", "Decisão configurada na campanha"]
    ]

    return {
      default: withBase({
        label: "evento da automação",
        description: "Payload padrão com dados do evento, lead e responsável atual.",
        badge: "Contexto geral"
      }),
      lead_created: withBase({
        label: "lead criado",
        description: "Este webhook acompanha a entrada de um novo lead e seus dados comerciais básicos.",
        badge: "Lead"
      }),
      lead_stage_changed: withBase({
        label: "mudança de etapa",
        description: "Este webhook acompanha a etapa anterior e a nova etapa do lead.",
        badge: "Etapa",
        payloadRows: [
          { key: "stage.from", value: "{{event.payload.from}}" },
          { key: "stage.to", value: "{{event.payload.to}}" }
        ],
        tokens: [
          ["{{event.payload.from}}", "Etapa anterior"],
          ["{{event.payload.to}}", "Nova etapa"]
        ]
      }),
      lead_idle: withBase({
        label: "lead parado",
        description: "Este webhook acompanha leads sem andamento dentro da janela configurada.",
        badge: "Rotina",
        payloadRows: [{ key: "idle.hours", value: "{{event.payload.idle_hours}}" }],
        tokens: [["{{event.payload.idle_hours}}", "Horas sem andamento"]]
      }),
      scheduled_routine: withBase({
        label: "rotina agendada",
        description: "Este webhook acompanha uma execução recorrente filtrada pela automação.",
        badge: "Rotina",
        payloadRows: [{ key: "workflow.id", value: "{{event.payload.workflow_id}}" }],
        tokens: [["{{event.payload.workflow_id}}", "ID do fluxo executado"]]
      }),
      whatsapp_received: withBase({
        label: "resposta no WhatsApp",
        description: "Este webhook acompanha uma mensagem recebida do lead no WhatsApp.",
        badge: "WhatsApp",
        payloadPlaceholder: "whatsapp.message_body",
        valuePlaceholder: "{{whatsapp.message_body}}",
        payloadRows: [
          { key: "whatsapp.message_id", value: "{{event.payload.whatsapp_message_id}}" },
          { key: "whatsapp.external_message_id", value: "{{event.payload.wa_message_id}}" },
          { key: "whatsapp.phone", value: "{{whatsapp.phone}}" },
          { key: "whatsapp.bsuid", value: "{{whatsapp.bsuid}}" },
          { key: "whatsapp.message_body", value: "{{whatsapp.message_body}}" }
        ],
        tokens: [
          ["{{event.payload.whatsapp_message_id}}", "ID interno da mensagem"],
          ["{{event.payload.wa_message_id}}", "ID externo da Meta"],
          ["{{whatsapp.phone}}", "Telefone recebido"],
          ["{{whatsapp.bsuid}}", "BSUID do contato"],
          ["{{whatsapp.message_body}}", "Texto da mensagem recebida"]
        ]
      }),
      proposal_viewed: withBase({
        label: "proposta visualizada",
        description: "Este webhook acompanha a abertura pública de uma proposta.",
        badge: "Proposta",
        payloadRows: [{ key: "proposal.id", value: "{{event.payload.proposal_id}}" }],
        tokens: [["{{event.payload.proposal_id}}", "ID da proposta"]]
      }),
      proposal_accepted: withBase({
        label: "proposta aceita",
        description: "Este webhook acompanha o aceite público de uma proposta.",
        badge: "Proposta",
        payloadRows: [
          { key: "proposal.id", value: "{{event.payload.proposal_id}}" },
          { key: "proposal.status", value: "{{event.payload.status}}" }
        ],
        tokens: [
          ["{{event.payload.proposal_id}}", "ID da proposta"],
          ["{{event.payload.status}}", "Status informado"]
        ]
      }),
      proposal_rejected: withBase({
        label: "proposta recusada",
        description: "Este webhook acompanha a recusa pública de uma proposta.",
        badge: "Proposta",
        payloadRows: [
          { key: "proposal.id", value: "{{event.payload.proposal_id}}" },
          { key: "proposal.status", value: "{{event.payload.status}}" }
        ],
        tokens: [
          ["{{event.payload.proposal_id}}", "ID da proposta"],
          ["{{event.payload.status}}", "Status informado"]
        ]
      }),
      whatsapp_campaign_started: withBase({
        label: "disparo WhatsApp iniciado",
        description: "Este webhook acompanha o início do processamento de uma campanha.",
        badge: "Disparo WhatsApp",
        payloadRows: campaignRows,
        tokens: campaignTokens
      }),
      whatsapp_campaign_completed: withBase({
        label: "disparo WhatsApp concluído",
        description: "Este webhook acompanha o fechamento dos envios da campanha.",
        badge: "Disparo WhatsApp",
        payloadRows: campaignRows,
        tokens: campaignTokens
      }),
      whatsapp_campaign_failed: withBase({
        label: "disparo WhatsApp com erro",
        description: "Este webhook acompanha falhas críticas no processamento da campanha.",
        badge: "Disparo WhatsApp",
        payloadRows: [...campaignRows, { key: "campaign.error", value: "{{event.payload.error}}" }],
        tokens: [...campaignTokens, ["{{event.payload.error}}", "Erro da campanha"]]
      }),
      whatsapp_campaign_message_sent: withBase({
        label: "mensagem de disparo enviada",
        description: "Este webhook acompanha uma mensagem aceita para envio pela Cloud API.",
        badge: "Mensagem WhatsApp",
        payloadRows: campaignRows,
        tokens: campaignTokens,
        payloadPlaceholder: "recipient.name",
        valuePlaceholder: "{{recipient.name}}"
      }),
      whatsapp_campaign_message_delivered: withBase({
        label: "mensagem de disparo entregue",
        description: "Este webhook acompanha confirmação de entrega da Meta.",
        badge: "Mensagem WhatsApp",
        payloadRows: campaignRows,
        tokens: campaignTokens,
        payloadPlaceholder: "recipient.name",
        valuePlaceholder: "{{recipient.name}}"
      }),
      whatsapp_campaign_message_read: withBase({
        label: "mensagem de disparo lida",
        description: "Este webhook acompanha confirmação de leitura da Meta.",
        badge: "Mensagem WhatsApp",
        payloadRows: campaignRows,
        tokens: campaignTokens,
        payloadPlaceholder: "recipient.name",
        valuePlaceholder: "{{recipient.name}}"
      }),
      whatsapp_campaign_message_failed: withBase({
        label: "mensagem de disparo falhou",
        description: "Este webhook acompanha uma falha no envio de uma mensagem da campanha.",
        badge: "Mensagem WhatsApp",
        payloadRows: [...campaignRows, { key: "message.failure_reason", value: "{{campaign_message.failure_reason}}" }],
        tokens: [...campaignTokens, ["{{campaign_message.failure_reason}}", "Motivo da falha"]],
        payloadPlaceholder: "recipient.name",
        valuePlaceholder: "{{recipient.name}}"
      }),
      whatsapp_campaign_message_replied: withBase({
        label: "destinatário respondeu um disparo",
        description: "Este webhook conecta a resposta ou clique do destinatário ao disparo e à mensagem de origem.",
        badge: "Mensagem WhatsApp",
        payloadRows: [
          ...campaignRows,
          { key: "reply.inbound_message_id", value: "{{event.payload.inbound_whatsapp_message_id}}" },
          { key: "reply.body", value: "{{event.payload.message_body}}" },
          { key: "reply.button_text", value: "{{event.payload.button_text}}" },
          { key: "reply.decision_action", value: "{{event.payload.response_decision.action}}" }
        ],
        tokens: [
          ...campaignTokens,
          ["{{event.payload.inbound_whatsapp_message_id}}", "ID da resposta recebida"],
          ["{{event.payload.message_body}}", "Texto recebido"],
          ["{{event.payload.button_text}}", "Botão clicado"],
          ["{{event.payload.response_decision.action}}", "Decisão configurada na campanha"]
        ],
        payloadPlaceholder: "recipient.name",
        valuePlaceholder: "{{recipient.name}}"
      }),
      interest_profile_detected: withBase(this.interestWebhookContext("interesse em imóveis detectado")),
      matching_property_found: withBase(this.interestWebhookContext("imóvel compatível encontrado", [
        { key: "match.minimum_score", value: "{{event.payload.minimum_score}}" }
      ], [["{{event.payload.minimum_score}}", "Score mínimo usado no filtro"]])),
      lead_without_matching_property: withBase(this.interestWebhookContext("lead sem imóvel compatível")),
      interest_profile_incomplete: withBase(this.interestWebhookContext("perfil de interesse incompleto")),
      interested_property_price_dropped: withBase(this.interestWebhookContext("imóvel de interesse baixou preço")),
      lead_repeated_similar_property_views: withBase(this.interestWebhookContext("lead visitou imóveis parecidos"))
    }
  }

  interestWebhookContext(label, rows = [], tokens = []) {
    return {
      label,
      description: "Este webhook acompanha sinais da Inteligência de Interesse e imóveis compatíveis quando existirem no evento.",
      badge: "Interesse",
      payloadRows: [
        { key: "interest.profile", value: "{{event.payload.profile}}" },
        { key: "interest.matches", value: "{{event.payload.matches}}" },
        ...rows
      ],
      tokens: [
        ["{{event.payload.profile}}", "Perfil de interesse detectado"],
        ["{{event.payload.matches}}", "Imóveis compatíveis no evento"],
        ...tokens
      ]
    }
  }

  webhookContextPanel(context) {
    const panel = document.createElement("section")
    panel.className = "automation-workflow-builder__webhook-context"
    panel.innerHTML = `
      <span class="automation-workflow-builder__webhook-context-icon"><i class="bi bi-diagram-2"></i></span>
      <span>
        <strong>${this.escapeHtml(context.badge || "Contexto")}: ${this.escapeHtml(context.label)}</strong>
        <small>${this.escapeHtml(context.description)}</small>
      </span>
    `
    return panel
  }

  escapeHtml(value) {
    return value.toString().replace(/[&<>"']/g, (char) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      "\"": "&quot;",
      "'": "&#39;"
    }[char]))
  }

  webhookTokenReference(context = this.webhookContexts().default) {
    const wrap = document.createElement("section")
    wrap.className = "automation-workflow-builder__token-reference"
    const tokens = (context.tokens || []).map(([token, description]) => `
        <li><code>${this.escapeHtml(token)}</code><span>${this.escapeHtml(description)}</span></li>
      `).join("")
    wrap.innerHTML = `
      <div>
        <i class="bi bi-braces"></i>
        <span>
          <strong>Tokens para este contexto</strong>
          <small>Lista reativa ao evento que trouxe o lead até esta etapa. Use no campo Valor do de/para.</small>
        </span>
      </div>
      <ul>
        ${tokens}
      </ul>
    `
    return wrap
  }

  webhookTestPanel() {
    const wrap = document.createElement("div")
    wrap.className = "automation-workflow-builder__webhook-test"

    const button = document.createElement("button")
    button.type = "button"
    button.className = "ax-btn ax-btn--sm"
    button.dataset.action = "click->automation-workflow-builder#testWebhook"
    button.innerHTML = '<i class="bi bi-broadcast"></i><span>Testar webhook</span>'

    const result = document.createElement("span")
    result.dataset.webhookTestResult = "true"
    result.textContent = "Envia payload de teste e registra a entrega."

    wrap.append(button, result)
    return wrap
  }

  testWebhook(event) {
    event.preventDefault()
    const node = this.selectedNode()
    if (!node) return

    const result = this.inspectorTarget.querySelector("[data-webhook-test-result]")
    if (result) result.textContent = "Enviando teste..."

    const formData = new FormData()
    formData.append("url", node.config?.url || "")
    formData.append("http_method", node.config?.http_method || "post")
    formData.append("headers", node.config?.headers || "")
    formData.append("payload_template", node.config?.payload_template || "")

    fetch("/admin/automacoes/test_webhook", {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
      },
      body: formData
    })
      .then((response) => response.json().then((data) => ({ ok: response.ok, data })))
      .then(({ ok, data }) => {
        if (!ok || !data.ok) throw new Error(data.error || `Falha HTTP ${data.response_code || "-"}`)
        if (result) result.textContent = `Teste entregue. HTTP ${data.response_code || "-"}`
      })
      .catch((error) => {
        if (result) result.textContent = error.message
      })
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
      await_whatsapp_response: { label: "Aguardar resposta WhatsApp", config: { timeout_amount: "1", timeout_unit: "days" } },
      response_condition: { label: "Condição de resposta", config: { category: "template_buttons", field: "interaction.button_text", operator: "equals", value: "" } },
      response_fallback: { label: "Fallback de resposta", config: { fallback_type: "no_match" } },
      response_router: { label: "Resposta condicional", config: { category: "template_buttons", timeout_amount: "1", timeout_unit: "days", routes: [this.defaultResponseRoute("template_buttons", 0)] } },
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

  workflowLayout() {
    const compactLevels = this.workflowLevels()
    const nodeRows = new Map()

    compactLevels.forEach((nodes, levelIndex) => {
      const usedRows = new Set()

      nodes.forEach((node, nodeIndex) => {
        const preferredRow = this.preferredWorkflowRow(node, nodeIndex, levelIndex, nodeRows)
        const row = this.availableWorkflowRow(preferredRow, usedRows)
        nodeRows.set(node.id, row)
        usedRows.add(row)
      })
    })

    this.centerWorkflowJoinNodes(compactLevels, nodeRows)

    const rowCount = Math.max(
      1,
      ...compactLevels.map((nodes) => nodes.length),
      ...Array.from(nodeRows.values()).map((row) => row + 1)
    )

    return {
      rowCount,
      nodeRows,
      levels: compactLevels.map((nodes) => {
        const slots = Array.from({ length: rowCount }, () => null)
        nodes.forEach((node) => {
          const row = nodeRows.get(node.id)
          if (Number.isInteger(row) && row >= 0 && row < rowCount) slots[row] = node
        })
        return slots
      })
    }
  }

  preferredWorkflowRow(node, nodeIndex, levelIndex, nodeRows) {
    const incomingRows = this.incomingEdges(node.id)
      .map((edge) => nodeRows.get(edge.from))
      .filter((row) => Number.isInteger(row))

    if (incomingRows.length > 0) return Math.round(incomingRows.reduce((sum, row) => sum + row, 0) / incomingRows.length)
    if (levelIndex === 0) return 0

    return nodeIndex
  }

  availableWorkflowRow(preferredRow, usedRows) {
    const base = Math.max(0, Number.isInteger(preferredRow) ? preferredRow : 0)
    if (!usedRows.has(base)) return base

    for (let distance = 1; distance < 24; distance += 1) {
      const down = base + distance
      if (!usedRows.has(down)) return down

      const up = base - distance
      if (up >= 0 && !usedRows.has(up)) return up
    }

    return usedRows.size
  }

  centerWorkflowJoinNodes(levels, nodeRows) {
    levels.forEach((nodes) => {
      if (nodes.length !== 1) return

      const node = nodes[0]
      const outgoingRows = this.outgoingEdges(node.id)
        .map((edge) => nodeRows.get(edge.to))
        .filter((row) => Number.isInteger(row))

      if (outgoingRows.length < 2) return

      const centeredRow = Math.round(outgoingRows.reduce((sum, row) => sum + row, 0) / outgoingRows.length)
      nodeRows.set(node.id, centeredRow)
    })
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

  applyStepPreset(node, preset) {
    const presets = {
      button_more: {
        label: "Se botão: Saiba mais",
        config: { category: "template_buttons", field: "interaction.button_text", operator: "equals", value: "Saiba mais" }
      },
      button_not_interest: {
        label: "Se botão: Não tenho interesse",
        config: { category: "template_buttons", field: "interaction.button_text", operator: "equals", value: "Não tenho interesse" }
      },
      human_help: {
        label: "Se pediu atendimento humano",
        config: { category: "lead_text", field: "message.body", operator: "contains", value: "atendimento" }
      },
      timeout_fallback: {
        label: "Sem resposta",
        config: { fallback_type: "timeout" }
      },
      unknown_fallback: {
        label: "Resposta não reconhecida",
        config: { fallback_type: "no_match" }
      }
    }
    const presetConfig = presets[preset]
    if (!presetConfig) return

    node.label = presetConfig.label
    node.config = { ...(node.config || {}), ...presetConfig.config }
  }

  nodeTitle(node) {
    return {
      entry: "Quando observar",
      wait: "Espera",
      await_event: "Aguardar evento",
      await_whatsapp_response: "Aguardar resposta WhatsApp",
      response_condition: "Condição de resposta",
      response_fallback: "Fallback de resposta",
      response_router: "Resposta condicional",
      action: "Intervenção",
      condition: "Condição"
    }[node.type] || "Etapa"
  }

  // Cor por função da etapa (CSS: [data-tone] define --tone).
  nodeTone(node) {
    if (node.type === "action") {
      const type = node.config?.action_type || ""
      if (type.startsWith("send_whatsapp") || type === "prepare_matching_properties_whatsapp") return "whatsapp"
      if (type === "transfer_to_attendant" || type === "set_flow_result") return "attendance"
      if (type === "send_webhook") return "webhook"
      if (type === "capture_answer") return "capture"
      if (["move_stage", "update_lead_lifecycle", "assign_agent"].includes(type)) return "stage"
      return "task"
    }
    return {
      entry: "entry",
      wait: "wait",
      await_event: "event",
      await_whatsapp_response: "whatsapp",
      response_condition: "response",
      response_router: "response",
      response_fallback: "fallback",
      condition: "condition"
    }[node.type] || "task"
  }

  nodeIcon(node) {
    return {
      entry: "bi-people-fill",
      wait: "bi-clock-fill",
      await_event: "bi-broadcast-pin",
      await_whatsapp_response: "bi-whatsapp",
      response_condition: "bi-ui-checks-grid",
      response_fallback: "bi-signpost-2",
      response_router: "bi-ui-checks-grid",
      action: "bi-lightning-charge-fill",
      condition: "bi-signpost-split-fill"
    }[node.type] || "bi-square-fill"
  }

  actionIcon(actionType) {
    return {
      create_task: "bi-check2-square",
      send_whatsapp: "bi-whatsapp",
      send_whatsapp_template: "bi-chat-square-text",
      send_whatsapp_buttons: "bi-ui-radios",
      send_whatsapp_list: "bi-list-ul",
      transfer_to_attendant: "bi-headset",
      send_webhook: "bi-broadcast",
      set_flow_result: "bi-signpost-split",
      move_stage: "bi-arrow-right-circle",
      update_lead_lifecycle: "bi-arrow-repeat",
      assign_agent: "bi-person-x",
      add_note: "bi-journal-text",
      create_interest_curation_task: "bi-house-heart",
      add_interest_note: "bi-stars",
      suggest_matching_properties: "bi-building-check",
      notify_broker_interest_opportunity: "bi-bell",
      prepare_matching_properties_whatsapp: "bi-whatsapp",
      generate_interest_ai_summary: "bi-magic",
      capture_answer: "bi-input-cursor-text"
    }[actionType] || "bi-lightning-charge"
  }

  actionDescription(actionType) {
    return {
      create_task: "Cria uma tarefa para o time acompanhar o lead no prazo definido.",
      send_whatsapp: "Envia uma mensagem livre pelo WhatsApp quando a etapa chegar aqui.",
      send_whatsapp_template: "Dispara um modelo WhatsApp aprovado e reutilizável.",
      send_whatsapp_buttons: "Pergunta com até 3 botões. Cada botão vira um caminho para você continuar.",
      send_whatsapp_list: "Pergunta com uma lista de até 10 opções. Cada opção vira um caminho.",
      transfer_to_attendant: "Entrega a conversa a um atendente da fila, com as respostas do cliente já anotadas.",
      send_webhook: "Envia o evento da automação para um endpoint externo com payload configurável.",
      set_flow_result: "Define se o caminho gera atendimento e qual regra assume o destino.",
      move_stage: "Atualiza a etapa operacional do lead como apoio ao acompanhamento.",
      update_lead_lifecycle: "Marca sem interesse, bloqueia, descarta ou reativa o lead com registro no histórico.",
      assign_agent: "Ação vertical legada. Use Distribuição de Leads para responsável, fila e aceite.",
      add_note: "Registra uma nota interna no histórico do lead.",
      create_interest_curation_task: "Cria uma tarefa para o responsável do lead curar imóveis aderentes ao perfil.",
      add_interest_note: "Registra no histórico o perfil de interesse detectado pela navegação e pelos dados do lead.",
      suggest_matching_properties: "Busca imóveis compatíveis e registra sugestões para a operação revisar.",
      notify_broker_interest_opportunity: "Cria uma tarefa de oportunidade para o responsável atual do lead.",
      prepare_matching_properties_whatsapp: "Prepara uma mensagem com imóveis sugeridos, respeitando revisão humana.",
      generate_interest_ai_summary: "Gera classificação frio, morno ou quente com resumo inteligente do interesse.",
      capture_answer: "Guarda o que o cliente respondeu (e-mail, nome, telefone...) para usar nas próximas mensagens e no cadastro do lead."
    }[actionType] || "Executa uma intervenção automática no lead."
  }

  actionBadge(actionType) {
    return {
      create_task: "tarefa",
      send_whatsapp: "mensagem",
      send_whatsapp_template: "modelo",
      send_whatsapp_buttons: "pergunta",
      send_whatsapp_list: "pergunta",
      transfer_to_attendant: "atendente",
      set_flow_result: "resultado",
      move_stage: "etapa",
      update_lead_lifecycle: "ciclo",
      add_note: "histórico",
      create_interest_curation_task: "curadoria",
      add_interest_note: "interesse",
      suggest_matching_properties: "match",
      notify_broker_interest_opportunity: "alerta",
      prepare_matching_properties_whatsapp: "revisão",
      generate_interest_ai_summary: "IA",
      capture_answer: "dados"
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
    if (node.type === "await_whatsapp_response") {
      return `WhatsApp ou timeout de ${node.config?.timeout_amount || 1} ${this.unitLabel(node.config?.timeout_unit)}`
    }
    if (node.type === "response_condition") {
      const category = this.responseRouterCategoryOptions()[node.config?.category || "template_buttons"]
      const operator = this.valueLabel(this.responseRouterOperatorOptions(), node.config?.operator || "equals", "Igual")
      const expectedValue = this.responseConditionExpectedValueSummary(node)
      return [category, operator, expectedValue].filter(Boolean).join(" · ")
    }
    if (node.type === "response_fallback") {
      return this.responseFallbackDetails()[node.config?.fallback_type || "no_match"]?.title || "Resposta não reconhecida"
    }
    if (node.type === "response_router") {
      const category = this.responseRouterCategoryOptions()[node.config?.category || "template_buttons"]
      const count = this.responseRoutes(node).length
      return `${category} · ${count} fluxo(s) · timeout de ${node.config?.timeout_amount || 1} ${this.unitLabel(node.config?.timeout_unit)}`
    }
    if (node.type === "action") {
      if (node.config?.action_type === "set_flow_result") return this.flowResultNodeSummary(node)
      const label = this.actionLabel(node.config?.action_type) || "Selecione a intervenção"
      return this.endsFlow(node) ? `${label} · encerra acompanhamento` : label
    }
    if (node.type === "condition") return node.config?.operator === "or" ? "OU - pelo menos um criterio" : "E - todos os criterios"
    return ""
  }

  flowResultNodeSummary(node) {
    const result = node.config?.result || "no_attendance"
    const resultLabel = this.valueLabel(this.flowResultOptions(), result, "Não gera atendimento")
    const destination = result === "generates_attendance" ? this.valueLabel(this.catalog.distribution_rules, node.config?.distribution_rule_id, "") : ""
    const summary = [resultLabel, destination].filter(Boolean).join(" · ")

    return this.endsFlow(node) ? `${summary} · encerra acompanhamento` : summary
  }

  // Operadores que não comparam com um valor digitado.
  valueFreeOperator(operator) {
    return ["present", "valid_email", "valid_phone", "valid_number"].includes(operator)
  }

  responseConditionExpectedValueSummary(node) {
    if (this.valueFreeOperator(node.config?.operator || "equals")) return ""

    const value = String(node.config?.value || "").trim().replace(/\s+/g, " ")
    if (!value) return ""

    return this.truncateSummaryValue(value)
  }

  truncateSummaryValue(value, maxLength = 28) {
    if (value.length <= maxLength) return value
    return `${value.slice(0, maxLength - 1).trim()}…`
  }

  entryEventSummary(node) {
    const rules = this.distributionRulesCardPart(node)

    if (node.config?.trigger === "lead_stage_changed") {
      const from = node.config?.from_stage || "qualquer etapa"
      const to = node.config?.to_stage || "qualquer etapa"
      return [`de ${from} para ${to}`, rules].filter(Boolean).join(" · ")
    }

    if (node.config?.trigger === "lead_created") {
      const parts = []
      if (node.config?.stage) parts.push(node.config.stage)
      if (node.config?.source) parts.push(node.config.source)
      if (rules) parts.push(rules)
      return parts.join(" · ")
    }

    if (node.config?.trigger === "lead_idle") {
      const hours = node.config?.idle_hours || "48"
      const stage = node.config?.stage ? ` · ${node.config.stage}` : ""
      const source = node.config?.source ? ` · ${node.config.source}` : ""
      return `${hours}h sem ação${stage}${source}${rules ? ` · ${rules}` : ""}`
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
      return `${frequency}${stage}${source}${rules ? ` · ${rules}` : ""}`
    }

    if (node.config?.trigger === "whatsapp_received") {
      const parts = []
      if (node.config?.stage) parts.push(node.config.stage)
      if (node.config?.message_contains) parts.push(`contém "${node.config.message_contains}"`)
      if (node.config?.message_not_contains) parts.push(`não contém "${node.config.message_not_contains}"`)
      if (rules) parts.push(rules)
      return parts.join(" · ")
    }

    if (this.proposalEvents().includes(node.config?.trigger)) {
      return [node.config?.stage ? `lead em ${node.config.stage}` : "", rules].filter(Boolean).join(" · ")
    }

    if (this.interestEvents().includes(node.config?.trigger)) {
      const parts = []
      if (node.config?.stage) parts.push(node.config.stage)
      if (node.config?.source) parts.push(node.config.source)
      if (node.config?.minimum_score && node.config?.trigger === "matching_property_found") parts.push(`score >= ${node.config.minimum_score}`)
      if (rules) parts.push(rules)
      return parts.join(" · ")
    }

    return rules
  }

  distributionRulesCardPart(node) {
    const names = this.selectedDistributionRuleNames(node)
    if (!names.length) return ""

    return `Regras: ${this.truncateSummaryValue(names.join(", "), 42)}`
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
