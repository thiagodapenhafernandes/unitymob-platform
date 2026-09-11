import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "items"]

  connect() {
    this.transitionTimers = new WeakMap()
    this.previewTimers = new WeakMap()
    this.previewCompactSection = this.previewCompactSection.bind(this)
    this.closeCompactPreview = this.closeCompactPreview.bind(this)
    this.sections = Array.from(this.element.querySelectorAll("[data-nav-section]"))
    this.sections.forEach((section) => {
      section.addEventListener("mouseenter", this.previewCompactSection)
      section.addEventListener("mouseleave", this.closeCompactPreview)
      section.addEventListener("focusin", this.previewCompactSection)
      section.addEventListener("focusout", this.closeCompactPreview)

      const shouldOpen = this.containsActiveLink(section)
      this.setSection(section, shouldOpen, false)
    })
  }

  disconnect() {
    this.sections?.forEach((section) => {
      section.removeEventListener("mouseenter", this.previewCompactSection)
      section.removeEventListener("mouseleave", this.closeCompactPreview)
      section.removeEventListener("focusin", this.previewCompactSection)
      section.removeEventListener("focusout", this.closeCompactPreview)

      const previewTimer = this.previewTimers.get(section)
      if (previewTimer) window.clearTimeout(previewTimer)

      const items = this.sectionItems(section)
      const timer = items && this.transitionTimers.get(items)
      if (timer) window.clearTimeout(timer)
    })
  }

  toggle(event) {
    const section = event.currentTarget.closest("[data-nav-section]")

    if (this.compactMode()) {
      this.setSection(section, true, false)
      return
    }

    const trigger = event.currentTarget
    const shouldOpen = trigger.getAttribute("aria-expanded") !== "true"

    if (shouldOpen) {
      this.sections.forEach((candidate) => {
        if (candidate !== section) this.setSection(candidate, false, true)
      })
    }

    this.setSection(section, shouldOpen, true)
  }

  setSection(section, open, animate) {
    const trigger = section.querySelector(":scope > [data-menu-sections-target='trigger']")
    const items = this.sectionItems(section)
    if (!trigger || !items) return

    const previousTimer = this.transitionTimers.get(items)
    if (previousTimer) window.clearTimeout(previousTimer)

    trigger.setAttribute("aria-expanded", String(open))
    section.classList.toggle("is-open", open)

    if (!animate || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      items.hidden = !open
      items.style.maxHeight = open ? "none" : "0px"
      items.classList.toggle("is-visible", open)
      return
    }

    if (open) {
      items.hidden = false
      items.style.maxHeight = "0px"
      requestAnimationFrame(() => {
        items.classList.add("is-visible")
        items.style.maxHeight = `${items.scrollHeight}px`
      })

      const timer = window.setTimeout(() => {
        items.style.maxHeight = "none"
        this.transitionTimers.delete(items)
      }, 170)
      this.transitionTimers.set(items, timer)
      return
    }

    items.style.maxHeight = `${items.scrollHeight}px`
    requestAnimationFrame(() => {
      items.classList.remove("is-visible")
      items.style.maxHeight = "0px"
    })

    const timer = window.setTimeout(() => {
      items.hidden = true
      this.transitionTimers.delete(items)
    }, 170)
    this.transitionTimers.set(items, timer)
  }

  previewCompactSection(event) {
    if (!this.compactMode()) return

    const section = event.currentTarget
    const previewTimer = this.previewTimers.get(section)
    if (previewTimer) window.clearTimeout(previewTimer)

    this.sections.forEach((candidate) => {
      if (candidate !== section) this.hideCompactPreview(candidate)
    })
    this.setSection(section, true, false)
    section.classList.add("is-previewing")
    this.positionCompactPreview(section)
  }

  closeCompactPreview(event) {
    if (!this.compactMode()) return

    const section = event.currentTarget
    const previousTimer = this.previewTimers.get(section)
    if (previousTimer) window.clearTimeout(previousTimer)

    const timer = window.setTimeout(() => {
      if (section.matches(":hover")) return
      if (event.type === "focusout" && section.contains(document.activeElement)) return
      this.hideCompactPreview(section)
      this.previewTimers.delete(section)
    }, 180)
    this.previewTimers.set(section, timer)
  }

  hideCompactPreview(section) {
    section.classList.remove("is-previewing")
    if (!this.containsActiveLink(section)) this.setSection(section, false, false)
  }

  positionCompactPreview(section) {
    const items = this.sectionItems(section)
    if (!items?.getBoundingClientRect || !section.getBoundingClientRect) return

    const sectionTop = section.getBoundingClientRect().top
    const panelHeight = Math.min(items.scrollHeight + 18, window.innerHeight * 0.7)
    const overflow = sectionTop + panelHeight + 16 - window.innerHeight
    items.style.setProperty("--ax-compact-preview-top", `${Math.min(0, -overflow)}px`)
  }

  compactMode() {
    return document.body.classList.contains("is-compact")
  }

  sectionItems(section) {
    return section.querySelector(":scope > [data-menu-sections-target='items']")
  }

  containsActiveLink(section) {
    return Boolean(section.querySelector(".ax-nav__section-items .ax-nav__link.active"))
  }
}
