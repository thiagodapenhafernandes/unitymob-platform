import { Controller } from "@hotwired/stimulus"

// Drawer / offcanvas (substitui bootstrap.Offcanvas) — usado p/ a sidebar no mobile.
// Uso:
//   <div data-controller="ax-drawer">
//     <button data-action="ax-drawer#open">menu</button>
//     <div data-ax-drawer-target="backdrop" class="ax-drawer-backdrop" hidden
//          data-action="click->ax-drawer#close"></div>
//     <aside data-ax-drawer-target="panel" class="ax-drawer-panel">…</aside>
//   </div>
export default class extends Controller {
  static targets = ["panel", "backdrop"]

  connect() {
    this.onKey = this.handleKeydown.bind(this)
    this.onViewportChange = this.handleViewportChange.bind(this)
    this.drawerMedia = window.matchMedia("(max-width: 1023.98px)")
    this.drawerMedia.addEventListener("change", this.onViewportChange)
    this.assignRelationships()
    this.applyCompactState()
    this.syncAccessibility()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    this.drawerMedia?.removeEventListener("change", this.onViewportChange)
    this.unlockScroll()
  }

  open(event) {
    if (event) event.preventDefault()
    if (this.isOpen) return

    this.previouslyFocusedElement = event?.currentTarget || document.activeElement
    if (this.hasBackdropTarget) this.backdropTarget.hidden = false
    this.element.classList.add("is-open")
    this.lockScroll()
    this.syncAccessibility()
    document.addEventListener("keydown", this.onKey)
    const focusable = this.focusableElements[0]
    if (focusable) focusable.focus()
    else this.panelTarget.focus()
  }

  close(event, options = {}) {
    if (event) event.preventDefault()
    if (!this.isOpen) return

    if (this.hasBackdropTarget) this.backdropTarget.hidden = true
    this.element.classList.remove("is-open")
    this.unlockScroll()
    this.syncAccessibility()
    document.removeEventListener("keydown", this.onKey)
    if (options.restoreFocus !== false && this.previouslyFocusedElement?.isConnected) this.previouslyFocusedElement.focus()
    this.previouslyFocusedElement = null
  }

  toggle(event) {
    if (event) event.preventDefault()
    this.isOpen ? this.close() : this.open(event)
  }

  // Mesmo botão "recolher" (--collapse): no desktop (sidebar fixa, >=1024px)
  // compacta a sidebar; no mobile/tablet (drawer) abre/fecha o menu. Assim o
  // hambúrguer do header fica dispensável no mobile, SEM mudar o desktop.
  toggleResponsive(event) {
    if (event) event.preventDefault()
    if (window.matchMedia("(min-width: 1024px)").matches) {
      this.toggleCompact()
    } else {
      this.isOpen ? this.close() : this.open(event)
    }
  }

  toggleCompact(event) {
    if (event) event.preventDefault()

    const compact = !this.element.classList.contains("is-compact")
    this.element.classList.toggle("is-compact", compact)
    document.documentElement.classList.toggle("ax-sidebar-compact-preload", compact)
    this.syncAccessibility()

    try {
      window.localStorage.setItem("ax-sidebar-compact", compact ? "1" : "0")
    } catch (_) {}
  }

  handleKeydown(event) {
    if (!this.isOpen || !this.isDrawerViewport) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }

    if (event.key !== "Tab") return

    const focusable = this.focusableElements
    if (focusable.length === 0) {
      event.preventDefault()
      this.panelTarget.focus()
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

  applyCompactState() {
    try {
      if (window.localStorage.getItem("ax-sidebar-compact") === "1") {
        this.element.classList.add("is-compact")
        document.documentElement.classList.add("ax-sidebar-compact-preload")
      } else {
        document.documentElement.classList.remove("ax-sidebar-compact-preload")
      }
    } catch (_) {}
  }

  assignRelationships() {
    if (!this.panelTarget.id) this.panelTarget.id = "admin-navigation-drawer"
    if (!this.panelTarget.hasAttribute("tabindex")) this.panelTarget.setAttribute("tabindex", "-1")
    if (!this.panelTarget.hasAttribute("aria-label")) this.panelTarget.setAttribute("aria-label", "Navegação principal")
    if (this.hasBackdropTarget) this.backdropTarget.setAttribute("aria-hidden", "true")

    this.drawerTriggers.forEach((trigger) => trigger.setAttribute("aria-controls", this.panelTarget.id))
  }

  syncAccessibility() {
    if (this.isDrawerViewport) {
      this.panelTarget.toggleAttribute("inert", !this.isOpen)
      this.panelTarget.setAttribute("aria-hidden", this.isOpen ? "false" : "true")
    } else {
      this.panelTarget.removeAttribute("inert")
      this.panelTarget.removeAttribute("aria-hidden")
    }

    this.drawerTriggers.forEach((trigger) => {
      const controlsCompactState = trigger.dataset.action?.includes("toggleResponsive") && !this.isDrawerViewport
      const expanded = controlsCompactState ? !this.element.classList.contains("is-compact") : this.isOpen
      trigger.setAttribute("aria-expanded", expanded ? "true" : "false")
    })
  }

  handleViewportChange() {
    if (!this.isDrawerViewport && this.isOpen) this.close(null, { restoreFocus: false })
    this.syncAccessibility()
  }

  lockScroll() {
    if (!this.isDrawerViewport || this.scrollLocked) return

    this.previousOverflow = document.documentElement.style.overflow
    document.documentElement.style.overflow = "hidden"
    this.scrollLocked = true
  }

  unlockScroll() {
    if (!this.scrollLocked) return

    document.documentElement.style.overflow = this.previousOverflow || ""
    this.previousOverflow = null
    this.scrollLocked = false
  }

  get drawerTriggers() {
    return Array.from(this.element.querySelectorAll('[data-action~="ax-drawer#toggle"], [data-action~="ax-drawer#toggleResponsive"]'))
  }

  get focusableElements() {
    const selector = 'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
    return Array.from(this.panelTarget.querySelectorAll(selector)).filter((element) => !element.hidden && !element.closest("[hidden]"))
  }

  get isOpen() {
    return this.element.classList.contains("is-open")
  }

  get isDrawerViewport() {
    return this.drawerMedia?.matches === true
  }
}
