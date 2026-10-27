import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Configuração das colunas do funil de leads (modal da engrenagem):
// reordenar (drag), renomear, subtítulo, adicionar e remover. Persiste em lote
// via Admin::LeadStatusesController#bulk_update e recarrega a página.
export default class extends Controller {
  static targets = ["list", "template", "error", "submit", "navigation", "navigationTemplate", "pipelineName", "pipelineTitle", "stageCount", "headerCount"]
  static values = { url: String, pipelineId: Number }

  connect() {
    this.fieldSequence = 0
    this.navigationItems = new Map()
    this.refreshNavigation()
    this.sortable = new Sortable(this.navigationTarget, {
      animation: 150,
      handle: ".lead-status-row__handle",
      draggable: ".lead-status-board__nav-row",
      onEnd: () => this.reorderStages()
    })
    this.listTarget.querySelectorAll(".lead-status-row__automation-rule").forEach((rule) => this.refreshAutomationAction(rule))
    this.openRow(this.rows()[0])
  }

  rows() {
    return Array.from(this.listTarget.querySelectorAll(".lead-status-row"))
  }

  refreshNavigation() {
    const rows = this.rows()
    for (const [row, item] of this.navigationItems) {
      if (!rows.includes(row)) {
        item.remove()
        this.navigationItems.delete(row)
      }
    }
    rows.forEach((row, index) => {
      if (!this.navigationItems.has(row)) {
        row.id = `lead-stage-editor-${row.dataset.id ? `saved-${row.dataset.id}` : `new-${++this.fieldSequence}`}`
        const item = this.navigationTemplateTarget.content.firstElementChild.cloneNode(true)
        item.dataset.rowId = row.id
        item.querySelector("button[data-action]").setAttribute("aria-controls", row.id)
        this.navigationItems.set(row, item)
      }
      this.navigationTarget.append(this.navigationItems.get(row))
      row.querySelector("[data-lead-status-position]").textContent = `Etapa ${String(index + 1).padStart(2, "0")}`
      row.querySelector('[data-direction="-1"]').disabled = index === 0
      row.querySelector('[data-direction="1"]').disabled = index === rows.length - 1
      this.refreshStage(row, index)
    })
    this.stageCountTarget.textContent = rows.length
    this.headerCountTarget.querySelector(".ax-badge").textContent = `${rows.length} etapas`
    this.updatePipelineName()
  }

  selectStage(event) {
    const item = event.currentTarget.closest("[data-row-id]")
    this.openRow(this.rows().find((row) => row.id === item.dataset.rowId))
  }

  reorderStages() {
    Array.from(this.navigationTarget.children).forEach((item) => {
      const row = this.rows().find((candidate) => candidate.id === item.dataset.rowId)
      if (row) this.listTarget.append(row)
    })
    this.refreshNavigation()
  }

  moveStage(event) {
    const row = event.currentTarget.closest(".lead-status-row")
    const rows = this.rows()
    const direction = Number(event.currentTarget.dataset.direction)
    const neighbor = rows[rows.indexOf(row) + direction]
    if (!neighbor) return
    this.listTarget.insertBefore(row, direction < 0 ? neighbor : neighbor.nextSibling)
    this.refreshNavigation()
  }

  updatePipelineName() {
    const name = this.pipelineNameTarget.value.trim() || "Sem nome"
    this.pipelineTitleTargets.forEach((label) => { label.textContent = name })
    this.refreshStageOptions()
  }

  updateStage(event) {
    const row = event.target.closest(".lead-status-row")
    if (!row) return
    this.refreshStage(row, this.rows().indexOf(row))
    if (event.target.dataset.leadStatusField === "name") this.refreshStageOptions()
  }

