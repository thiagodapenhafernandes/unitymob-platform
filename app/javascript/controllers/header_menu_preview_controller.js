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
        return {
          label: input.value.trim() || input.dataset.default || input.placeholder,
          visible: row.querySelector("[data-role='visible']").checked,
          bar: row.querySelector("[data-role='bar']").checked
        }
      })
      .filter((item) => item.label)
    const visible = items.filter((item) => item.visible)

    this.fill(this.barTarget, visible.filter((item) => item.bar), "span")
    this.fill(this.menuTarget, visible, "li")
    if (this.hasCountTarget) this.countTarget.textContent = `${visible.length} visíveis`
  }

  fill(container, items, tag) {
    container.replaceChildren(...items.map((item) => Object.assign(document.createElement(tag), { textContent: item.label })))
  }
}
