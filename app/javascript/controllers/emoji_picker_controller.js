import AxPopoverController from "controllers/ax_popover_controller"

// Popover de emojis do composer (offline, sem dependência externa).
// Insere o emoji na posição do cursor do textarea alvo e dispara "input"
// para o wa-composer atualizar estado/contadores.
//
//   <div data-controller="emoji-picker" data-emoji-picker-target-selector-value="...">
//     <button data-action="emoji-picker#toggle">🙂</button>
//   </div>
const EMOJIS = [
  "😀", "😄", "😁", "😅", "😂", "🙂", "😉", "😊",
  "😍", "🥰", "😘", "😎", "🤝", "👍", "👏", "🙏",
  "👋", "💪", "🎉", "✨", "🔥", "❤️", "💙", "✅",
  "⭐", "🏠", "🏢", "🔑", "📍", "📷", "📅", "⏰",
  "💰", "📄", "✍️", "📞", "💬", "🚗", "🌳", "☀️",
  "🤔", "😬", "😢", "🙌", "🫡", "🤩", "😴", "🚀"
]

export default class extends AxPopoverController {
  open() {
    this.buildPopover()
    super.open()
  }

  buildPopover() {
    if (!this.hasPopoverTarget || this.popoverTarget.childElementCount > 0) return

    EMOJIS.forEach((emoji) => {
      const button = document.createElement("button")
      button.type = "button"
      button.textContent = emoji
      button.setAttribute("aria-label", `Inserir ${emoji}`)
      button.addEventListener("click", (event) => {
        event.stopPropagation()
        this.insert(emoji)
      })
      this.popoverTarget.appendChild(button)
    })
  }

  insert(emoji) {
    const textarea = this.element.closest("form")?.querySelector('[data-wa-composer-target="body"]')
    if (!textarea || textarea.disabled) return

    const start = textarea.selectionStart ?? textarea.value.length
    const end = textarea.selectionEnd ?? textarea.value.length
    textarea.value = textarea.value.slice(0, start) + emoji + textarea.value.slice(end)
    const cursor = start + emoji.length
    textarea.setSelectionRange(cursor, cursor)
    textarea.focus()
    textarea.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
