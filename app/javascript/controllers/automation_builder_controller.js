import { Controller } from "@hotwired/stimulus"

// Construtor de regras de automação: gerencia as linhas de ação (adicionar/remover),
// mostra apenas os campos do tipo escolhido e serializa tudo em JSON no submit.
export default class extends Controller {
  static targets = ["rows", "template", "json", "trigger", "idleCond"]

  connect() {
    this.syncTrigger()
    this.rowsTarget
      .querySelectorAll("[data-automation-builder-target='row']")
      .forEach((row) => this.refreshRow(row))
    if (this.rowsTarget.children.length === 0) this.addRow()
  }

  addRow(event) {
    if (event) event.preventDefault()
    const node = this.templateTarget.content.firstElementChild.cloneNode(true)
    this.rowsTarget.appendChild(node)
    this.refreshRow(node)
  }

  removeRow(event) {
    event.preventDefault()
    const row = event.target.closest("[data-automation-builder-target='row']")
    if (row) row.remove()
  }

  changeType(event) {
    const row = event.target.closest("[data-automation-builder-target='row']")
    if (row) this.refreshRow(row)
  }

  refreshRow(row) {
    const type = row.querySelector(".ab-type").value
    row.querySelectorAll("[data-ab-wrap]").forEach((wrap) => {
      const types = wrap.dataset.abFor.split(",")
      wrap.style.display = types.includes(type) ? "" : "none"
    })
  }

  syncTrigger() {
    if (!this.hasTriggerTarget || !this.hasIdleCondTarget) return
    this.idleCondTarget.style.display = this.triggerTarget.value === "lead_idle" ? "" : "none"
  }

  serialize() {
    const actions = []
    this.rowsTarget.querySelectorAll("[data-automation-builder-target='row']").forEach((row) => {
      const type = row.querySelector(".ab-type").value
      const obj = { type }
      row.querySelectorAll("[data-ab-field]").forEach((field) => {
        const types = field.dataset.abFor.split(",")
        if (types.includes(type) && field.value !== "") obj[field.dataset.abField] = field.value
      })
      actions.push(obj)
    })
    this.jsonTarget.value = JSON.stringify(actions)
  }
}
