import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["columns"]

  connect() {
    this.restoreLeadFromHash() || this.syncActiveFromScroll()
  }

  focusColumn(event) {
    event.preventDefault()

    const trigger = event.currentTarget
    const columnId = trigger.dataset.leadPwaKanbanColumnId
    const column = columnId ? document.getElementById(columnId) : null
    if (!column || !this.hasColumnsTarget) return

    this.centerColumn(column, "smooth")
    this.activateTab(trigger)
    this.activateColumn(column)
  }

  syncActiveFromScroll() {
    if (!this.hasColumnsTarget) return

    window.cancelAnimationFrame(this.scrollFrame)
    this.scrollFrame = window.requestAnimationFrame(() => {
      const activeColumn = this.closestColumnToCenter()
      if (!activeColumn) return

      const activeTrigger = this.element.querySelector(
        `[data-lead-pwa-kanban-column-id="${CSS.escape(activeColumn.id)}"]`
      )
      this.activateTab(activeTrigger)
      this.activateColumn(activeColumn)
      this.centerTab(activeTrigger)
    })
  }

  centerColumn(column, behavior = "auto") {
    const columnBox = column.getBoundingClientRect()
    const columnsBox = this.columnsTarget.getBoundingClientRect()
    const columnCenter = columnBox.left + columnBox.width / 2
    const columnsCenter = columnsBox.left + columnsBox.width / 2
    const targetLeft = this.columnsTarget.scrollLeft + columnCenter - columnsCenter

    this.columnsTarget.scrollTo({ left: Math.max(targetLeft, 0), behavior })
  }

  closestColumnToCenter() {
    const columns = Array.from(this.columnsTarget.querySelectorAll(".lead-pwa-kanban-column"))
    if (columns.length === 0) return null

    const columnsBox = this.columnsTarget.getBoundingClientRect()
    const center = columnsBox.left + columnsBox.width / 2

    return columns.reduce((closest, column) => {
      const box = column.getBoundingClientRect()
      const distance = Math.abs(box.left + box.width / 2 - center)
      return distance < closest.distance ? { column, distance } : closest
    }, { column: columns[0], distance: Number.POSITIVE_INFINITY }).column
  }

  activateTab(activeTrigger) {
    if (!activeTrigger) return

    this.element.querySelectorAll("[data-lead-pwa-kanban-column-id]").forEach((trigger) => {
      trigger.classList.toggle("is-active", trigger === activeTrigger)
    })
  }

  centerTab(activeTrigger) {
    if (!activeTrigger) return

    activeTrigger.scrollIntoView({ behavior: "smooth", inline: "center", block: "nearest" })
  }

  activateColumn(activeColumn) {
    this.columnsTarget.querySelectorAll(".lead-pwa-kanban-column").forEach((column) => {
      column.classList.toggle("is-active", column === activeColumn)
    })
  }

  restoreLeadFromHash() {
    const leadId = window.location.hash?.slice(1)
    if (!leadId || !this.hasColumnsTarget) return false

    const leadCard = document.getElementById(leadId)
    const column = leadCard?.closest(".lead-pwa-kanban-column")
    if (!leadCard || !column) return false

    const activeTrigger = this.element.querySelector(
      `[data-lead-pwa-kanban-column-id="${CSS.escape(column.id)}"]`
    )

    this.centerColumn(column)
    this.activateTab(activeTrigger)
    this.activateColumn(column)
    this.centerTab(activeTrigger)

    window.requestAnimationFrame(() => {
      leadCard.scrollIntoView({ behavior: "auto", block: "center", inline: "nearest" })
      leadCard.classList.add("lead-pwa-card--restored")
      window.setTimeout(() => leadCard.classList.remove("lead-pwa-card--restored"), 1800)
    })

    return true
  }
}
