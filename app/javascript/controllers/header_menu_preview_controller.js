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

    this.fill(this.barTarget, visible.filter((item) => item.bar), "span", "hps-header__link")
    this.fill(this.menuTarget, visible, "li")
    if (this.hasCountTarget) this.countTarget.textContent = `${visible.length} visíveis`
  }

  syncSummary(row, item) {
    const title = row.querySelector("[data-role='title']")
    if (title) title.textContent = item.label
    const urlInput = row.querySelector("[data-role='url']")
    if (urlInput) {
      const dest = row.querySelector("[data-role='dest']")
      // Item do sistema sem endereço próprio mostra o padrão da página (data-default).
      if (dest) dest.textContent = urlInput.value.trim() || urlInput.dataset.default || "Sem endereço"
    }
    const hidden = row.querySelector("[data-role='badge-hidden']")
    if (hidden) hidden.hidden = item.visible
    const bar = row.querySelector("[data-role='badge-bar']")
    if (bar) bar.hidden = !item.bar
  }

  fill(container, items, tag, className = null) {
    container.replaceChildren(...items.map((item) => {
      const node = Object.assign(document.createElement(tag), { textContent: item.label })
      if (className) node.className = className
      return node
    }))
  }
}
