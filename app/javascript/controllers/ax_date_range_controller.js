import { Controller } from "@hotwired/stimulus"

// Dates stay as ISO calendar days; UTC arithmetic avoids daylight-saving shifts.
export default class extends Controller {
  static targets = ["start", "end", "day", "summary", "month"]

  connect() { this.refresh() }

  refresh() {
    const month = this.element.querySelector("[data-current-month]")?.dataset.currentMonth
    if (this.hasMonthTarget && month) this.monthTarget.value = month
    this.change()
  }

  select(event) {
    const day = event.currentTarget
    if (day.disabled) return
    const value = day.dataset.date
    const start = this.startTarget.value
    if (!start || this.endTarget.value) {
      this.startTarget.value = value
      this.endTarget.value = ""
    } else {
      this.startTarget.value = value < start ? value : start
      this.endTarget.value = value < start ? start : value
    }
    this.change()
  }

  change() {
    const start = this.startTarget.value
    const end = this.endTarget.value
    const invalid = start && end && end < start
    this.endTarget.setCustomValidity(invalid ? "A data final não pode ser anterior à inicial." : "")
    if (invalid) this.summaryTarget.textContent = "Ajuste a data final: ela deve ser igual ou posterior à inicial."
    else if (start && end) {
      const days = Math.round((Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / 86400000) + 1
      this.summaryTarget.textContent = `${this.label(start)} a ${this.label(end)} · ${days} ${days === 1 ? "dia" : "dias"}`
    } else this.summaryTarget.textContent = start ? `Início: ${this.label(start)}. Agora escolha o último dia.` : "Escolha a data inicial no calendário."
    this.paint()
  }

  label(value) { return value.split("-").reverse().join("/") }

  paint(preview = null) {
    const start = this.startTarget.value
    const end = this.endTarget.value || preview
    const low = end && end < start ? end : start
    const high = end && end < start ? start : end
    this.dayTargets.forEach(day => {
      const value = day.dataset.date
      const selected = !day.disabled && !!start && (value === start || (!!end && value >= low && value <= high))
      day.classList.toggle("is-selected", selected)
      day.classList.toggle("is-endpoint", selected && (value === low || value === high))
      day.classList.toggle("is-preview", selected && !!preview)
      day.setAttribute("aria-pressed", selected && !preview ? "true" : "false")
    })
  }

  preview(event) {
    if (this.startTarget.value && !this.endTarget.value) this.paint(event.currentTarget.dataset.date)
  }

  clearPreview() { this.paint() }

  clear() {
    this.startTarget.value = ""
    this.endTarget.value = ""
    this.change()
  }

  navigate(event) {
    const steps = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }
    const step = steps[event.key]
    if (!step) return
    event.preventDefault()
    let index = this.dayTargets.indexOf(event.currentTarget) + step
    while (this.dayTargets[index]?.disabled) index += step
    this.dayTargets[index]?.focus()
  }
}
