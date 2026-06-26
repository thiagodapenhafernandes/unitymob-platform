import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { combine } from "@atlaskit/pragmatic-drag-and-drop/combine"
import {
  draggable,
  dropTargetForElements,
  monitorForElements
} from "@atlaskit/pragmatic-drag-and-drop/element/adapter"

export default class extends Controller {
  static targets = ["column"]

  connect() {
    this.isTouchDevice = window.matchMedia("(pointer: coarse)").matches || "ontouchstart" in window
    this.pointerX = null
    this.dragState = null
    this.recentlyDragged = false
    this.dragBlockedCard = null

    this.trackDragPointer = (event) => this.rememberPointer(event)
    this.capturePointerDown = (event) => this.preparePointerIntent(event)
    this.openCardFromClick = (event) => this.openCard(event)

    this.element.addEventListener("pointerdown", this.capturePointerDown, true)
    this.element.addEventListener("click", this.openCardFromClick)

    this.cleanupDragAndDrop = combine(
      ...this.columnTargets.map((column) => this.registerColumn(column)),
      ...Array.from(this.element.querySelectorAll(".lead-kanban-card")).map((card) => this.registerCard(card)),
      monitorForElements({
        canMonitor: ({ source }) => this.isLeadCardSource(source),
        onDrag: ({ source, location }) => this.moveCardWithPointer(source, location),
        onDropTargetChange: ({ source, location }) => this.moveCardWithPointer(source, location),
        onDrop: ({ source, location }) => this.dropCard(source, location)
      })
    )

    this.restoreReturnedCard()
  }

  disconnect() {
    this.cleanupDragAndDrop?.()
    this.stopBoardAutoScroll()
    this.unbindDragListeners()
    this.element.removeEventListener("pointerdown", this.capturePointerDown, true)
    this.element.removeEventListener("click", this.openCardFromClick)
  }

  registerColumn(column) {
    return dropTargetForElements({
      element: column,
      canDrop: ({ source }) => this.isLeadCardSource(source),
      getData: () => ({
        type: "lead-column",
        status: column.dataset.leadKanbanStatus
      }),
      getIsSticky: () => true,
      onDragEnter: () => this.setActiveColumn(column),
      onDragLeave: () => {
        if (this.activeColumn === column) this.clearActiveColumn()
      }
    })
  }

  registerCard(card) {
    return draggable({
      element: card,
      canDrag: () => this.dragBlockedCard !== card,
      getInitialData: () => ({
        type: "lead-card",
        leadId: card.dataset.leadId
      }),
      onDragStart: () => this.beginDrag(card),
      onDrop: () => this.finishDrag(card)
    })
  }

  changeStatus(event) {
    const card = event.target.closest(".lead-kanban-card")
    const status = event.target.value
    if (!card || !status) return
    if (card.dataset.currentStatus === status) return

    this.updateLead(card, status, { moveCard: true })
  }

  beginDrag(card) {
    this.dragState = {
      card,
      previousColumn: card.parentElement,
      previousStatus: card.dataset.currentStatus
    }
    this.recentlyDragged = true
    card.classList.add("lead-kanban-card--dragging", "lead-kanban-card--chosen")
    this.element.classList.add("ax-board--dragging")
    this.setActiveColumn(card.parentElement)
    this.bindDragListeners()
    this.startBoardAutoScroll()
  }

  finishDrag(card) {
    card?.classList.remove("lead-kanban-card--dragging", "lead-kanban-card--chosen")
    this.element.classList.remove("ax-board--dragging")
    this.stopBoardAutoScroll()
    this.unbindDragListeners()
    this.clearActiveColumn()
    window.setTimeout(() => {
      this.recentlyDragged = false
    }, 80)
  }

  moveCardWithPointer(source, location) {
    if (!this.isLeadCardSource(source)) return

    const card = source.element
    const column = this.columnFromLocation(location)
    const input = location?.current?.input
    if (!card || !column || !input) return

    this.rememberPointer(input)
    this.setActiveColumn(column)
    this.placeCardAtPointer(card, column, input.clientY)
  }

  dropCard(source, location) {
    if (!this.isLeadCardSource(source)) return

    const card = source.element
    const column = this.columnFromLocation(location)
    const status = this.statusFromLocation(location)

    if (!card || !column || !status) {
      this.restoreDraggedCard()
      return
    }

    this.snapColumnIntoView(column)

    if (card.dataset.currentStatus !== status) {
      this.updateLead(card, status)
    }

    this.dragState = null
  }

  placeCardAtPointer(card, column, pointerY) {
    const beforeCard = this.cardBeforePointer(column, card, pointerY)
    if (beforeCard) {
      column.insertBefore(card, beforeCard)
    } else {
      column.appendChild(card)
    }
  }

