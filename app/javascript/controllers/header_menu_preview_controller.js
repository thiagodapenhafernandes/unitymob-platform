import { Controller } from "@hotwired/stimulus"

// Redesenha o topo e o menu suspenso da prévia a partir das linhas do editor (data-role="label|visible|bar").
export default class extends Controller {
  static targets = ["rows", "bar", "menu", "count"]

  connect() {
    this.render()
  }

  render() {
    const items = [...this.rowsTarget.querySelectorAll(".nested-fields")]
      .filter((row) => row.style.display !== "none")
      .map((row) => {
        const input = row.querySelector("[data-role='label']")
        const item = {
          label: input.value.trim() || input.dataset.default || input.placeholder,
          visible: row.querySelector("[data-role='visible']").checked,
          bar: row.querySelector("[data-role='bar']").checked
        }
        this.syncSummary(row, item)
        return item
      })
      .filter((item) => item.label)
    const visible = items.filter((item) => item.visible)

    this.fill(this.barTarget, visible.filter((item) => item.bar), "span")
    this.fill(this.menuTarget, visible, "li")
    if (this.hasCountTarget) this.countTarget.textContent = `${visible.length} visíveis`
  }

  syncSummary(row, item) {
    const title = row.querySelector("[data-role='title']")
    if (title) title.textContent = item.label
    const urlInput = row.querySelector("[data-role='url']")
    if (urlInput) {
      const dest = row.querySelector("[data-role='dest']")
      if (dest) dest.textContent = urlInput.value.trim() || "Sem endereço"
    }
    const hidden = row.querySelector("[data-role='badge-hidden']")
    if (hidden) hidden.hidden = item.visible
    const bar = row.querySelector("[data-role='badge-bar']")
    if (bar) bar.hidden = !item.bar
  }

  fill(container, items, tag) {
    container.replaceChildren(...items.map((item) => Object.assign(document.createElement(tag), { textContent: item.label })))
  }
}
