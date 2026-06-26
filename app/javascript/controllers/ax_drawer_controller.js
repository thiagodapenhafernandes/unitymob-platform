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
    this.onKey = this.closeOnEsc.bind(this)
    this.applyCompactState()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
  }

  open(event) {
    if (event) event.preventDefault()
    if (this.hasBackdropTarget) this.backdropTarget.hidden = false
    this.element.classList.add("is-open")
    document.addEventListener("keydown", this.onKey)
  }

  close(event) {
    if (event) event.preventDefault()
    if (this.hasBackdropTarget) this.backdropTarget.hidden = true
    this.element.classList.remove("is-open")
    document.removeEventListener("keydown", this.onKey)
  }

  toggle(event) {
    if (event) event.preventDefault()
    this.element.classList.contains("is-open") ? this.close() : this.open()
  }

  // Mesmo botão "recolher" (--collapse): no desktop (sidebar fixa, >=1024px)
  // compacta a sidebar; no mobile/tablet (drawer) abre/fecha o menu. Assim o
  // hambúrguer do header fica dispensável no mobile, SEM mudar o desktop.
  toggleResponsive(event) {
    if (event) event.preventDefault()
    if (window.matchMedia("(min-width: 1024px)").matches) {
      this.toggleCompact()
    } else {
      this.element.classList.contains("is-open") ? this.close() : this.open()
    }
  }

  toggleCompact(event) {
    if (event) event.preventDefault()

    const compact = !this.element.classList.contains("is-compact")
    this.element.classList.toggle("is-compact", compact)
    document.documentElement.classList.toggle("ax-sidebar-compact-preload", compact)

    try {
      window.localStorage.setItem("ax-sidebar-compact", compact ? "1" : "0")
    } catch (_) {}
  }

  closeOnEsc(event) {
    if (event.key === "Escape") this.close()
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
}