  cardBeforePointer(column, draggedCard, pointerY) {
    const cards = Array.from(column.querySelectorAll(".lead-kanban-card")).filter((card) => card !== draggedCard)

    return cards.find((card) => {
      const rect = card.getBoundingClientRect()
      return pointerY < rect.top + rect.height * 0.58
    })
  }

  restoreDraggedCard() {
    if (!this.dragState?.card || !this.dragState.previousColumn) return

    this.dragState.previousColumn.prepend(this.dragState.card)
    this.snapColumnIntoView(this.dragState.previousColumn)
    this.dragState = null
  }

  preparePointerIntent(event) {
    const card = event.target.closest(".lead-kanban-card")
    if (!card) {
      this.dragBlockedCard = null
      return
    }

    this.dragBlockedCard = this.isInteractiveElement(event.target) ? card : null
  }

  openCard(event) {
    if (event.defaultPrevented || this.recentlyDragged || this.isInteractiveElement(event.target)) return

    const card = event.target.closest(".lead-kanban-card")
    const url = card?.dataset.leadUrl
    if (!card || !url) return

    event.preventDefault()
    this.storeReturnCard(card)
    Turbo.visit(url)
  }

  storeReturnCard(card) {
    if (!card.dataset.leadId) return

    try {
      window.sessionStorage.setItem("leadKanbanReturn", JSON.stringify({
        leadId: card.dataset.leadId,
        path: window.location.pathname + window.location.search
      }))
    } catch (_error) {
      // Navegacao continua normalmente mesmo quando storage local estiver bloqueado.
    }
  }

  restoreReturnedCard() {
    let raw
    try {
      raw = window.sessionStorage.getItem("leadKanbanReturn")
    } catch (_error) {
      return
    }
    if (!raw) return

    let payload
    try {
      payload = JSON.parse(raw)
    } catch (_error) {
      window.sessionStorage.removeItem("leadKanbanReturn")
      return
    }

    if (!payload?.leadId) return

    window.requestAnimationFrame(() => {
      const card = Array.from(this.element.querySelectorAll(".lead-kanban-card")).find((element) => {
        return element.dataset.leadId === String(payload.leadId)
      })
      if (!card) return

      card.scrollIntoView({
        behavior: this.isTouchDevice ? "smooth" : "auto",
        block: "center",
        inline: "center"
      })
      card.classList.add("lead-kanban-card--returned")
      window.setTimeout(() => card.classList.remove("lead-kanban-card--returned"), 1600)
      window.sessionStorage.removeItem("leadKanbanReturn")
    })
  }

  isLeadCardSource(source) {
    return source?.data?.type === "lead-card" && source?.element?.classList?.contains("lead-kanban-card")
  }

  columnFromLocation(location) {
    const target = location?.current?.dropTargets?.find((dropTarget) => dropTarget.data?.type === "lead-column")
    return target?.element || null
  }

  statusFromLocation(location) {
    const target = location?.current?.dropTargets?.find((dropTarget) => dropTarget.data?.type === "lead-column")
    return target?.data?.status || null
  }

  isInteractiveElement(element) {
    return Boolean(element.closest("a, button, input, select, textarea, label, [data-no-drag]"))
  }

  async updateLead(card, status, { moveCard = false } = {}) {
    const previousStatus = card.dataset.currentStatus
    const select = card.querySelector("[data-lead-kanban-status-select]")
    const updateUrl = card.dataset.updateUrl

    if (!updateUrl) {
      if (select) select.value = previousStatus
      this.returnToPreviousColumn(card, previousStatus)
      this.notify("Não foi possível identificar este lead no Kanban.", "danger")
      return
    }

    card.classList.add("lead-kanban-card--saving")

    try {
      const response = await fetch(updateUrl, {
        method: "PATCH",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        body: JSON.stringify({ lead: { status } })
      })
      const data = await this.parseResponse(response)

      if (!response.ok) {
        const error = new Error(data.message || "Não foi possível atualizar o status do lead.")
        error.payload = data
        error.status = response.status
        throw error
      }

      const nextStatus = data.status || status
      if (moveCard) this.moveCardToStatus(card, nextStatus)
      card.dataset.currentStatus = nextStatus
      if (select) select.value = nextStatus
      this.updateCardBadge(card, nextStatus, data.badge_class)
      this.updateCounters(previousStatus, nextStatus)
    } catch (error) {
      if (select) select.value = previousStatus
      this.returnToPreviousColumn(card, previousStatus)
      this.notify(error.message || "Não foi possível atualizar o status do lead.", "danger")
      if (error.payload?.error === "lead_unavailable") this.reloadSoon()
    } finally {
      card.classList.remove("lead-kanban-card--saving")
    }
  }

