import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "action", "preview", "thread", "simTitle", "toggleAll"]
  static messageCopy = {
    send_message: ["Mensagem automática", ""],
    send_url: ["Mensagem (opcional)", "Ex: Aqui está o link que você pediu"],
    create_task: ["Confirmação para o cliente (opcional)", "Ex: Recebemos seu interesse! Um consultor retorna em breve."]
  }
  static incomplete = { distribute_lead: "escolher a fila", send_to_user: "escolher o usuário", run_automation: "escolher a automação", send_url: "informar o link" }
  static values = { ruleAgents: Object, defaultReply: String, defaultOutside: String, newUrl: String }

  static dayLabels = { mon: "Seg", tue: "Ter", wed: "Qua", thu: "Qui", fri: "Sex", sat: "Sáb", sun: "Dom" }

  connect() {
    this.activeRow = this.rowTargets[0]
    this.refresh()
    this.openIncompleteRows()
  }

  // Depois de um salvamento recusado, abre os botões que ainda precisam de ajuste.
  openIncompleteRows() {
    if (!this.element.querySelector(".ax-inline-notice--danger, .ax-inline-notice[data-tone='danger']")) return

    this.rowTargets.forEach((row) => { if (this.rowStatus(row).state === "todo") this.setRowCollapsed(row, false) })
    this.syncToggleAll()
  }

  // Novo fluxo: escolher o template recarrega a tela com os botões dele (o nome sugerido acompanha o template).
  changeTemplate(event) {
    const url = new URL(this.newUrlValue, window.location.origin)
    if (event.target.value) url.searchParams.set("whatsapp_template_id", event.target.value)
    window.Turbo ? window.Turbo.visit(url.toString()) : (window.location.href = url.toString())
  }

  // Abre/fecha a configuração de um botão (todos começam fechados, inclusive na edição).
  toggleRow(event) {
    const row = event.currentTarget.closest("[data-whatsapp-response-flow-target='row']")
    if (!row) return

    this.setRowCollapsed(row, !row.classList.contains("is-collapsed"))
    this.syncToggleAll()
  }

  toggleAll() {
    const expand = this.rowTargets.some((row) => row.classList.contains("is-collapsed"))
    this.rowTargets.forEach((row) => this.setRowCollapsed(row, !expand))
    this.syncToggleAll()
  }

  setRowCollapsed(row, collapsed) {
    row.classList.toggle("is-collapsed", collapsed)
    row.querySelector(".wtf-row__head")?.setAttribute("aria-expanded", String(!collapsed))
    const panel = row.querySelector(".wtf-row__panel")
    if (panel) panel.inert = collapsed
  }

  syncToggleAll() {
    if (!this.hasToggleAllTarget) return

    const anyCollapsed = this.rowTargets.some((row) => row.classList.contains("is-collapsed"))
    this.toggleAllTarget.querySelector("span").textContent = anyCollapsed ? "Expandir todos" : "Recolher todos"
    this.toggleAllTarget.querySelector("i").className = `bi ${anyCollapsed ? "bi-arrows-expand" : "bi-arrows-collapse"} ax-ico`
  }

  // Cartões de ação: escolhem o valor do select (que continua sendo o campo enviado).
  pickAction(event) {
    const choice = event.currentTarget
    const select = choice.closest("[data-whatsapp-response-flow-target='row']")?.querySelector("[data-whatsapp-response-flow-target='action']")
    if (!select || select.value === choice.dataset.value) return

    select.value = choice.dataset.value
    select.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // Detalhe curto mostrado no cabeçalho do botão (a ação já aparece no chip).
  rowSummary(row, action) {
    const value = (suffix) => row.querySelector(`[name$='[${suffix}]']`)?.value.trim() || ""
    const selected = (selector) => [...(row.querySelector(selector)?.selectedOptions || [])].filter((o) => o.value).map((o) => o.text)
    let detail = ""
    if (action === "distribute_lead") {
      const agents = selected("[data-response-role='target-admin']")
      detail = [selected("[data-response-role='distribution-rule']")[0], agents.length ? `${agents.length} atendente(s)` : "todos os atendentes"].filter(Boolean).join(" · ")
    }
    if (action === "send_to_user") detail = selected("[name$='[target_user_id]']")[0] || ""
    if (action === "run_automation") detail = selected("[name$='[automation_workflow_id]']")[0] || ""
    if (action === "send_url") detail = value("url")
    if (action === "send_message") detail = value("message")
    if (action === "create_task") {
      const due = selected("[name$='[task_due_minutes]']")[0]
      const who = selected("[name$='[task_user_id]']")[0] || "responsável do lead"
      detail = [value("task_title") || "Acompanhar resposta", who, due].filter(Boolean).join(" · ")
    }
    if (action === "record_only") detail = "Só registra o clique"
    return detail
  }

  // Estado de cada botão: pronto ou o que ainda falta (espelha as validações do servidor).
  rowStatus(row) {
    const action = row.querySelector("[data-whatsapp-response-flow-target='action']")?.value || "record_only"
    const value = (suffix) => row.querySelector(`[name$='[${suffix}]']`)?.value.trim() || ""
    const missing = {
      distribute_lead: !value("distribution_rule_id"),
      send_to_user: !value("target_user_id"),
      run_automation: !value("automation_workflow_id"),
      send_url: !value("url")
    }[action]
    return missing ? { state: "todo", text: `Falta ${this.constructor.incomplete[action]}` } : { state: "done", text: "Pronto" }
  }

  activate({ currentTarget }) {
    if (this.activeRow === currentTarget) return
    this.activeRow = currentTarget
    this.simulate()
  }

  refresh() {
    this.rowTargets.forEach((row) => {
      const action = row.querySelector("[data-whatsapp-response-flow-target='action']")?.value || "record_only"
      row.querySelectorAll("[data-response-field]").forEach((field) => {
        const type = field.dataset.responseField
        field.hidden = !this.visibleField(action, type)
      })
      // Com horário de atendimento ligado, valem as mensagens de dentro/fora do horário: a mensagem simples e os detalhes se ajustam.
      const hoursOn = !!row.querySelector("input[type='checkbox'][name$='[business_hours][enabled]']")?.checked
      const detail = row.querySelector("[data-hours-detail]")
      if (detail) detail.hidden = !hoursOn
      const plain = row.querySelector("[data-response-field='message']")
      if (plain && action === "send_message" && hoursOn) plain.hidden = true
      const copy = this.constructor.messageCopy[action]
      if (plain && copy) {
        plain.querySelector("[data-message-label]").textContent = copy[0]
        const input = plain.querySelector("textarea")
        if (input) input.placeholder = copy[1]
      }
      row.querySelectorAll("[data-response-hint]").forEach((hint) => { hint.hidden = hint.dataset.responseHint !== action })
      this.refreshAttendantOptions(row)
      this.refreshBadge(row, action)
    })
    this.simulate()
    this.refreshProgress()
  }

  refreshBadge(row, action) {
    row.dataset.responseAction = action
    let icon = ""
    let label = row.querySelector("[data-whatsapp-response-flow-target='action']")?.selectedOptions[0]?.text || ""
    row.querySelectorAll(".wtf-choice").forEach((choice) => {
      const on = choice.dataset.value === action
      choice.setAttribute("aria-checked", String(on))
      if (on) { icon = choice.dataset.icon; label = choice.dataset.label }
    })
    const chip = row.querySelector("[data-row-chip]")
    if (chip) chip.textContent = label
    const chipIcon = row.querySelector("[data-row-chip-icon]")
    if (chipIcon && icon) chipIcon.className = `bi ${icon}`
    const summary = row.querySelector("[data-row-summary]")
    if (summary) summary.textContent = this.rowSummary(row, action)
    const status = this.rowStatus(row)
    const badge = row.querySelector("[data-row-state]")
    if (badge) {
      badge.textContent = status.text
      badge.dataset.state = status.state
    }
  }

  // Progresso e checklist da revisão: template, nome e um item por botão.
  refreshProgress() {
    const guided = (name) => this.element.querySelector(`[data-guided='${name}']`)
    if (!guided("progressBar")) return

    const templateInput = this.element.querySelector("[name='whatsapp_response_flow[whatsapp_template_id]']")
    const hasTemplate = !!templateInput?.value
    const hasName = !!this.element.querySelector("[name='whatsapp_response_flow[name]']")?.value.trim()
    const statuses = this.rowTargets.map((row) => ({ row, ...this.rowStatus(row) }))
    const pending = statuses.filter((status) => status.state === "todo")
    const buttonsOk = statuses.length > 0 && pending.length === 0
    const done = (hasTemplate ? 1 : 0) + (hasName ? 1 : 0) + statuses.length - pending.length
    const total = 2 + statuses.length
    const ready = hasTemplate && hasName && buttonsOk

    const states = { 1: hasTemplate && hasName, 2: true, 3: buttonsOk, 4: ready }
    this.element.querySelectorAll("[data-guided-step]").forEach((section) => { section.dataset.state = states[section.dataset.guidedStep] ? "done" : "todo" })
    this.element.querySelectorAll(".ax-guided-steps-nav__item").forEach((item) => { item.dataset.state = states[item.dataset.step] ? "done" : "todo" })

    const check = (key, state, text) => {
      const item = this.element.querySelector(`[data-check='${key}']`)
      if (!item) return
      item.dataset.state = state
      item.querySelector("span").textContent = text
    }
    check("template", hasTemplate ? "done" : "todo", hasTemplate ? "Template escolhido" : "Escolha o template")
    check("name", hasName ? "done" : "todo", hasName ? "Nome do fluxo" : "Dê um nome ao fluxo")
    check("buttons", buttonsOk ? "done" : "todo", !statuses.length ? "Escolha um template para ver os botões" : (buttonsOk ? `${statuses.length} botão(ões) configurado(s)` : `${pending.length} botão(ões) precisam de ajuste`))

    const first = pending[0]
    guided("progressBar").style.width = `${Math.round((done / total) * 100)}%`
    guided("progressCount").textContent = `${done} de ${total}`
    guided("progressLabel").textContent = ready ? "Pronto para salvar"
      : (!hasTemplate ? "Falta escolher o template" : (!hasName ? "Falta o nome" : `Ajustar o botão “${first.row.querySelector(".wtf-row__btn strong")?.textContent}”`))
    this.element.querySelector("form")?.classList.toggle("is-ready", ready)
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
    section.querySelector("input:not([type='hidden']):not([type='checkbox']), select:not([hidden]), button[type='submit']")?.focus({ preventScroll: true })
  }

  // Monta o preview do template com o botão ativo em destaque e a conversa simulada.
  simulate() {
    const row = this.activeRow
    if (!row || !this.hasThreadTarget) return

    const field = (suffix) => row.querySelector(`[name$='[${suffix}]']`)?.value.trim() || ""
    const label = field("button_text")
    const key = field("button_key")
    const action = row.querySelector("[data-whatsapp-response-flow-target='action']")?.value || "record_only"

    this.rowTargets.forEach((item) => item.classList.toggle("is-active", item === row))
    this.previewTarget.classList.add("has-active-button")
    this.previewTarget.querySelectorAll("[data-button-key]").forEach((button) => {
      button.classList.toggle("is-active", button.dataset.buttonKey === key)
    })
    this.simTitleTarget.textContent = label

    const thread = [this.bubble("out", label)]
    const hoursEnabled = ["send_message", "distribute_lead", "send_to_user"].includes(action) && row.querySelector("input[type='checkbox'][name$='[business_hours][enabled]']")?.checked
    let reply = null
    const selectedTexts = (selector) => [...(row.querySelector(selector)?.selectedOptions || [])]
      .filter((option) => option.value).map((option) => option.text)

    // Espelha ResponseFlowRunner#send_auto_reply: sem horário vale a "Mensagem automática"; com horário, a "dentro do horário".
    const inside = field("inside_hours_message") || this.defaultReplyValue
    if (action === "send_message") reply = hoursEnabled ? inside : (field("message") || inside)
    if (action === "send_url") reply = [field("message"), field("url") || "(informe o link)"].filter(Boolean).join("\n")
    if (["distribute_lead", "send_to_user"].includes(action)) reply = inside
    if (action === "create_task") {
      const due = selectedTexts("[name$='[task_due_minutes]']")[0]
      reply = field("message") || null
      thread.push(this.note(`Tarefa “${field("task_title") || `Acompanhar resposta WhatsApp: ${label}`}” para o corretor do lead${due ? `, ${due}` : ""}`))
      thread.push(this.note("O corretor recebe o aviso em tempo real"))
    }
    if (action === "distribute_lead") {
      const rule = selectedTexts("[data-response-role='distribution-rule']")[0] || "(selecione a fila)"
      const agents = selectedTexts("[data-response-role='target-admin']")
      thread.push(this.note(`Lead enviado para: ${rule} · ${agents.length ? agents.join(", ") : "todos os atendentes da regra"}`))
    }
    if (action === "send_to_user") {
      thread.push(this.note(`Lead enviado para: ${selectedTexts("[name$='[target_user_id]']")[0] || "(selecione o usuário)"}`))
    }
    if (action === "run_automation") {
      thread.push(this.note(`Inicia a automação: ${selectedTexts("[name$='[automation_workflow_id]']")[0] || "(selecione)"}`))
    }
    if (["distribute_lead", "send_to_user"].includes(action)) {
      thread.push(this.note("Atendimento em curso até o atendente finalizar"))
    }
    if (action === "record_only") thread.push(this.note("Clique registrado, sem resposta automática."))

    if (reply && hoursEnabled && action !== "send_url") {
      const days = [...row.querySelectorAll("input[name$='[business_hours][days][]']:checked")]
        .map((input) => this.constructor.dayLabels[input.value]).join(", ")
      const time = (name) => row.querySelector(`[name$='[business_hours][${name}]']`)?.value || ""
      const range = `${time("start") || "08:00"}–${time("end") || "18:00"}`
      thread.push(this.bubble("in", reply, `Dentro do horário · ${days || "sem dias"} ${range}`))
      thread.push(this.bubble("in", field("outside_hours_message") || this.defaultOutsideValue, "Fora do horário"))
    } else if (reply) {
      thread.push(this.bubble("in", reply))
    }

    if (["distribute_lead", "send_to_user"].includes(action)) {
      thread.push(this.bubble("in", field("finish_message"), "Ao finalizar o atendimento"))
    }
    this.threadTarget.replaceChildren(...thread)
  }

  bubble(kind, text, meta) {
    const el = document.createElement("div")
    el.className = `whatsapp-response-simulator__msg is-${kind}`
    if (meta) {
      const small = document.createElement("small")
      small.textContent = meta
      el.append(small)
    }
    el.append(text)
    return el
  }

  note(text) {
    const el = document.createElement("div")
    el.className = "whatsapp-response-simulator__note"
    el.textContent = text
    return el
  }

  visibleField(action, type) {
    if (type === "hours") return ["send_message", "distribute_lead", "send_to_user"].includes(action)
    if (type === "message") return ["send_message", "send_url", "create_task"].includes(action)
    if (type === "url") return action === "send_url"
    if (["task", "task-user", "task-due", "task-kind", "task-priority"].includes(type)) return action === "create_task"
    if (type === "distribution") return action === "distribute_lead"
    if (type === "target-admin") return action === "distribute_lead"
    if (type === "accept") return action === "distribute_lead"
    if (type === "automation") return action === "run_automation"
    if (type === "target-user") return action === "send_to_user"
    if (type === "finish") return ["distribute_lead", "send_to_user"].includes(action)
    return false
  }

  // Atualiza as opções do multiselect de atendentes quando a regra muda, mantendo os que continuam válidos.
  refreshAttendantOptions(row) {
    const select = row.querySelector("[data-response-role='target-admin']")
    if (!select) return

    const ruleId = row.querySelector("[data-response-role='distribution-rule']")?.value || ""
    if (select.dataset.ruleId === ruleId) return
    const firstPass = select.dataset.ruleId === undefined
    select.dataset.ruleId = ruleId
    if (firstPass) return // opções renderizadas pelo servidor já correspondem à regra salva

    const agents = (this.ruleAgentsValue[ruleId] || []).map(([name, id]) => ({ value: String(id), text: name }))
    const tomSelect = select.tomselect
    const current = tomSelect ? tomSelect.items : [...select.selectedOptions].map((option) => option.value)
    const selected = current.filter((value) => agents.some((agent) => agent.value === value))

    if (tomSelect) {
      tomSelect.clear(true)
      tomSelect.clearOptions()
      tomSelect.addOptions(agents)
      tomSelect.setValue(selected, true)
    } else {
      select.replaceChildren(...agents.map((agent) => new Option(agent.text, agent.value, false, selected.includes(agent.value))))
    }
  }
}
