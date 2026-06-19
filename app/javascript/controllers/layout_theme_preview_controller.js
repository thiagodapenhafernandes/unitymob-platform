import { Controller } from "@hotwired/stimulus"

const TOKEN_TO_VAR = {
  surface: "--theme-surface",
  header: "--theme-header",
  primary: "--theme-primary",
  ink: "--theme-ink"
}

const TOKEN_TO_ADMIN_VAR = {
  surface: "--admin-surface",
  header: "--admin-surface-header",
  primary: "--admin-primary",
  ink: "--admin-ink"
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

    if (options.syncInputs !== false) {
      this.syncInputs(token, value, options.source)
    }

    this.element.querySelectorAll(`[data-theme-token-label="${token}"]`).forEach((label) => {
      label.textContent = value.toUpperCase()
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
}
