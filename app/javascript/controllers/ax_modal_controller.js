import { Controller } from "@hotwired/stimulus"

// Modal genérico do novo CRM (substitui bootstrap.Modal).
// Uso:
//   <div data-controller="ax-modal">
//     <button data-action="ax-modal#open">Abrir</button>
//     <div data-ax-modal-target="overlay" class="ax-modal-overlay" hidden
//          data-action="click->ax-modal#backdropClose">
//       <div class="ax-modal-panel" role="dialog" aria-modal="true">
//         <button data-action="ax-modal#close">×</button> …
//       </div>
//     </div>
//   </div>
// Abrir de fora: dispare o evento ou use um trigger com data-action.
export default class extends Controller {
  static targets = ["overlay"]
  static values = { open: { type: Boolean, default: false } }

  connect() {
    this.onKey = this.handleKeydown.bind(this)
    this.onDocumentClick = this.openFromTrigger.bind(this)
    this.onRequestedOpen = this.open.bind(this)
    this.onRequestedClose = this.close.bind(this)
    document.addEventListener("click", this.onDocumentClick)
    this.element.addEventListener("ax-modal:open", this.onRequestedOpen)
    this.element.addEventListener("ax-modal:close", this.onRequestedClose)
    if (this.openValue) this.open()
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
    this.element.removeEventListener("ax-modal:open", this.onRequestedOpen)
    this.element.removeEventListener("ax-modal:close", this.onRequestedClose)
    document.removeEventListener("keydown", this.onKey)
    this.unlockScroll()
  }

  open(event) {
    if (event) event.preventDefault()
    const wasClosed = this.overlayTarget.hidden
    if (wasClosed) {
      this.previouslyFocusedElement = event?.type === "ax-modal:open" ? document.activeElement : (event?.currentTarget || document.activeElement)
    }
    this.overlayTarget.hidden = false
    this.overlayTarget.setAttribute("aria-hidden", "false")
    if (!this.overlayTarget.hasAttribute("tabindex")) this.overlayTarget.setAttribute("tabindex", "-1")
    this.lockScroll()
    document.addEventListener("keydown", this.onKey)
    const focusable = this.focusableElements()[0]
    if (focusable) focusable.focus()
    else this.overlayTarget.focus()
    this.dispatchModalEvent("opened")
  }

  close(event) {
    if (event) event.preventDefault()
    if (this.overlayTarget.hidden) return
    this.overlayTarget.hidden = true
    this.overlayTarget.setAttribute("aria-hidden", "true")
    this.unlockScroll()
    document.removeEventListener("keydown", this.onKey)
    this.dispatchModalEvent("closed")
    if (this.previouslyFocusedElement?.isConnected) this.previouslyFocusedElement.focus()
    this.previouslyFocusedElement = null
  }

  backdropClose(event) {
    if (event.target === this.overlayTarget) this.close()
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }

    if (event.key !== "Tab") return

    const focusable = this.focusableElements()
    if (focusable.length === 0) {
      event.preventDefault()
      this.overlayTarget.focus()
      return
    }

    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  openFromTrigger(event) {
    const trigger = event.target.closest("[data-ax-modal-open]")
    if (!trigger || !this.matchesTrigger(trigger.dataset.axModalOpen)) return

    event.preventDefault()
    this.open({ currentTarget: trigger, preventDefault() {} })
  }

  lockScroll() {
    if (this.scrollLocked) return

    const root = document.documentElement
    const lockCount = Number.parseInt(root.dataset.axModalLockCount || "0", 10)
    if (lockCount === 0) root.dataset.axModalPreviousOverflow = root.style.overflow || ""
    root.dataset.axModalLockCount = String(lockCount + 1)
    root.style.overflow = "hidden"
    this.scrollLocked = true
  }

  unlockScroll() {
    if (!this.scrollLocked) return

    const root = document.documentElement
    const lockCount = Math.max(Number.parseInt(root.dataset.axModalLockCount || "1", 10) - 1, 0)
    if (lockCount === 0) {
      root.style.overflow = root.dataset.axModalPreviousOverflow || ""
      delete root.dataset.axModalLockCount
      delete root.dataset.axModalPreviousOverflow
    } else {
      root.dataset.axModalLockCount = String(lockCount)
    }
    this.scrollLocked = false
  }

  focusableElements() {
    const selector = [
      "[autofocus]",
      "a[href]",
      "button:not([disabled])",
      "input:not([disabled]):not([type='hidden'])",
      "select:not([disabled])",
      "textarea:not([disabled])",
      "[tabindex]:not([tabindex='-1'])"
    ].join(",")

    return Array.from(this.overlayTarget.querySelectorAll(selector)).filter((element) => {
      return !element.hidden && !element.closest("[hidden]") && element.getAttribute("aria-hidden") !== "true"
    })
  }

  matchesTrigger(target) {
    if (!target) return false

    return target === `#${this.element.id}` || target === this.element.id
  }

  dispatchModalEvent(name) {
    this.element.dispatchEvent(new CustomEvent(`ax-modal:${name}`, { bubbles: true }))
  }
}
