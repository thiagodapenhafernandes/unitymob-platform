import { Controller } from "@hotwired/stimulus"

const DEFAULT_STORAGE_KEY = "ax-aside-collapsed"
const DEFAULT_PRELOAD_CLASS = "ax-inspector-collapsed-preload"

export default class extends Controller {
  static targets = ["toggle", "panel", "rail"]
  static values = {
    storageKey: String,
    preloadClass: String,
    collapsedClass: { type: String, default: "is-inspector-collapsed" },
    pinWorkspace: { type: Boolean, default: false }
  }

  connect() {
    this.element.dataset.axAsideReady = "true"
    this.applyStoredState()
    this.assignRelationships()
    this.syncPreloadState()
    this.syncAccessibility()
    this.keepWorkspacePinned()
  }

  toggle(event) {
    if (event) event.preventDefault()

    const collapsed = !this.element.classList.contains(this.collapsedClassValue)
    this.setCollapsed(collapsed, { activeElement: event?.currentTarget || document.activeElement })
  }

  collapse() {
    this.setCollapsed(true)
  }

  expand() {
    this.setCollapsed(false)
  }

  setCollapsed(collapsed, options = {}) {
    const activeElement = options.activeElement || document.activeElement
    const shouldMoveFocus = this.focusWillBeHidden(activeElement, collapsed)
    this.element.classList.toggle(this.collapsedClassValue, collapsed)

    try {
      window.localStorage.setItem(this.storageKey, collapsed ? "1" : "0")
    } catch (_) {}

    this.syncPreloadState()
    this.syncAccessibility()
    if (shouldMoveFocus) this.visibleToggle(collapsed)?.focus()
  }

  applyStoredState() {
    let stored = null
    try { stored = window.localStorage.getItem(this.storageKey) } catch (_) {}

    // Sem preferência salva: no mobile começa recolhido (conteúdo primeiro, com o
    // filtro atrás do botão); no desktop segue expandido (inalterado). O default
    // mobile é só calculado por viewport, NÃO é persistido — não afeta o desktop.
    const collapsed = stored === "1" ||
      (stored === null && window.matchMedia("(max-width: 767.98px)").matches)

    this.element.classList.toggle(this.collapsedClassValue, collapsed)
  }

  get storageKey() {
    return this.hasStorageKeyValue ? this.storageKeyValue : DEFAULT_STORAGE_KEY
  }

  get preloadClass() {
    return this.hasPreloadClassValue ? this.preloadClassValue : DEFAULT_PRELOAD_CLASS
  }

  syncPreloadState() {
    document.documentElement.classList.toggle(
      this.preloadClass,
      this.element.classList.contains(this.collapsedClassValue)
    )
  }

  syncAccessibility() {
    const expanded = !this.element.classList.contains(this.collapsedClassValue)
    this.toggleTargets.forEach((button) => {
      button.setAttribute("aria-expanded", expanded ? "true" : "false")
    })

    if (this.hasPanelTarget) {
      this.panelTarget.toggleAttribute("inert", !expanded)
      this.panelTarget.setAttribute("aria-hidden", expanded ? "false" : "true")
    }
    if (this.hasRailTarget) {
      this.railTarget.toggleAttribute("inert", expanded)
      this.railTarget.setAttribute("aria-hidden", expanded ? "true" : "false")
    }
  }

  assignRelationships() {
    if (!this.hasPanelTarget) return

    if (!this.panelTarget.id) this.panelTarget.id = `ax-aside-panel-${this.uniqueId()}`
    this.toggleTargets.forEach((button) => button.setAttribute("aria-controls", this.panelTarget.id))
  }

  focusWillBeHidden(activeElement, collapsed) {
    if (!activeElement) return false
    if (collapsed && this.hasPanelTarget) return this.panelTarget.contains(activeElement)
    if (!collapsed && this.hasRailTarget) return this.railTarget === activeElement || this.railTarget.contains(activeElement)

    return false
  }

  visibleToggle(collapsed) {
    if (collapsed && this.hasRailTarget) {
      return this.toggleTargets.find((button) => this.railTarget === button || this.railTarget.contains(button))
    }
    if (!collapsed && this.hasPanelTarget) {
      return this.toggleTargets.find((button) => this.panelTarget === button || this.panelTarget.contains(button))
    }

    return this.toggleTargets.find((button) => !button.closest("[inert]"))
  }

  uniqueId() {
    return Math.random().toString(36).slice(2, 10)
  }

  keepWorkspacePinned() {
    if (!this.pinWorkspaceValue) return
    if (!document.body.classList.contains("ax-habitations-workspace")) return

    const pin = () => {
      document.documentElement.scrollTop = 0
      document.body.scrollTop = 0
      window.scrollTo(0, 0)
    }

    pin()
    window.requestAnimationFrame(pin)
    window.setTimeout(pin, 180)
  }
}