  updateCardBadge(card, status, badgeClass) {
    const badge = card.querySelector("[data-lead-kanban-status-badge]")
    if (!badge) return

    if (badge.classList.contains("ax-badge")) {
      badge.className = `ax-badge ax-badge--${this.axToneFor(badgeClass)} lead-kanban-status-badge`
    } else {
      badge.className = `badge bg-${badgeClass || "dark"}`
    }
    badge.textContent = status
  }

  axToneFor(badgeClass) {
    return {
      success: "green",
      danger: "red",
      warning: "amber",
      info: "blue",
      primary: "blue",
      secondary: "gray",
      light: "gray",
      dark: "gray"
    }[badgeClass] || "gray"
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
    if (!column) return

    column.prepend(card)
    this.snapColumnIntoView(column)
  }

  moveCardToStatus(card, status) {
    const column = this.columnTargets.find((target) => target.dataset.leadKanbanStatus === status)
    if (!column) return

    if (card.parentElement !== column) column.prepend(card)
    this.snapColumnIntoView(column)
  }

  snapColumnIntoView(columnBody) {
    const column = columnBody?.closest?.(".ax-board__column")
    if (!column) return

    column.scrollIntoView({
      behavior: this.isTouchDevice ? "smooth" : "auto",
      block: "nearest",
      inline: this.isTouchDevice ? "center" : "nearest"
    })
  }

  setActiveColumn(columnBody) {
    if (!columnBody || this.activeColumn === columnBody) return

    this.clearActiveColumn()
    this.activeColumn = columnBody
    this.activeColumn.classList.add("lead-kanban-column--active")
  }

  clearActiveColumn() {
    this.activeColumn?.classList.remove("lead-kanban-column--active")
    this.activeColumn = null
  }

  bindDragListeners() {
    window.addEventListener("pointermove", this.trackDragPointer, { passive: true })
    window.addEventListener("touchmove", this.trackDragPointer, { passive: true })
    window.addEventListener("mousemove", this.trackDragPointer, { passive: true })
  }

  unbindDragListeners() {
    window.removeEventListener("pointermove", this.trackDragPointer)
    window.removeEventListener("touchmove", this.trackDragPointer)
    window.removeEventListener("mousemove", this.trackDragPointer)
  }

  rememberPointer(event) {
    const point = event?.touches?.[0] || event?.changedTouches?.[0] || event
    if (Number.isFinite(point?.clientX)) this.pointerX = point.clientX
  }

  startBoardAutoScroll() {
    if (this.autoScrollFrame) return
    this.autoScrollFrame = window.requestAnimationFrame(() => this.boardAutoScrollTick())
  }

  stopBoardAutoScroll() {
    if (this.autoScrollFrame) window.cancelAnimationFrame(this.autoScrollFrame)
    this.autoScrollFrame = null
    this.pointerX = null
  }

  boardAutoScrollTick() {
    const speed = this.boardScrollSpeed()
    if (speed !== 0) this.element.scrollLeft += speed

    this.autoScrollFrame = window.requestAnimationFrame(() => this.boardAutoScrollTick())
  }

  boardScrollSpeed() {
    if (!Number.isFinite(this.pointerX)) return 0

    const rect = this.element.getBoundingClientRect()
    const edgeSize = Math.min(128, Math.max(72, rect.width * 0.24))
    const maxSpeed = this.isTouchDevice ? 26 : 18
    const leftDistance = this.pointerX - rect.left
    const rightDistance = rect.right - this.pointerX

    if (leftDistance < edgeSize) {
      return -this.edgeScrollSpeed(edgeSize - leftDistance, edgeSize, maxSpeed)
    }

    if (rightDistance < edgeSize) {
      return this.edgeScrollSpeed(edgeSize - rightDistance, edgeSize, maxSpeed)
    }

    return 0
  }

  edgeScrollSpeed(distanceIntoEdge, edgeSize, maxSpeed) {
    const ratio = Math.min(Math.max(distanceIntoEdge / edgeSize, 0), 1)
    return Math.ceil(maxSpeed * ratio)
  }

  async parseResponse(response) {
    const contentType = response.headers.get("content-type") || ""
    if (contentType.includes("application/json")) return response.json()

    const text = await response.text()
    return { message: text ? "Não foi possível atualizar o status do lead." : null }
  }

  notify(message, type = "danger") {
    if (window.axToast) {
      window.axToast({ message, type })
    } else {
      window.alert(message)
    }
  }

  reloadSoon() {
    window.clearTimeout(this.reloadTimer)
    this.reloadTimer = window.setTimeout(() => window.location.reload(), 1200)
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