  refreshStage(row, index) {
    const name = row.querySelector('[data-lead-status-field="name"]').value.trim() || "Nova etapa"
    const typeField = row.querySelector('[data-lead-status-field="stage_type"]')
    const type = typeField.selectedOptions[0]?.textContent || "Aberta"
    const active = row.querySelector('[data-lead-status-field="active"]').checked
    const removing = row.dataset.destroy === "true"
    const item = this.navigationItems.get(row)
    item.querySelector("[data-ax-studio-nav-label]").textContent = name
    item.querySelector("[data-ax-studio-nav-hint]").textContent = `${String(index + 1).padStart(2, "0")} · ${removing ? "Remoção pendente" : `${type}${active ? "" : " · Inativa"}`}`
    item.querySelector(".ax-studio-nav__icon").style.color = row.querySelector('[data-lead-status-field="color"]').value
    row.querySelector("[data-lead-status-summary-name]").textContent = name
    row.querySelector("[data-lead-status-type-badge] .ax-badge").textContent = type
    row.querySelector("[data-lead-status-remove-label]").textContent = removing ? "Cancelar remoção" : "Remover etapa"
    row.querySelector("[data-lead-status-qualification-options]").hidden = !row.querySelector('[data-lead-status-policy-field="qualification_enabled"]').checked
    const roles = Array.from(row.querySelectorAll('[data-lead-status-policy-array-field="visible_to_roles"]:checked'))
      .map((field) => field.closest("label").querySelector(".ax-toggle-chip__label").textContent.trim())
    const nextCount = this.selectedValues(row, '[data-lead-status-transition-field="next_stage_id"]').length
    row.querySelector("[data-lead-status-summary-details]").textContent = [roles.length ? `Visível para ${roles.join(", ")}` : "Nenhum perfil selecionado", nextCount ? `${nextCount} próxima(s) etapa(s)` : "Fluxo sem restrição"].join(" · ")
    const rules = Array.from(row.querySelectorAll('.lead-status-row__automation-rule')).filter((rule) => rule.dataset.destroy !== "true")
    const activeCount = rules.filter((rule) => rule.querySelector('[data-lead-status-automation-field="active"]').checked).length
    row.querySelector("[data-lead-status-automation-summary]").textContent = rules.length ? `${activeCount} ativa(s) · ${rules.length} regra(s)` : "Nenhuma automação configurada"
    row.querySelector("[data-lead-status-automation-empty]").hidden = rules.length > 0
  }

  refreshStageOptions() {
    const stages = this.rows().filter((row) => row.dataset.id)
    const containers = [this.element, this.templateTarget.content,
      ...this.listTarget.querySelectorAll(".lead-status-row__automation-template"),
      ...this.templateTarget.content.querySelectorAll(".lead-status-row__automation-template")].map((container) => container.content || container)
    containers.forEach((container) => {
      container.querySelectorAll("select[data-lead-status-stage-options]").forEach((select) => {
        stages.forEach((row) => {
          const option = Array.from(select.options).find((candidate) => candidate.value === row.dataset.id)
          if (!option) return
          const name = row.querySelector('[data-lead-status-field="name"]').value.trim() || "Nova etapa"
          const text = select.dataset.leadStatusStageOptions === "qualified" ? `${this.pipelineNameTarget.value.trim() || "Sem nome"} · ${name}` : name
          option.textContent = text
          const tomOption = select.tomselect?.options[option.value]
          if (tomOption && tomOption.text !== text) select.tomselect.updateOption(option.value, { ...tomOption, text })
        })
      })
    })
  }

  uniquifyFields(container) {
    container.querySelectorAll("[id]").forEach((field) => {
      const oldId = field.id
      field.id = `lead-stage-field-${++this.fieldSequence}`
      container.querySelectorAll("label[for]").forEach((label) => {
        if (label.htmlFor === oldId) label.htmlFor = field.id
      })
    })
  }

  disconnect() {
    this.sortable?.destroy()
  }

  addRow(event) {
    event.preventDefault()
    const fragment = this.templateTarget.content.cloneNode(true)
    this.listTarget.appendChild(fragment)
    const row = this.listTarget.lastElementChild
    this.uniquifyFields(row)
    this.refreshNavigation()
    this.openRow(row)
    row?.querySelector('[data-lead-status-field="name"]')?.focus()
  }

  removeRow(event) {
    event.preventDefault()
    const row = event.target.closest(".lead-status-row")
    if (!row) return

    if (row.dataset.id) {
      const destroying = row.dataset.destroy === "true"
      row.dataset.destroy = destroying ? "false" : "true"
      row.classList.toggle("is-destroying", !destroying)
      row.querySelector("[data-lead-status-destroy-panel]")?.toggleAttribute("hidden", destroying)
      row.querySelector("[data-lead-status-destroy-field='replacement_stage_id']")?.toggleAttribute("disabled", destroying)
      if (destroying) {
        const replacementField = row.querySelector("[data-lead-status-destroy-field='replacement_stage_id']")
        if (replacementField) replacementField.value = ""
      } else {
        this.openRow(row)
        row.querySelector("[data-lead-status-destroy-field='replacement_stage_id']")?.focus()
      }
    } else {
      const next = row.nextElementSibling || row.previousElementSibling
      row.remove()
      this.openRow(next)
    }
    this.refreshNavigation()
  }

