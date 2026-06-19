import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab"]
  static values = {
    panelSelector: String
  }

  connect() {
    this.activateFromHashBound = this.activateFromHash.bind(this)
    window.addEventListener("hashchange", this.activateFromHashBound)
    document.addEventListener("DOMContentLoaded", this.activateFromHashBound)
    window.addEventListener("load", this.activateFromHashBound)

    this.activateFromHash()
    requestAnimationFrame(() => this.activateFromHash())
  }

  disconnect() {
    window.removeEventListener("hashchange", this.activateFromHashBound)
    document.removeEventListener("DOMContentLoaded", this.activateFromHashBound)
    window.removeEventListener("load", this.activateFromHashBound)
  }

  select(event) {
    event.preventDefault()
    this.show(event.currentTarget)
  }

  show(trigger) {
    const targetSelector = this.targetSelectorFor(trigger)
    if (!targetSelector) return false

    const panel = document.querySelector(targetSelector)
    const content = this.contentFor(panel)
    if (!panel || !content) return false

    this.tabTargets.forEach((tab) => {
      const active = tab === trigger
      tab.classList.toggle("active", active)
      tab.setAttribute("aria-selected", active ? "true" : "false")
    })

    content.querySelectorAll(":scope > .tab-pane").forEach((tabPane) => {
      const active = tabPane === panel
      tabPane.classList.toggle("active", active)
      tabPane.classList.toggle("show", active)
    })

    this.syncPeerTriggers(targetSelector, content)
    this.syncHash(targetSelector)

    panel.dispatchEvent(new CustomEvent("ax:tab-shown", {
      bubbles: true,
      detail: { trigger, target: panel }
    }))

    trigger.dispatchEvent(new CustomEvent("ax:tab-shown", {
      bubbles: true,
      detail: { trigger, target: panel }
    }))

    return true
  }

  syncHash(targetSelector) {
    if (!targetSelector?.startsWith("#")) return
    if (window.location.hash === targetSelector) return

    history.replaceState(null, "", `${window.location.pathname}${window.location.search}${targetSelector}`)
  }

  activateFromHash() {
    const tabId = window.location.hash?.replace("#", "")
    if (!tabId) return

    const trigger = this.tabTargets.find((tab) => this.targetSelectorFor(tab) === `#${this.escapeSelector(tabId)}`)
    if (trigger) requestAnimationFrame(() => this.show(trigger))
  }

  syncPeerTriggers(targetSelector, content) {
    const panelSelectors = Array.from(content.querySelectorAll(":scope > .tab-pane[id]")).map((tabPane) => `#${this.escapeSelector(tabPane.id)}`)

    document.querySelectorAll("[data-ax-tabs-target-param], [data-bs-target]").forEach((tab) => {
      const selector = this.targetSelectorFor(tab)
      if (!panelSelectors.includes(selector)) return

      const active = selector === targetSelector
      tab.classList.toggle("active", active)
      tab.setAttribute("aria-selected", active ? "true" : "false")
    })
  }

  targetSelectorFor(trigger) {
    return trigger?.dataset?.axTabsTargetParam || trigger?.dataset?.bsTarget || null
  }

  contentFor(panel) {
    if (this.hasPanelSelectorValue) return document.querySelector(this.panelSelectorValue)
    return panel?.closest(".tab-content")
  }

  escapeSelector(value) {
    if (window.CSS?.escape) return CSS.escape(value)
    return value.replace(/([ #;?%&,.+*~':"!^$[\]()=>|/@])/g, "\\$1")
  }
}
