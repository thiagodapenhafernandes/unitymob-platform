import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "items"]

  connect() {
    this.transitionTimers = new WeakMap()
    this.sections = Array.from(this.element.querySelectorAll("[data-nav-section]"))
    this.sections.forEach((section) => {
      const shouldOpen = section.dataset.navSection === "product" || this.containsActiveLink(section)
      this.setSection(section, shouldOpen, false)
    })
  }

  disconnect() {
    this.sections?.forEach((section) => {
      const items = this.sectionItems(section)
      const timer = items && this.transitionTimers.get(items)
      if (timer) window.clearTimeout(timer)
    })
  }

  toggle(event) {
    const section = event.currentTarget.closest("[data-nav-section]")
    const trigger = event.currentTarget
    this.setSection(section, trigger.getAttribute("aria-expanded") !== "true", true)
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

  sectionItems(section) {
    return section.querySelector(":scope > [data-menu-sections-target='items']")
  }

  containsActiveLink(section) {
    return Boolean(section.querySelector(".ax-nav__section-items .ax-nav__link.active"))
  }
}
