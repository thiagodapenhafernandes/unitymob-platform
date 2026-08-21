import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Configuração das colunas do funil de leads (modal da engrenagem):
// reordenar (drag), renomear, subtítulo, adicionar e remover. Persiste em lote
// via Admin::LeadStatusesController#bulk_update e recarrega a página.
export default class extends Controller {
  static targets = ["list", "template", "error", "submit"]
  static values = { url: String, pipelineId: Number }

  connect() {
    this.sortable = new Sortable(this.listTarget, {
      animation: 150,
      handle: ".lead-status-row__handle",
      draggable: ".lead-status-row"
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
    row?.querySelector('[data-lead-status-field="name"]')?.focus()
    this.openRow(row)
  }

  removeRow(event) {
    event.preventDefault()
    const row = event.target.closest(".lead-status-row")
    if (!row) return

    if (row.dataset.id) {
      row.dataset.destroy = "true"
      row.hidden = true
    } else {
      row.remove()
    }
  }

  addAutomation(event) {
    event.preventDefault()
    const row = event.target.closest(".lead-status-row")
    const template = row?.querySelector(".lead-status-row__automation-template")
    const list = row?.querySelector(".lead-status-row__automation-list")
    if (!template || !list) return

    list.appendChild(template.content.cloneNode(true))
    const rule = list.lastElementChild
    this.refreshAutomationAction(rule)
    rule?.querySelector('[data-lead-status-automation-field="trigger"]')?.focus()
  }

  removeAutomation(event) {
    event.preventDefault()
    const rule = event.target.closest(".lead-status-row__automation-rule")
    if (!rule) return

    if (rule.dataset.automationId) {
      rule.dataset.destroy = "true"
      rule.hidden = true
    } else {
      rule.remove()
    }
  }

  toggleDetails(event) {
    event.preventDefault()
    const row = event.currentTarget.closest(".lead-status-row")
    if (!row) return

    const details = row.querySelector(".lead-status-row__details")
    if (details?.hidden) {
      this.openRow(row)
    } else {
      this.closeRow(row)
    }
  }

  changeAutomationAction(event) {
    this.refreshAutomationAction(event.currentTarget.closest(".lead-status-row__automation-rule"))
  }

  openRow(row) {
    Array.from(this.listTarget.querySelectorAll(".lead-status-row")).forEach((candidate) => {
      if (candidate === row) return
      this.closeRow(candidate)
    })
    row?.classList.add("is-open")
    const details = row?.querySelector(".lead-status-row__details")
    const trigger = row?.querySelector(".lead-status-row__summary")
    if (details) details.hidden = false
    trigger?.setAttribute("aria-expanded", "true")
  }

  closeRow(row) {
    row?.classList.remove("is-open")
    const details = row?.querySelector(".lead-status-row__details")
    const trigger = row?.querySelector(".lead-status-row__summary")
    if (details) details.hidden = true
    trigger?.setAttribute("aria-expanded", "false")
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
        color: row.querySelector('[data-lead-status-field="color"]')?.value || "",
        active: row.querySelector('[data-lead-status-field="active"]')?.checked ?? true,
        policy: this.policyFor(row),
        next_stage_ids: this.selectedValues(row, '[data-lead-status-transition-field="next_stage_id"]'),
        automations: this.automationsFor(row),
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
