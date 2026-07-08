import { Controller } from "@hotwired/stimulus"

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

export default class extends Controller {
  static targets = ["popover"]

  connect() {
    this.onDocClick = this.closeOnOutside.bind(this)
    this.onKey = this.closeOnEsc.bind(this)
  }

  disconnect() {
    this.close()
  }

  toggle(event) {
    event.preventDefault()
    if (this.hasPopoverTarget && !this.popoverTarget.hidden) {
      this.close()
      return
    }
    this.open()
  }

  open() {
    this.buildPopover()
    this.popoverTarget.hidden = false
    document.addEventListener("click", this.onDocClick)
    document.addEventListener("keydown", this.onKey)
  }

  close() {
    if (this.hasPopoverTarget) this.popoverTarget.hidden = true
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKey)
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

  closeOnOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  closeOnEsc(event) {
    if (event.key === "Escape") this.close()
  }
}
