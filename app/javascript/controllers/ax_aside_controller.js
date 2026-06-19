import { Controller } from "@hotwired/stimulus"

const DEFAULT_STORAGE_KEY = "ax-aside-collapsed"
const DEFAULT_PRELOAD_CLASS = "ax-inspector-collapsed-preload"

export default class extends Controller {
  static targets = ["toggle"]
  static values = {
    storageKey: String,
    preloadClass: String,
    collapsedClass: { type: String, default: "is-inspector-collapsed" },
    pinWorkspace: { type: Boolean, default: false }
  }

  connect() {
    this.element.dataset.axAsideReady = "true"
    this.applyStoredState()
    this.syncPreloadState()
    this.syncToggleState()
    this.keepWorkspacePinned()
  }

  toggle(event) {
    if (event) event.preventDefault()

    const collapsed = !this.element.classList.contains(this.collapsedClassValue)
    this.element.classList.toggle(this.collapsedClassValue, collapsed)

    try {
      window.localStorage.setItem(this.storageKey, collapsed ? "1" : "0")
    } catch (_) {}

    this.syncPreloadState()
    this.syncToggleState()
  }

  applyStoredState() {
    try {
      this.element.classList.toggle(
        this.collapsedClassValue,
        window.localStorage.getItem(this.storageKey) === "1"
      )
    } catch (_) {}
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

  syncToggleState() {
    const expanded = !this.element.classList.contains(this.collapsedClassValue)
    this.toggleTargets.forEach((button) => {
      button.setAttribute("aria-expanded", expanded ? "true" : "false")
    })
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
