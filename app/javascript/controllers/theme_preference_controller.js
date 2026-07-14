import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async submit(event) {
    event.preventDefault()

    const button = this.element.querySelector('[role="switch"]')
    button?.setAttribute("aria-busy", "true")
    if (button) button.disabled = true

    try {
      const response = await fetch(this.element.action, {
        method: (this.element.method || "post").toUpperCase(),
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        credentials: "same-origin",
        body: new FormData(this.element)
      })

      if (!response.ok) throw new Error("theme_preference_update_failed")

      this.apply(await response.json())
    } catch (_error) {
      this.element.submit()
    } finally {
      button?.removeAttribute("aria-busy")
      if (button) button.disabled = false
    }
  }

  apply(payload) {
    const mode = payload.mode === "dark" ? "dark" : "light"
    const dark = mode === "dark"
    const root = document.documentElement

    if (root.hasAttribute("data-admin-theme")) root.dataset.adminTheme = mode
    if (root.hasAttribute("data-field-theme")) root.dataset.fieldTheme = mode
    root.style.colorScheme = mode

    Object.entries(payload.tokens || {}).forEach(([name, value]) => {
      root.style.setProperty(`--${name.replaceAll("_", "-")}`, value)
    })

    document.querySelectorAll('meta[name="theme-color"]').forEach((meta) => {
      meta.setAttribute("content", payload.theme_color)
    })

    const button = this.element.querySelector('[role="switch"]')
    button?.setAttribute("aria-checked", dark.toString())
    button?.setAttribute("title", dark ? "Usar tema claro" : "Usar tema escuro")

    const visualSwitch = button?.querySelector(".ax-menu__theme-switch")
    visualSwitch?.classList.toggle("is-checked", dark)

    const icon = button?.querySelector("i")
    if (icon && button.classList.contains("field-theme-toggle")) {
      icon.classList.toggle("bi-sun", dark)
      icon.classList.toggle("bi-moon-stars", !dark)
    }

    const modeInput = this.element.querySelector('input[name="admin_user[admin_theme_mode]"]')
    if (modeInput) modeInput.value = dark ? "light" : "dark"

    document.dispatchEvent(new CustomEvent("theme-preference:changed", { detail: payload }))
  }
}
