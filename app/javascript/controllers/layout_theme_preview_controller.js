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

const PUBLIC_VARS = {
  primary: "--theme-public-primary",
  secondary: "--theme-public-secondary",
  accent: "--theme-public-accent"
}

const DARK_THEME = {
  surface: "#172033",
  header: "#202B3D",
  workspace: "#0F1726",
  sidebar: "#141D2D",
  ink: "#E6EDF7"
}

const INITIAL_THEME_DATASET = {
  surface: "layoutThemePreviewInitialSurface",
  header: "layoutThemePreviewInitialHeader",
  workspace: "layoutThemePreviewInitialWorkspace",
  sidebar: "layoutThemePreviewInitialSidebar",
  primary: "layoutThemePreviewInitialPrimary",
  ink: "layoutThemePreviewInitialInk"
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
  static targets = ["brandName", "areaName", "contrast"]

  connect() {
    this.applyInitialTheme()

    // O tema efetivo do usuário manda ao abrir a tela; o radio só vale depois que a pessoa o troca (updateMode).
    if (this.previewingDark()) {
      this.applyDarkTheme()
    } else {
      this.applyLightTheme()
    }

    this.updateContrast()
  }

  applyInitialTheme() {
    Object.entries(INITIAL_THEME_DATASET).forEach(([token, datasetKey]) => {
      const value = this.normalizedHex(this.element.dataset[datasetKey])
      if (value) this.element.style.setProperty(TOKEN_TO_VAR[token], value)
    })

    Object.entries(PUBLIC_VARS).forEach(([key, cssVar]) => {
      const value = this.normalizedHex(this.element.dataset[`layoutThemePreviewPublic${key[0].toUpperCase()}${key.slice(1)}`])
      if (value) this.element.style.setProperty(cssVar, value)
    })
  }

  updateMode() {
    if (this.darkModeSelected()) {
      document.documentElement.dataset.adminTheme = "dark"
      this.applyDarkTheme()
    } else {
      document.documentElement.dataset.adminTheme = "light"
      this.applyLightTheme()
    }
  }

  applyLightTheme() {
    this.element.querySelectorAll("[data-theme-token]").forEach((input) => {
      this.applyToken(input.dataset.themeToken, input.value, { syncInputs: false })
    })
  }

  applyDarkTheme() {
    Object.entries(DARK_THEME).forEach(([token, value]) => {
      this.applyToken(token, value, { syncInputs: false })
    })
  }

  previewingDark() {
    return document.documentElement.dataset.adminTheme === "dark"
  }

  darkModeSelected() {
    return this.element.querySelector('input[name="layout_setting[admin_theme_mode]"]:checked')?.value === "dark"
  }

  update(event) {
    if (this.previewingDark()) return

    const token = event.currentTarget.dataset.themeToken
    this.applyToken(token, event.currentTarget.value, { source: event.currentTarget })
  }

  // Nomes da marca e da plataforma espelhados na prévia enquanto a pessoa digita.
  updateName(event) {
    const input = event.currentTarget
    const targets = input.dataset.previewName === "area" ? this.areaNameTargets : this.brandNameTargets
    const text = input.value.trim() || input.dataset.previewFallback || ""
    targets.forEach((el) => { el.textContent = text })
  }

  // Cores do site público: --theme-public-{primary,secondary,accent} para a prévia do site.
  updatePublic(event) {
    const input = event.currentTarget
    const value = this.normalizedHex(input.value)
    const cssVar = PUBLIC_VARS[input.dataset.publicKey]
    if (!value || !cssVar) return

    this.element.style.setProperty(cssVar, value)
  }

  // Abre, na sidebar da prévia, a divisão escolhida no seletor do menu (igual ao menu real: uma aberta por vez).
  focusSection(event) {
    const key = String(event.currentTarget.dataset.menuSectionKey || "").replaceAll("_", "-")
    this.element.querySelectorAll(".lss-sidebar [data-nav-section]").forEach((section) => {
      const open = section.dataset.navSection === key
      section.classList.toggle("is-open", open)
      section.querySelector(".ax-nav__section-trigger")?.setAttribute("aria-expanded", String(open))
      section.querySelector(".ax-nav__section-items")?.classList.toggle("is-visible", open)
    })
  }

  // Volta uma divisão do menu aos valores padrão (data-default-value) e reaplica na sidebar e na prévia.
  resetMenuSection(event) {
    const panel = event.currentTarget.closest("[data-menu-panel]")
    panel?.querySelectorAll("[data-menu-style-property][data-default-value]").forEach((input) => {
      input.value = input.dataset.defaultValue
      input.dispatchEvent(new Event("input", { bubbles: true }))
    })
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

    this.updateContrast()
  }

  // Legibilidade das combinações que o tema cria (WCAG): texto 4.5:1, componentes de interface 3:1.
  updateContrast() {
    if (!this.hasContrastTarget) return

    const read = (token) => this.normalizedHex(this.element.style.getPropertyValue(TOKEN_TO_VAR[token]))
    const pairs = {
      "ink:surface": [read("ink"), read("surface"), 4.5],
      "white:primary": ["#ffffff", read("primary"), 4.5],
      "primary:surface": [read("primary"), read("surface"), 3]
    }

    this.contrastTargets.forEach((target) => {
      const [foreground, background, minimum] = pairs[target.dataset.contrastPair] || []
      if (!foreground || !background) return

      const ratio = this.contrastRatio(foreground, background)
      target.querySelector("[data-contrast-value]").textContent = `${ratio.toFixed(1)}:1`
      target.dataset.state = ratio >= minimum ? "pass" : ratio >= minimum * 0.75 ? "warn" : "fail"
    })
  }

  contrastRatio(a, b) {
    const luminance = (hex) => {
      const [r, g, bl] = [1, 3, 5].map((i) => {
        const channel = parseInt(hex.slice(i, i + 2), 16) / 255
        return channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4
      })
      return 0.2126 * r + 0.7152 * g + 0.0722 * bl
    }
    const [light, dark] = [luminance(a), luminance(b)].sort((x, y) => y - x)
    return (light + 0.05) / (dark + 0.05)
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