  addAutomation(event) {
    event.preventDefault()
    const row = event.target.closest(".lead-status-row")
    const template = row?.querySelector(".lead-status-row__automation-template")
    const list = row?.querySelector(".lead-status-row__automation-list")
    if (!template || !list) return

    list.appendChild(template.content.cloneNode(true))
    const rule = list.lastElementChild
    this.uniquifyFields(rule)
    this.refreshAutomationAction(rule)
    this.refreshStageOptions()
    this.refreshStage(row, this.rows().indexOf(row))
    rule?.querySelector('[data-lead-status-automation-field="trigger"]')?.focus()
  }

  removeAutomation(event) {
    event.preventDefault()
    const rule = event.target.closest(".lead-status-row__automation-rule")
    if (!rule) return

    const row = rule.closest(".lead-status-row")
    if (rule.dataset.automationId) {
      rule.dataset.destroy = "true"
      rule.hidden = true
    } else {
      rule.remove()
    }
    this.refreshStage(row, this.rows().indexOf(row))
  }

  changeAutomationAction(event) {
    this.refreshAutomationAction(event.currentTarget.closest(".lead-status-row__automation-rule"))
  }

  openRow(row) {
    this.rows().forEach((candidate) => {
      const selected = candidate === row
      candidate.hidden = !selected
      const button = this.navigationItems.get(candidate)?.querySelector("button[data-action]")
      button?.classList.toggle("active", selected)
      button?.setAttribute("aria-pressed", String(selected))
    })
  }

  refreshAutomationAction(rule) {
    if (!rule) return

    const actionType = rule.querySelector('[data-lead-status-automation-field="action_type"]')?.value || "move_stage"
    rule.querySelectorAll("[data-action-config-panel]").forEach((panel) => {
      const panelType = panel.dataset.actionConfigPanel
      panel.hidden = panelType !== actionType
    })
  }

