import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab"]
  static values = {
    panelSelector: String
  }

  connect() {
    this.activateFromHashBound = this.activateFromHash.bind(this)
    this.handleKeydownBound = this.handleKeydown.bind(this)
    window.addEventListener("hashchange", this.activateFromHashBound)
    document.addEventListener("DOMContentLoaded", this.activateFromHashBound)
    window.addEventListener("load", this.activateFromHashBound)
    this.element.addEventListener("keydown", this.handleKeydownBound)
    this.element.setAttribute("role", "tablist")

    this.initializeState()
    this.activateFromHash()
    requestAnimationFrame(() => {
      this.initializeState()
      this.activateFromHash()
    })
  }

  disconnect() {
    window.removeEventListener("hashchange", this.activateFromHashBound)
    document.removeEventListener("DOMContentLoaded", this.activateFromHashBound)
    window.removeEventListener("load", this.activateFromHashBound)
    this.element.removeEventListener("keydown", this.handleKeydownBound)
  }

  select(event) {
    event.preventDefault()
    if (this.tabDisabled(event.currentTarget)) return

    this.show(event.currentTarget)
  }

  show(trigger) {
    if (this.tabDisabled(trigger)) return false

    const targetSelector = this.targetSelectorFor(trigger)
    if (!targetSelector) return false

    const panel = document.querySelector(targetSelector)
    const content = this.contentFor(panel)
    if (!panel || !content) return false

    this.applyState(trigger, panel, content)

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

  initializeState() {
    const trigger = this.tabTargets.find((tab) => tab.classList.contains("active") || tab.getAttribute("aria-selected") === "true") || this.tabTargets[0]
    const targetSelector = this.targetSelectorFor(trigger)
    const panel = targetSelector ? document.querySelector(targetSelector) : null
    const content = this.contentFor(panel)
    if (!trigger || !panel || !content) return

    this.applyState(trigger, panel, content)
  }

  applyState(trigger, panel, content) {
    this.tabTargets.forEach((tab) => {
      const active = tab === trigger
      const selector = this.targetSelectorFor(tab)
      tab.setAttribute("role", "tab")
      tab.classList.toggle("active", active)
      tab.setAttribute("aria-selected", active ? "true" : "false")
      tab.setAttribute("tabindex", active ? "0" : "-1")
      if (selector?.startsWith("#")) {
        const panelId = selector.slice(1)
        tab.setAttribute("aria-controls", panelId)
        if (!tab.id) tab.id = `${panelId}-tab`
      }
    })

    this.panelsFor(content).forEach((tabPane) => {
      const active = tabPane === panel
      const owningTab = this.tabTargets.find((tab) => this.targetSelectorFor(tab) === `#${tabPane.id}`)
      tabPane.setAttribute("role", "tabpanel")
      if (owningTab?.id) tabPane.setAttribute("aria-labelledby", owningTab.id)
      tabPane.classList.toggle("active", active)
      tabPane.classList.toggle("show", active)
      tabPane.hidden = !active
      tabPane.setAttribute("aria-hidden", active ? "false" : "true")
      if (active && !tabPane.hasAttribute("tabindex")) tabPane.setAttribute("tabindex", "0")
    })
  }

  handleKeydown(event) {
    const availableTabs = this.tabTargets.filter((tab) => !this.tabDisabled(tab))
    const currentTab = event.target.closest("[data-ax-tabs-target~='tab']")
    const currentIndex = availableTabs.indexOf(currentTab)
    if (currentIndex < 0) return

    const vertical = this.element.getAttribute("aria-orientation") === "vertical"
    const previousKeys = vertical ? ["ArrowUp"] : ["ArrowLeft"]
    const nextKeys = vertical ? ["ArrowDown"] : ["ArrowRight"]
    let nextIndex

    if (previousKeys.includes(event.key)) nextIndex = (currentIndex - 1 + availableTabs.length) % availableTabs.length
    if (nextKeys.includes(event.key)) nextIndex = (currentIndex + 1) % availableTabs.length
    if (event.key === "Home") nextIndex = 0
    if (event.key === "End") nextIndex = availableTabs.length - 1
    if (nextIndex === undefined) return

    event.preventDefault()
    const nextTab = availableTabs[nextIndex]
    nextTab.focus()
    nextTab.scrollIntoView({ block: "nearest", inline: "nearest" })
    this.show(nextTab)
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
    const panelSelectors = this.panelsFor(content).map((tabPane) => `#${this.escapeSelector(tabPane.id)}`)

    document.querySelectorAll("[data-ax-tabs-target-param], [data-bs-target]").forEach((tab) => {
      const selector = this.targetSelectorFor(tab)
      if (!panelSelectors.includes(selector)) return

      const active = selector === targetSelector
      tab.classList.toggle("active", active)
      tab.setAttribute("aria-selected", active ? "true" : "false")
      tab.setAttribute("tabindex", active ? "0" : "-1")
    })
  }

  targetSelectorFor(trigger) {
    return trigger?.dataset?.axTabsTargetParam || trigger?.dataset?.bsTarget || null
  }

  contentFor(panel) {
    if (this.hasPanelSelectorValue) return document.querySelector(this.panelSelectorValue)
    return panel?.closest(".tab-content")
  }

  panelsFor(content) {
    if (!content) return []

    return this.tabTargets
      .map((tab) => this.targetSelectorFor(tab))
      .filter((selector) => selector?.startsWith("#"))
      .map((selector) => document.querySelector(selector))
      .filter((panel, index, panels) => panel && content.contains(panel) && panels.indexOf(panel) === index)
  }

  tabDisabled(tab) {
    return Boolean(tab?.disabled || tab?.getAttribute("aria-disabled") === "true")
  }

  escapeSelector(value) {
    if (window.CSS?.escape) return CSS.escape(value)
    return value.replace(/([ #;?%&,.+*~':"!^$[\]()=>|/@])/g, "\\$1")
  }
}
