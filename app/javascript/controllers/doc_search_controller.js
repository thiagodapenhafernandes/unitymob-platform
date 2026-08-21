import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "item", "empty", "count"]

  connect() {
    this.search()
  }

  search() {
    const query = this.normalize(this.inputTarget?.value)
    let visibleCount = 0

    this.itemTargets.forEach((item) => {
      const text = this.normalize(item.textContent)
      const visible = query.blank || text.includes(query.value)
      item.hidden = !visible
      if (visible) visibleCount += 1
      if (query.present && visible && item.tagName.toLowerCase() === "details") item.open = true
    })

    if (this.hasEmptyTarget) this.emptyTarget.hidden = visibleCount > 0
    if (this.hasCountTarget) {
      this.countTarget.textContent = query.present ? `${visibleCount} seção(ões) encontrada(s)` : ""
    }
  }

  clear() {
    if (!this.hasInputTarget) return

    this.inputTarget.value = ""
    this.search()
    this.inputTarget.focus()
  }

  normalize(value) {
    const normalized = (value || "").toString().normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim()
    return {
      value: normalized,
      present: normalized.length > 0,
      blank: normalized.length === 0
    }
  }
}
