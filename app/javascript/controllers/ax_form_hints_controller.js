import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.hydrate()
  }

  hydrate() {
    this.element.querySelectorAll(".ax-field-hint").forEach((hint) => {
      const text = hint.textContent.replace(/\s+/g, " ").trim()
      if (!text) return

      hint.setAttribute("title", text)
      if (hint.classList.contains("text-success") || hint.classList.contains("text-danger")) return

      const field = hint.closest(".ax-field-group, .ax-field, [class*='ax-span-']")
      const label = field?.querySelector(".ax-field-label")
      if (label && !label.querySelector(".ax-field-tooltip")) {
        label.appendChild(this.buildTooltip(text))
      }

      hint.setAttribute("aria-hidden", "true")
    })
  }

  buildTooltip(text) {
    const tooltip = document.createElement("span")
    tooltip.className = "ax-field-tooltip"
    tooltip.setAttribute("tabindex", "0")
    tooltip.setAttribute("role", "button")
    tooltip.setAttribute("title", text)
    tooltip.setAttribute("aria-label", `Ajuda: ${text}`)
    tooltip.innerHTML = '<i class="bi bi-info-circle"></i>'
    return tooltip
  }
}
