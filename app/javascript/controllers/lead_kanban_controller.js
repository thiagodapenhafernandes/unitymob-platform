import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["column"]

  connect() {
    this.sortables = this.columnTargets.map((column) => {
      return new Sortable(column, {
        group: "lead-kanban",
        animation: 150,
        draggable: ".lead-kanban-card",
        ghostClass: "lead-kanban-card--ghost",
        chosenClass: "lead-kanban-card--chosen",
        onEnd: (event) => this.persistMove(event)
      })
    })
  }

  disconnect() {
    this.sortables?.forEach((sortable) => sortable.destroy())
  }

  changeStatus(event) {
    const card = event.target.closest(".lead-kanban-card")
    const status = event.target.value
    if (!card || !status) return

    this.updateLead(card, status)
  }

  persistMove(event) {
    const card = event.item
    const column = event.to
    const status = column.dataset.leadKanbanStatus

    if (!card || !status || card.dataset.currentStatus === status) return
    this.updateLead(card, status)
  }

  updateLead(card, status) {
    const previousStatus = card.dataset.currentStatus
    const select = card.querySelector("[data-lead-kanban-status-select]")

    card.classList.add("lead-kanban-card--saving")

    fetch(card.dataset.updateUrl, {
      method: "PATCH",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({ lead: { status } })
    })
      .then((response) => {
        if (!response.ok) throw new Error("status_update_failed")
        return response.json()
      })
      .then((data) => {
        card.dataset.currentStatus = data.status
        if (select) select.value = data.status
        this.updateCardBadge(card, data.status, data.badge_class)
        this.updateCounters(previousStatus, data.status)
      })
      .catch(() => {
        if (select) select.value = previousStatus
        this.returnToPreviousColumn(card, previousStatus)
        window.alert("Não foi possível atualizar o status do lead.")
      })
      .finally(() => {
        card.classList.remove("lead-kanban-card--saving")
      })
  }

  updateCardBadge(card, status, badgeClass) {
    const badge = card.querySelector("[data-lead-kanban-status-badge]")
    if (!badge) return

    badge.className = `badge bg-${badgeClass || "dark"}`
    badge.textContent = status
  }

  updateCounters(previousStatus, nextStatus) {
    if (!previousStatus || previousStatus === nextStatus) return

    this.adjustCounter(previousStatus, -1)
    this.adjustCounter(nextStatus, 1)
  }

  adjustCounter(status, delta) {
    const counter = Array.from(this.element.querySelectorAll("[data-lead-kanban-count]")).find((element) => {
      return element.dataset.leadKanbanCount === status
    })
    if (!counter) return

    const current = Number.parseInt(counter.textContent, 10) || 0
    counter.textContent = Math.max(current + delta, 0)
  }

  returnToPreviousColumn(card, previousStatus) {
    const column = this.columnTargets.find((target) => target.dataset.leadKanbanStatus === previousStatus)
    if (column) column.prepend(card)
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
