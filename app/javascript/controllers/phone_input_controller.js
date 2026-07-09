import { Controller } from "@hotwired/stimulus"

let intlTelInputPromise = null

export default class extends Controller {
  static values = {
    initialCountry: { type: String, default: "br" }
  }

  connect() {
    this.prepareInitialValue()
    this.handleSubmit = this.handleSubmit.bind(this)
    this.initializeOnFocus = this.initializeOnFocus.bind(this)

    this.element.addEventListener("focus", this.initializeOnFocus, { once: true })
    this.element.form?.addEventListener("submit", this.handleSubmit)
  }

  disconnect() {
    this.element.removeEventListener("focus", this.initializeOnFocus)
    this.element.form?.removeEventListener("submit", this.handleSubmit)
    this.iti?.destroy()
  }

  initializeOnFocus() {
    this.loadStylesheet()
    this.initialize()
  }

  initialize() {
    if (this.iti || this.initializing) return

    this.initializing = true

    this.loadIntlTelInput()
      .then((intlTelInput) => {
        this.iti = intlTelInput(this.element, {
          initialCountry: this.initialCountryValue,
          preferredCountries: ["br", "us", "pt"],
          nationalMode: false,
          separateDialCode: true,
          autoPlaceholder: "aggressive",
          utilsScript: "https://cdn.jsdelivr.net/npm/intl-tel-input@25.12.2/build/js/utils.js"
        })
      })
      .catch(() => {})
      .finally(() => {
        this.initializing = false
      })
  }

  handleSubmit() {
    if (this.iti) {
      const value = this.iti.getNumber()
      if (value) this.element.value = value.replace(/\D/g, "")
      return
    }

    this.element.value = this.element.value.replace(/\D/g, "")
  }

  prepareInitialValue() {
    const value = this.element.value.trim()
    const digits = value.replace(/\D/g, "")

    if (value.startsWith("+") || digits.length < 12 || digits.length > 15) return

    this.element.value = `+${digits}`
  }

  loadIntlTelInput() {
    if (!intlTelInputPromise) {
      intlTelInputPromise = import("intl-tel-input").then((module) => module.default || module)
    }

    return intlTelInputPromise
  }

  loadStylesheet() {
    if (document.querySelector("link[data-phone-input-css]")) return

    const link = document.createElement("link")
    link.rel = "stylesheet"
    link.href = "https://cdn.jsdelivr.net/npm/intl-tel-input@25.12.2/build/css/intlTelInput.css"
    link.dataset.phoneInputCss = "true"
    document.head.appendChild(link)
  }
}