  save(event) {
    event.preventDefault()
    this.hideError()

    const statuses = Array.from(this.listTarget.querySelectorAll(".lead-status-row"))
      .map((row) => ({
        id: row.dataset.id || null,
        name: row.querySelector('[data-lead-status-field="name"]')?.value.trim() || "",
        description: row.querySelector('[data-lead-status-field="description"]')?.value.trim() || "",
        stage_type: row.querySelector('[data-lead-status-field="stage_type"]')?.value || "open",
        google_event_trigger: row.querySelector('[data-lead-status-field="google_event_trigger"]')?.value || "stage_entered",
        meta_event_trigger: row.querySelector('[data-lead-status-field="meta_event_trigger"]')?.value || "stage_entered",
        google_event: row.querySelector('[data-lead-status-field="google_event"]')?.value || "none",
        meta_conversion_event: row.querySelector('[data-lead-status-field="meta_conversion_event"]')?.value || "",
        color: row.querySelector('[data-lead-status-field="color"]')?.value || "",
        active: row.querySelector('[data-lead-status-field="active"]')?.checked ?? true,
        policy: this.policyFor(row),
        next_stage_ids: this.selectedValues(row, '[data-lead-status-transition-field="next_stage_id"]'),
        automations: this.automationsFor(row),
        replacement_stage_id: row.querySelector('[data-lead-status-destroy-field="replacement_stage_id"]')?.value || "",
        _destroy: row.dataset.destroy === "true"
      }))
      .filter((status) => status.id || status.name || status._destroy)

    const active = statuses.filter((status) => !status._destroy)
    if (active.length === 0) {
      this.showError("Mantenha pelo menos um status no funil.")
      return
    }
    if (active.some((status) => !status.name)) {
      this.showError("Todos os status precisam de um nome.")
      return
    }
    if (statuses.some((status) => status._destroy && status.id && !status.replacement_stage_id)) {
      this.showError("Escolha para qual etapa enviar os leads das etapas removidas.")
      return
    }
    const activeAutomations = active.flatMap((status) => status.automations.filter((automation) => !automation._destroy && automation.active))
    if (activeAutomations.some((automation) => {
      const amount = Number.parseInt(automation.after_amount, 10)
      return !Number.isFinite(amount) || amount <= 0
    })) {
      this.showError("Toda automação ativa precisa de um tempo maior que zero.")
      return
    }
    if (activeAutomations.some((automation) => automation.action_type === "move_stage" && !automation.auto_advance_to_stage_id)) {
      this.showError("Toda automação ativa de mover precisa de uma etapa de destino.")
      return
    }

    this.setLoading(true)

    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({ lead_pipeline_id: this.pipelineIdValue, statuses })
    })
      .then((response) => response.json().then((data) => ({ ok: response.ok, data })))
      .then(({ ok, data }) => {
        if (!ok || !data.ok) throw new Error(data.error || "Não foi possível salvar as colunas.")
        // Mantém o loading: a página recarrega e o toast (flash) aparece.
        window.location.reload()
      })
      .catch((error) => {
        console.error("[lead-status-board] save: erro", error)
        this.setLoading(false)
        this.showError(error.message)
      })
  }

  setLoading(loading) {
    if (loading) {
      this.submitOriginalHtml = this.submitTarget.innerHTML
      this.submitTarget.disabled = true
      this.submitTarget.innerHTML = '<span class="ax-spinner"></span> Salvando...'
    } else {
      this.submitTarget.disabled = false
      if (this.submitOriginalHtml != null) this.submitTarget.innerHTML = this.submitOriginalHtml
    }
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  hideError() {
    this.errorTarget.hidden = true
    this.errorTarget.textContent = ""
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }

  automationsFor(row) {
    return Array.from(row.querySelectorAll(".lead-status-row__automation-rule"))
      .map((rule) => ({
        id: rule.dataset.automationId || null,
        trigger: rule.querySelector('[data-lead-status-automation-field="trigger"]')?.value || "stage_duration",
        after_amount: rule.querySelector('[data-lead-status-automation-field="after_amount"]')?.value || "",
        after_unit: rule.querySelector('[data-lead-status-automation-field="after_unit"]')?.value || "days",
        auto_advance_to_stage_id: rule.querySelector('[data-lead-status-automation-field="auto_advance_to_stage_id"]')?.value || "",
        action_type: rule.querySelector('[data-lead-status-automation-field="action_type"]')?.value || "move_stage",
        action_config: this.automationConfigFor(rule),
        active: rule.querySelector('[data-lead-status-automation-field="active"]')?.checked || false,
        _destroy: rule.dataset.destroy === "true"
      }))
      .filter((automation) => automation.id || automation.active || automation.after_amount || automation.auto_advance_to_stage_id || automation.action_type !== "move_stage" || automation._destroy)
  }

  policyFor(row) {
    return {
      visible_to_roles: this.selectedValues(row, '[data-lead-status-policy-array-field="visible_to_roles"]'),
      allowed_archive_reason_ids: this.selectedValues(row, '[data-lead-status-policy-array-field="allowed_archive_reason_ids"]'),
      qualification_options: this.selectedValues(row, '[data-lead-status-policy-array-field="qualification_options"]'),
      future_activity_limit_days: row.querySelector('[data-lead-status-policy-field="future_activity_limit_days"]')?.value || "",
      qualification_enabled: row.querySelector('[data-lead-status-policy-field="qualification_enabled"]')?.checked || false,
      divergence_queue_enabled: row.querySelector('[data-lead-status-policy-field="divergence_queue_enabled"]')?.checked || false
    }
  }

  automationConfigFor(rule) {
    const config = {}
    rule.querySelectorAll("[data-lead-status-automation-config-field]").forEach((field) => {
      if (field.closest("[data-action-config-panel]")?.hidden) return
      config[field.dataset.leadStatusAutomationConfigField] = field.value
    })
    return config
  }

  selectedValues(row, selector) {
    return Array.from(row.querySelectorAll(selector)).flatMap((field) => {
      if (field instanceof HTMLSelectElement) {
        return Array.from(field.selectedOptions).map((option) => option.value)
      }

      return field.checked ? [field.value] : []
    })
  }
}
