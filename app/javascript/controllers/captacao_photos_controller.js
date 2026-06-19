import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "input",
    "newList",
    "existingList",
    "emptyState",
    "orderInput",
    "flowSelect",
    "uploadPanel",
    "newPhotosPanel",
    "existingPhotosPanel",
    "schedulePanel",
    "externalScheduleButton",
    "internalScheduleButton",
    "scheduledAtGroup",
    "scheduledAtInput",
    "calendarGrid",
    "slotList"
  ]

  static values = {
    scheduleUrl: String,
    blockedDates: Array,
    bookedSlots: Array
  }

  connect() {
    this.selectedFiles = []
    this.selectedDate = null
    this.refreshFlow()
    this.refreshExistingIndexes()
    this.buildCalendar()
  }

  filesChanged(event) {
    const incomingFiles = Array.from(event.target.files || [])
    if (event.currentTarget.dataset.captacaoPhotosAppend === "true") {
      this.selectedFiles = this.selectedFiles.concat(incomingFiles)
      event.currentTarget.value = ""
      this.syncInputFiles()
    } else {
      this.selectedFiles = incomingFiles
    }
    this.renderNewFiles()
  }

  moveNewUp(event) {
    this.moveNew(event.currentTarget.dataset.index, -1)
  }

  moveNewDown(event) {
    this.moveNew(event.currentTarget.dataset.index, 1)
  }

  removeNew(event) {
    const index = Number(event.currentTarget.dataset.index)
    this.selectedFiles.splice(index, 1)
    this.syncInputFiles()
    this.renderNewFiles()
  }

  highlightNew(event) {
    const index = Number(event.currentTarget.value)
    if (index > 0) {
      const [file] = this.selectedFiles.splice(index, 1)
      this.selectedFiles.unshift(file)
      this.syncInputFiles()
      this.renderNewFiles()
    }
  }

  moveExistingUp(event) {
    this.moveExisting(event.currentTarget.closest("[data-photo-id]"), -1)
  }

  moveExistingDown(event) {
    this.moveExisting(event.currentTarget.closest("[data-photo-id]"), 1)
  }

  highlightExisting(event) {
    const item = event.currentTarget.closest("[data-photo-id]")
    this.existingListTarget.prepend(item)
    this.refreshExistingIndexes()
  }

  refreshFlow(event) {
    const value = this.hasFlowSelectTarget ? this.flowSelectTarget.value : ""
    const uploadSelected = value === "upload"
    this.toggle(this.uploadPanelTarget, uploadSelected)
    this.toggle(this.newPhotosPanelTarget, uploadSelected)
    if (this.hasExistingPhotosPanelTarget) {
      this.toggle(this.existingPhotosPanelTarget, uploadSelected)
    }
    this.toggle(this.schedulePanelTarget, value === "schedule")

    if (this.hasExternalScheduleButtonTarget) {
      this.toggle(this.externalScheduleButtonTarget, value === "schedule" && this.scheduleUrlValue.length > 0)
    }

    if (this.hasInternalScheduleButtonTarget) {
      this.toggle(this.internalScheduleButtonTarget, value === "schedule" && this.scheduleUrlValue.length === 0)
    }

    if (this.hasScheduledAtGroupTarget) {
      this.toggle(this.scheduledAtGroupTarget, value === "schedule")
    }

    if (event && value === "schedule") {
      this.openScheduler()
    }
  }

  openScheduler() {
    if (this.scheduleUrlValue.length > 0) {
      window.open(this.scheduleUrlValue, "_blank", "noopener")
      return
    }

    const modalElement = document.getElementById("captacaoPhotoSchedulerModal")
    if (!modalElement) return
    modalElement.dispatchEvent(new CustomEvent("ax-modal:open"))
  }

  selectDate(event) {
    this.selectedDate = event.currentTarget.dataset.date
    this.calendarGridTarget.querySelectorAll("[data-date]").forEach((button) => {
      button.classList.toggle("active", button.dataset.date === this.selectedDate)
    })
    this.renderSlots()
  }

  selectSlot(event) {
    if (!this.selectedDate || !this.hasScheduledAtInputTarget) return

    const slot = event.currentTarget.dataset.slot
    this.scheduledAtInputTarget.value = `${this.selectedDate}T${slot}`

    const modalElement = document.getElementById("captacaoPhotoSchedulerModal")
    if (modalElement) {
      modalElement.dispatchEvent(new CustomEvent("ax-modal:close"))
    }
  }

  moveNew(rawIndex, direction) {
    const index = Number(rawIndex)
    const targetIndex = index + direction
    if (targetIndex < 0 || targetIndex >= this.selectedFiles.length) return

    const [file] = this.selectedFiles.splice(index, 1)
    this.selectedFiles.splice(targetIndex, 0, file)
    this.syncInputFiles()
    this.renderNewFiles()
  }

  moveExisting(item, direction) {
    if (!item) return

    const sibling = direction < 0 ? item.previousElementSibling : item.nextElementSibling
    if (!sibling) return

    if (direction < 0) {
      this.existingListTarget.insertBefore(item, sibling)
    } else {
      this.existingListTarget.insertBefore(sibling, item)
    }
    this.refreshExistingIndexes()
  }

  renderNewFiles() {
    this.newListTarget.innerHTML = ""
    this.toggle(this.emptyStateTarget, this.selectedFiles.length === 0)

    this.selectedFiles.forEach((file, index) => {
      const row = document.createElement("div")
      row.className = "captacao-photo-row"

      const preview = document.createElement("img")
      preview.alt = file.name
      preview.className = "captacao-photo-thumb"
      preview.src = URL.createObjectURL(file)

      row.innerHTML = `
        <div class="captacao-photo-index">${index + 1}</div>
        <div class="captacao-photo-preview"></div>
        <div class="captacao-photo-meta">
          <strong>${this.escapeHtml(file.name)}</strong>
          <span class="captacao-photo-size">${this.formatSize(file.size)}</span>
          <label class="captacao-highlight-choice">
            <input type="radio" name="new_photo_highlight" value="${index}" ${index === 0 ? "checked" : ""} data-action="change->captacao-photos#highlightNew">
            Destaque
          </label>
        </div>
        <div class="captacao-photo-actions">
          <button type="button" class="captacao-photo-action" data-index="${index}" data-action="captacao-photos#moveNewUp" aria-label="Subir foto"><i class="bi bi-arrow-up"></i></button>
          <button type="button" class="captacao-photo-action" data-index="${index}" data-action="captacao-photos#moveNewDown" aria-label="Descer foto"><i class="bi bi-arrow-down"></i></button>
          <button type="button" class="captacao-photo-action captacao-photo-action--danger" data-index="${index}" data-action="captacao-photos#removeNew" aria-label="Remover foto"><i class="bi bi-trash"></i></button>
        </div>
      `
      row.querySelector(".captacao-photo-preview").appendChild(preview)
      this.newListTarget.appendChild(row)
    })
  }

  syncInputFiles() {
    const dataTransfer = new DataTransfer()
    this.selectedFiles.forEach((file) => dataTransfer.items.add(file))
    this.inputTarget.files = dataTransfer.files
  }

  refreshExistingIndexes() {
    if (!this.hasExistingListTarget || !this.hasOrderInputTarget) return

    const ids = []
    this.existingListTarget.querySelectorAll("[data-photo-id]").forEach((item, index) => {
      item.querySelector("[data-photo-index]").textContent = index + 1
      item.querySelectorAll("[data-action*='moveExistingUp']").forEach((button) => button.disabled = index === 0)
      item.querySelectorAll("[data-action*='moveExistingDown']").forEach((button) => button.disabled = index === this.existingListTarget.children.length - 1)
      const radio = item.querySelector("input[type='radio']")
      if (radio) radio.checked = index === 0
      ids.push(item.dataset.photoId)
    })

    this.orderInputTarget.value = ids.join(",")
  }

  buildCalendar() {
    if (!this.hasCalendarGridTarget) return

    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const formatter = new Intl.DateTimeFormat("pt-BR", { weekday: "short", day: "2-digit", month: "2-digit" })
    const days = []
    const cursor = new Date(today)

    while (days.length < 18) {
      const day = cursor.getDay()
      const isoDate = this.localDateValue(cursor)
      if (day !== 0 && !this.blockedDatesValue.includes(isoDate)) days.push(new Date(cursor))
      cursor.setDate(cursor.getDate() + 1)
    }

    this.calendarGridTarget.innerHTML = days.map((date, index) => {
      const isoDate = this.localDateValue(date)
      return `<button type="button" class="captacao-calendar-day ${index === 0 ? "active" : ""}" data-date="${isoDate}" data-action="captacao-photos#selectDate">${formatter.format(date)}</button>`
    }).join("")

    this.selectedDate = days[0] ? this.localDateValue(days[0]) : null
    this.renderSlots()
  }

  renderSlots() {
    if (!this.hasSlotListTarget) return

    const slots = ["09:00", "09:45", "10:30", "11:15", "14:00", "14:45", "15:30", "16:15"]
    const availableSlots = slots.filter((slot) => !this.bookedSlotsValue.includes(`${this.selectedDate}T${slot}`))

    if (availableSlots.length === 0) {
      this.slotListTarget.innerHTML = '<div class="captacao-slot-empty">Não há horários disponíveis para este dia.</div>'
      return
    }

    this.slotListTarget.innerHTML = availableSlots.map((slot) => (
      `<button type="button" class="captacao-time-slot" data-slot="${slot}" data-action="captacao-photos#selectSlot">${slot}</button>`
    )).join("")
  }

  toggle(element, visible) {
    if (!element) return
    element.hidden = !visible
  }

  formatSize(bytes) {
    if (!bytes) return "0 KB"
    return `${Math.max(1, Math.round(bytes / 1024))} KB`
  }

  localDateValue(date) {
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    return `${year}-${month}-${day}`
  }

  escapeHtml(value) {
    return value.replace(/[&<>"']/g, (char) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;"
    }[char]))
  }
}
