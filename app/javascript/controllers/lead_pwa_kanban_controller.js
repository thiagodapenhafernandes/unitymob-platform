import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = [
    "columns",
    "card",
    "sheet",
    "sheetName",
    "sheetMeta",
    "sheetOpenLink",
    "sheetWhatsappForm",
    "sheetStatusForm",
    "sheetStatusSelect",
    "sheetTaskLeadId",
    "sheetScheduleForm",
    "sheetNoteForm"
  ]

  connect() {
    this.pressTimer = null
    this.tapTimer = null
    this.lastTapAt = 0
    this.lastTapCardId = null
    this.drag = null
    this.boundGlobalDragMove = this.handleGlobalDragMove.bind(this)
    this.boundGlobalDragEnd = this.handleGlobalDragEnd.bind(this)
    this.boundGlobalDragCancel = this.handleGlobalDragCancel.bind(this)
    this.restoreLeadFromHash() || this.syncActiveFromScroll()
  }

  disconnect() {
    this.clearPressTimer()
    window.clearTimeout(this.tapTimer)
    this.removeGlobalDragListeners()
    this.removeGhost()
  }

  focusColumn(event) {
    event.preventDefault()

    const trigger = event.currentTarget
    const column = this.columnById(trigger.dataset.leadPwaKanbanColumnId)
    if (!column || !this.hasColumnsTarget) return

    this.centerColumn(column, "smooth")
    this.activateTab(trigger)
    this.activateColumn(column)
  }

  prepareCardGesture(event) {
    const card = event.currentTarget
    if (this.isInteractiveElement(event.target)) return

    event.preventDefault()
    this.clearPressTimer()
    this.drag = {
      card,
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      lastX: event.clientX,
      lastY: event.clientY,
      sourceColumn: card.closest(".lead-pwa-kanban-column"),
      activeColumn: null,
      dragging: false
    }

    this.pressTimer = window.setTimeout(() => {
      if (!this.drag || this.drag.card !== card) return
      this.startCardDrag(event)
    }, 260)

    card.classList.add("is-pressing")
  }

  moveCardGesture(event) {
    if (!this.drag || this.drag.pointerId !== event.pointerId) return

    this.drag.lastX = event.clientX
    this.drag.lastY = event.clientY
    const moved = Math.hypot(event.clientX - this.drag.startX, event.clientY - this.drag.startY)
    if (!this.drag.dragging && moved > 32) this.clearPressTimer()
    if (!this.drag.dragging) return

    event.preventDefault()
    this.moveGhost(event.clientX, event.clientY)
    this.updateDropTarget(event.clientX, event.clientY)
    this.autoScrollColumns(event.clientX)
  }

  finishCardGesture(event) {
    if (!this.drag || this.drag.pointerId !== event.pointerId) return

    const drag = this.drag
    this.clearPressTimer()
    drag.card.classList.remove("is-pressing", "is-drag-ready")

    if (drag.dragging) {
      event.preventDefault()
      this.dropCard(drag)
      return
    }

    this.drag = null
    this.handleCardTap(drag.card)
  }

  cancelCardGesture() {
    if (!this.drag) return
    if (this.drag.dragging) return

    this.drag.card.classList.remove("is-pressing", "is-drag-ready", "is-dragging")
    this.clearActiveDropTarget()
    this.removeGhost()
    this.drag = null
    this.clearPressTimer()
  }

  blockNativeMenu(event) {
    if (event.target.closest(".lead-pwa-card")) event.preventDefault()
  }

  openSelectedCard(event) {
    event.preventDefault()
    this.storeReturnCard(event.currentTarget)
    Turbo.visit(event.currentTarget.dataset.leadUrl)
  }

  openQuickSheet(event) {
    event.preventDefault()
    const card = event.currentTarget.closest(".lead-pwa-card") || event.currentTarget
    if (!card || !this.hasSheetTarget) return

    this.showSheet(card)
  }

  closeSheet(event) {
    event?.preventDefault()
    if (this.hasSheetTarget) this.sheetTarget.hidden = true
    document.documentElement.classList.remove("lead-pwa-sheet-open")
  }

  closeSheetFromBackdrop(event) {
    if (event.target === this.sheetTarget) this.closeSheet(event)
  }

  async openConversation(event) {
    event.preventDefault()

    const form = event.currentTarget
    const submit = event.submitter || form.querySelector("button[type='submit']")
    submit?.setAttribute("disabled", "disabled")

    try {
      const response = await fetch(form.action, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Accept": "text/html",
          "X-CSRF-Token": this.csrfToken()
        }
      })

      Turbo.visit(response.url || form.action)
    } catch (_error) {
      form.submit()
    } finally {
      submit?.removeAttribute("disabled")
    }
  }

  syncActiveFromScroll() {
    if (!this.hasColumnsTarget) return

    window.cancelAnimationFrame(this.scrollFrame)
    this.scrollFrame = window.requestAnimationFrame(() => {
      const activeColumn = this.closestColumnToCenter()
      if (!activeColumn) return

      const activeTrigger = this.triggerForColumn(activeColumn)
      this.activateTab(activeTrigger)
      this.activateColumn(activeColumn)
      this.centerTab(activeTrigger)
    })
  }

  startCardDrag(event) {
    if (!this.drag) return

    const { card } = this.drag
    this.drag.dragging = true
    card.classList.remove("is-pressing")
    card.classList.add("is-drag-ready", "is-dragging")
    this.addGlobalDragListeners()
    try {
      card.setPointerCapture?.(event.pointerId)
    } catch (_error) {
      // Safari can cancel pointer capture during a long press.
    }
    this.createGhost(card, this.drag.lastX, this.drag.lastY)
    this.updateDropTarget(this.drag.lastX, this.drag.lastY)
  }

  handleGlobalDragMove(event) {
    if (!this.drag?.dragging) return

    const point = this.eventPoint(event)
    if (!point) return

    event.preventDefault()
    this.drag.lastX = point.x
    this.drag.lastY = point.y
    this.moveGhost(point.x, point.y)
    this.updateDropTarget(point.x, point.y)
    this.autoScrollColumns(point.x)
  }

  handleGlobalDragEnd(event) {
    if (!this.drag) return
    if (!this.drag.dragging) {
      this.removeGlobalDragListeners()
      return
    }

    event.preventDefault()
    this.dropCard(this.drag)
  }

  handleGlobalDragCancel(event) {
    if (!this.drag) return
    event.preventDefault()
    if (event.type === "pointercancel" && this.drag.dragging) return

    this.abortDrag()
  }

  async dropCard(drag) {
    const card = drag.card
    const targetColumn = drag.activeColumn || drag.sourceColumn
    const nextStatus = targetColumn?.dataset.leadStatus
    const previousStatus = card.dataset.leadStatus

    card.classList.remove("is-dragging", "is-drag-ready", "is-pressing")
    this.clearActiveDropTarget()
    this.removeGhost()
    this.removeGlobalDragListeners()
    this.drag = null

    if (!targetColumn || !nextStatus || nextStatus === previousStatus) {
      this.centerColumn(drag.sourceColumn, "smooth")
      return
    }

    this.moveCardToColumn(card, targetColumn)
    card.dataset.leadStatus = nextStatus
    this.centerColumn(targetColumn, "smooth")
    this.activateColumn(targetColumn)
    this.activateTab(this.triggerForColumn(targetColumn))
    this.centerTab(this.triggerForColumn(targetColumn))
    this.updateColumnCounts(previousStatus, nextStatus)

    try {
      const response = await fetch(card.dataset.updateUrl, {
        method: "PATCH",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        body: JSON.stringify({ lead: { status: nextStatus } })
      })
      const data = await this.parseResponse(response)
      if (!response.ok) throw new Error(data.error || data.message || "Não foi possível mudar o lead de etapa.")
      if (data.status && data.status !== nextStatus) card.dataset.leadStatus = data.status
    } catch (error) {
      this.moveCardToColumn(card, drag.sourceColumn)
      card.dataset.leadStatus = previousStatus
      this.updateColumnCounts(nextStatus, previousStatus)
      this.centerColumn(drag.sourceColumn, "smooth")
      this.notify(error.message || "Não foi possível mudar o lead de etapa.", "danger")
    }
  }

  abortDrag() {
    if (!this.drag) return

    this.drag.card.classList.remove("is-pressing", "is-drag-ready", "is-dragging")
    this.clearActiveDropTarget()
    this.removeGhost()
    this.removeGlobalDragListeners()
    this.drag = null
    this.clearPressTimer()
  }

  handleCardTap(card) {
    const now = Date.now()
    const sameCard = this.lastTapCardId === card.id
    const doubleTap = sameCard && now - this.lastTapAt < 380
    this.lastTapAt = now
    this.lastTapCardId = card.id

    window.clearTimeout(this.tapTimer)
    if (doubleTap) {
      this.showSheet(card)
      return
    }

    this.tapTimer = window.setTimeout(() => {
      this.storeReturnCard(card)
      Turbo.visit(card.dataset.leadUrl)
    }, 390)
  }

  showSheet(card) {
    if (!this.hasSheetTarget) return

    window.clearTimeout(this.tapTimer)
    this.populateSheet(card)
    this.sheetTarget.hidden = false
    document.documentElement.classList.add("lead-pwa-sheet-open")
  }

  populateSheet(card) {
    if (!this.hasSheetTarget) return

    const name = card.dataset.leadName || "Lead"
    const phone = card.dataset.leadPhone || "Sem telefone"
    const status = card.dataset.leadStatus || ""

    this.sheetTarget.dataset.leadId = card.dataset.leadId
    if (this.hasSheetNameTarget) this.sheetNameTarget.textContent = name
    if (this.hasSheetMetaTarget) this.sheetMetaTarget.textContent = `${phone} · ${status}`
    if (this.hasSheetOpenLinkTarget) this.sheetOpenLinkTarget.href = card.dataset.leadUrl
    if (this.hasSheetWhatsappFormTarget) this.sheetWhatsappFormTarget.action = card.dataset.whatsappUrl
    if (this.hasSheetStatusFormTarget) this.sheetStatusFormTarget.action = card.dataset.updateUrl
    if (this.hasSheetStatusSelectTarget) this.sheetStatusSelectTarget.value = status
    if (this.hasSheetTaskLeadIdTarget) this.sheetTaskLeadIdTarget.value = card.dataset.leadId
    if (this.hasSheetScheduleFormTarget) this.sheetScheduleFormTarget.action = `${card.dataset.updateUrl}/schedule_activity`
    if (this.hasSheetNoteFormTarget) this.sheetNoteFormTarget.action = `${card.dataset.updateUrl}/log_contact`
  }

  createGhost(card, x, y) {
    this.removeGhost()
    this.ghost = card.cloneNode(true)
    this.ghost.removeAttribute("id")
    this.ghost.classList.add("lead-pwa-drag-ghost")
    this.ghost.style.width = `${card.getBoundingClientRect().width}px`
    document.body.appendChild(this.ghost)
    this.moveGhost(x, y)
  }

  moveGhost(x, y) {
    if (!this.ghost) return

    this.ghost.style.left = `${x}px`
    this.ghost.style.top = `${y}px`
  }

  removeGhost() {
    this.ghost?.remove()
    this.ghost = null
  }

  updateDropTarget(x, y) {
    if (!this.hasColumnsTarget || !this.drag) return

    const ghostDisplay = this.ghost?.style.display
    if (this.ghost) this.ghost.style.display = "none"
    const element = document.elementFromPoint(x, y)
    if (this.ghost) this.ghost.style.display = ghostDisplay || ""

    const column = element?.closest?.(".lead-pwa-kanban-column")
    if (!column) return

    this.drag.activeColumn = column
    this.clearActiveDropTarget()
    column.classList.add("is-drop-target")
  }

  clearActiveDropTarget() {
    this.element.querySelectorAll(".lead-pwa-kanban-column.is-drop-target").forEach((column) => {
      column.classList.remove("is-drop-target")
    })
  }

  addGlobalDragListeners() {
    if (this.globalDragListenersActive) return

    this.globalDragListenersActive = true
    document.documentElement.classList.add("lead-pwa-card-dragging")
    window.addEventListener("pointermove", this.boundGlobalDragMove, { passive: false })
    window.addEventListener("pointerup", this.boundGlobalDragEnd, { passive: false })
    window.addEventListener("pointercancel", this.boundGlobalDragCancel, { passive: false })
    window.addEventListener("touchmove", this.boundGlobalDragMove, { passive: false })
    window.addEventListener("touchend", this.boundGlobalDragEnd, { passive: false })
    window.addEventListener("touchcancel", this.boundGlobalDragCancel, { passive: false })
  }

  removeGlobalDragListeners() {
    if (!this.globalDragListenersActive) return

    this.globalDragListenersActive = false
    document.documentElement.classList.remove("lead-pwa-card-dragging")
    window.removeEventListener("pointermove", this.boundGlobalDragMove)
    window.removeEventListener("pointerup", this.boundGlobalDragEnd)
    window.removeEventListener("pointercancel", this.boundGlobalDragCancel)
    window.removeEventListener("touchmove", this.boundGlobalDragMove)
    window.removeEventListener("touchend", this.boundGlobalDragEnd)
    window.removeEventListener("touchcancel", this.boundGlobalDragCancel)
  }

  eventPoint(event) {
    const touch = event.touches?.[0] || event.changedTouches?.[0]
    if (touch) return { x: touch.clientX, y: touch.clientY }
    if (Number.isFinite(event.clientX) && Number.isFinite(event.clientY)) return { x: event.clientX, y: event.clientY }
    return null
  }

  autoScrollColumns(x) {
    if (!this.hasColumnsTarget) return

    const rect = this.columnsTarget.getBoundingClientRect()
    const edge = 58
    if (x > rect.right - edge) this.columnsTarget.scrollLeft += 14
    if (x < rect.left + edge) this.columnsTarget.scrollLeft -= 14
  }

  moveCardToColumn(card, column) {
    const cardsContainer = column.querySelector(".lead-pwa-kanban-column__cards")
    const empty = cardsContainer?.querySelector(".lead-pwa-kanban__empty")
    empty?.remove()
    cardsContainer?.prepend(card)
  }

  updateColumnCounts(previousStatus, nextStatus) {
    if (!previousStatus || !nextStatus || previousStatus === nextStatus) return

    this.adjustColumnCount(previousStatus, -1)
    this.adjustColumnCount(nextStatus, 1)
  }

  adjustColumnCount(status, delta) {
    const column = this.columnForStatus(status)
    const count = column?.querySelector(".lead-pwa-kanban-column__count")
    const tabCount = this.triggerForColumn(column)?.querySelector(".lead-pwa-tab__count")

    if (count) this.writeAdjustedCount(count, delta)
    if (tabCount) this.writeAdjustedCount(tabCount, delta)
  }

  writeAdjustedCount(element, delta) {
    const current = Number.parseInt(element.textContent.replace(/\D/g, ""), 10) || 0
    element.textContent = String(Math.max(current + delta, 0))
  }

  centerColumn(column, behavior = "auto") {
    if (!column || !this.hasColumnsTarget) return

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

    const activeTrigger = this.triggerForColumn(column)

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

  storeReturnCard(card) {
    if (!card?.id) return
    window.location.hash = card.id
  }

  columnById(id) {
    return id ? document.getElementById(id) : null
  }

  columnForStatus(status) {
    return Array.from(this.element.querySelectorAll(".lead-pwa-kanban-column")).find((column) => {
      return column.dataset.leadStatus === status
    })
  }

  triggerForColumn(column) {
    if (!column?.id) return null

    return this.element.querySelector(`[data-lead-pwa-kanban-column-id="${CSS.escape(column.id)}"]`)
  }

  clearPressTimer() {
    window.clearTimeout(this.pressTimer)
    this.pressTimer = null
  }

  isInteractiveElement(element) {
    return Boolean(element.closest("a, button, input, select, textarea, label"))
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  async parseResponse(response) {
    const text = await response.text()
    if (!text) return {}

    try {
      return JSON.parse(text)
    } catch (_error) {
      return { message: text }
    }
  }

  notify(message, type = "info") {
    window.dispatchEvent(new CustomEvent("ax:toast", { detail: { message, type } }))
  }
}
