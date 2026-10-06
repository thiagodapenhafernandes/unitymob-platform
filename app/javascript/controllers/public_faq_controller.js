import { Controller } from "@hotwired/stimulus"

// O editor usa o mesmo filtro no iframe sem habilitar scripts no conteúdo importado.
export function applyFAQFilters(element, category = "", query = "") {
  const normalize = (text) => text.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
  const text = normalize(query.trim())
  let visible = 0
  element.querySelectorAll('[data-public-faq-target="filter"]').forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.category === category)))
  element.querySelectorAll('[data-public-faq-target="item"]').forEach((item) => {
    const categories = (item.dataset.categories || "").split(",").map((value) => value.trim())
    item.hidden = Boolean((category && !categories.includes(category)) || (text && !normalize(item.textContent).includes(text)))
    if (!item.hidden) visible++
  })
  element.querySelectorAll('[data-public-faq-target="group"]').forEach((group) => {
    group.hidden = ![...group.querySelectorAll('[data-public-faq-target="item"]')].some((item) => !item.hidden)
  })
  const empty = element.querySelector('[data-public-faq-target="empty"]')
  if (empty) empty.hidden = visible > 0
}

export default class extends Controller {
  static targets = ["search"]
  connect() { this.category = ""; this.update() }
  filter(event) { this.category = event.currentTarget.dataset.category; this.update() }
  update() { applyFAQFilters(this.element, this.category, this.hasSearchTarget ? this.searchTarget.value : "") }
}
