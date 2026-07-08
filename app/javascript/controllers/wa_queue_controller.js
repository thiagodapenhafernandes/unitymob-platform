import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "list", "filterButton"]

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    this.activeFilter = "all"
    this.observer = new MutationObserver(() => this.apply())
    if (this.hasListTarget) {
      this.observer.observe(this.listTarget, { childList: true })
    }
    window.addEventListener("keydown", this.handleKeydown)
    this.apply()
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
    window.removeEventListener("keydown", this.handleKeydown)
  }

  search() {
    this.apply()
  }

  // Destaque otimista: a fila é data-turbo-permanent, então o servidor não
  // re-renderiza o item ativo na troca de conversa. Sem preventDefault — a
  // navegação normal do link é quem troca o thread à direita.
  select(event) {
    const item = event.currentTarget
    this.conversationItems.forEach((conversationItem) => {
      conversationItem.classList.toggle("is-active", conversationItem === item)
    })
  }

  filter(event) {
    this.activeFilter = event.currentTarget.dataset.filter || "all"
    this.filterButtonTargets.forEach((button) => {
      button.classList.toggle("is-active", button.dataset.filter === this.activeFilter)
    })
    this.apply()
  }

  apply() {
    const term = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : ""
    const items = this.conversationItems
    let activeItem = null

    items.forEach((item) => {
      if (item.classList.contains("is-active")) activeItem = item
      const matchesTerm = !term || (item.dataset.search || "").includes(term)
      const matchesFilter = this.matchesFilter(item) || item.classList.contains("is-active")
      item.hidden = !(matchesTerm && matchesFilter)
    })

    this.keepActiveVisible(activeItem)
  }

  matchesFilter(item) {
    switch (this.activeFilter) {
      case "unread":
        return item.dataset.unread === "true"
      case "unlinked":
        return item.dataset.lead !== "true"
      default:
        return true
    }
  }

  get conversationItems() {
    if (!this.hasListTarget) return []

    return Array.from(this.listTarget.querySelectorAll(".wa-inbox-conversation"))
  }

  keepActiveVisible(activeItem) {
    if (!activeItem || !this.hasListTarget) return

    activeItem.hidden = false
  }

  handleKeydown(event) {
    if (!this.isFocusWorkspace) return
    if (this.isTypingContext(event.target)) return

    if (event.key === "/") {
      event.preventDefault()
      if (this.hasSearchTarget) this.searchTarget.focus()
      return
    }

    if (event.key === "Escape") {
      if (this.hasSearchTarget && this.searchTarget.value) {
        event.preventDefault()
        this.searchTarget.value = ""
        this.apply()
      }
      return
    }

    if (event.key === "j" || event.key === "ArrowDown") {
      event.preventDefault()
      this.navigateRelative(1)
      return
    }

    if (event.key === "k" || event.key === "ArrowUp") {
      event.preventDefault()
      this.navigateRelative(-1)
    }
  }

  navigateRelative(direction) {
    const items = this.visibleConversationItems
    if (!items.length) return

    const activeIndex = items.findIndex((item) => item.classList.contains("is-active"))
    const nextIndex = activeIndex === -1
      ? 0
      : Math.max(0, Math.min(items.length - 1, activeIndex + direction))

    const nextItem = items[nextIndex]
    if (!nextItem || nextIndex === activeIndex) return

    this.visitConversation(nextItem)
  }

  visitConversation(item) {
    const href = item.getAttribute("href")
    if (!href) return

    if (window.Turbo?.visit) {
      window.Turbo.visit(href, { frame: "wa-thread", action: "advance" })
    } else {
      window.location.href = href
    }
  }

  get visibleConversationItems() {
    return this.conversationItems.filter((item) => !item.hidden)
  }

  get isFocusWorkspace() {
    return Boolean(this.element.closest(".wa-inbox-page--focus")) ||
      document.body.classList.contains("ax-whatsapp-focus-workspace")
  }

  isTypingContext(target) {
    if (!(target instanceof Element)) return false

    return Boolean(
      target.closest("input, textarea, select, [contenteditable='true'], [contenteditable=''], trix-editor")
    )
  }
}
