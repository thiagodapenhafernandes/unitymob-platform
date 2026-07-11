import { Controller } from "@hotwired/stimulus"

const TOKEN_TO_VAR = {
  surface: "--theme-surface",
  header: "--theme-header",
  workspace: "--theme-workspace",
  sidebar: "--theme-sidebar",
  primary: "--theme-primary",
  ink: "--theme-ink"
}

const TOKEN_TO_ADMIN_VAR = {
  surface: "--admin-surface",
  header: "--admin-surface-header",
  workspace: "--admin-workspace-bg",
  sidebar: "--admin-sidebar-bg",
  primary: "--admin-primary",
  ink: "--admin-ink"
}

const DERIVED_ADMIN_VARS = {
  surface: [
    "--ab-panel",
    "--ab-control-bg",
    "--ax-panel-bg",
    "--ax-control-bg"
  ],
  header: [
    "--ab-panel-header",
    "--ax-panel-header"
  ],
  workspace: [
    "--ab-page",
    "--ax-page-bg"
  ],
  primary: [
    "--admin-primary-hover",
    "--admin-primary-soft",
    "--admin-primary-softer",
    "--admin-primary-ring",
    "--ab-field-hover",
    "--ab-field-focus",
    "--ax-field-hover",
    "--ax-field-focus"
  ],
  ink: [
    "--ab-ink",
    "--ab-muted",
    "--ab-line",
    "--ab-line-soft",
    "--ax-border",
    "--ax-border-soft"
  ]
}

export default class extends Controller {
  connect() {
    this.element.querySelectorAll("[data-theme-token]").forEach((input) => {
      this.applyToken(input.dataset.themeToken, input.value, { syncInputs: false })
    })
  }

  update(event) {
    const token = event.currentTarget.dataset.themeToken
    this.applyToken(token, event.currentTarget.value, { source: event.currentTarget })
  }

  updateMenuSection(event) {
    const input = event.currentTarget
    const section = String(input.dataset.menuSectionKey || "").replaceAll("_", "-")
    const property = input.dataset.menuStyleProperty
    const value = property === "background-opacity"
      ? this.normalizedOpacity(input.value)
      : property === "shadow"
        ? this.normalizedBoxShadow(input.value)
        : this.normalizedHex(input.value)

    if (!section || !property || value === null) return

    document.documentElement.style.setProperty(`--admin-nav-${section}-${property}`, value)
  }

  resetDefaults() {
    const tokens = new Set()

    this.element.querySelectorAll("[data-theme-token][data-default-value]").forEach((input) => {
      const token = input.dataset.themeToken
      const value = this.normalizedHex(input.dataset.defaultValue)
      if (!token || !value) return

      input.value = value
      tokens.add(token)
    })

    tokens.forEach((token) => {
      const input = this.element.querySelector(`[data-theme-token="${token}"][data-default-value]`)
      this.applyToken(token, input.dataset.defaultValue)
    })
  }

  applyToken(token, rawValue, options = {}) {
    const value = this.normalizedHex(rawValue)
    if (!token || !value) return

    this.element.style.setProperty(TOKEN_TO_VAR[token], value)
    document.documentElement.style.setProperty(TOKEN_TO_ADMIN_VAR[token], value)
    this.applyDerivedAdminVars(token)

    if (options.syncInputs !== false) {
      this.syncInputs(token, value, options.source)
    }

    this.element.querySelectorAll(`[data-theme-token-label="${token}"]`).forEach((label) => {
      label.textContent = value.toUpperCase()
    })
  }

  applyDerivedAdminVars(token) {
    const derivedVars = DERIVED_ADMIN_VARS[token] || []

    derivedVars.forEach((name) => {
      document.documentElement.style.removeProperty(name)
    })
  }

  syncInputs(token, value, source) {
    this.element.querySelectorAll(`[data-theme-token="${token}"]`).forEach((input) => {
      if (input === source) return
      input.value = value
    })
  }

  normalizedHex(value) {
    const candidate = String(value || "").trim()
    if (/^#[0-9a-fA-F]{6}$/.test(candidate)) return candidate
    return null
  }

  normalizedOpacity(value) {
    const candidate = Number.parseInt(value, 10)
    if (Number.isNaN(candidate)) return null

    return `${Math.min(100, Math.max(0, candidate))}%`
  }

  normalizedBoxShadow(value) {
    const candidate = String(value || "").trim().replace(/\s+/g, " ")
    const pattern = /^(?:inset\s+)?(?:0|-?\d+(?:\.\d+)?px)\s+(?:0|-?\d+(?:\.\d+)?px)(?:\s+(?:0|\d+(?:\.\d+)?px)){0,2}\s+#[0-9a-fA-F]{6}$/

    return pattern.test(candidate) ? candidate : null
  }
}
