import { Controller } from "@hotwired/stimulus"

let intlTelInputPromise = null

export default class extends Controller {
  static values = {
    initialCountry: { type: String, default: "br" }
  }

  connect() {
    this.inputGroup = this.findInputGroup()
    this.inputGroup?.classList.add("phone-input-group")
    this.prepareInitialValue()
    this.handleSubmit = this.handleSubmit.bind(this)
    this.handleInput = this.handleInput.bind(this)
    this.handleCountryChange = this.handleCountryChange.bind(this)

    this.element.form?.addEventListener("submit", this.handleSubmit)
    this.element.addEventListener("input", this.handleInput)
    this.element.addEventListener("countrychange", this.handleCountryChange)
    this.loadStylesheet()
    this.initialize()
  }

  disconnect() {
    this.element.form?.removeEventListener("submit", this.handleSubmit)
    this.element.removeEventListener("input", this.handleInput)
    this.element.removeEventListener("countrychange", this.handleCountryChange)
    this.iti?.destroy()
    this.inputGroup?.classList.remove("phone-input-group")
  }

  initialize() {
    if (this.iti || this.initializing) return

    this.initializing = true

    this.loadIntlTelInput()
      .then((intlTelInput) => {
        this.iti = intlTelInput(this.element, {
          initialCountry: this.initialCountryValue,
          preferredCountries: ["br", "us", "pt"],
          nationalMode: true,
          separateDialCode: true,
          formatAsYouType: false,
          autoPlaceholder: "aggressive",
          utilsScript: "https://cdn.jsdelivr.net/npm/intl-tel-input@25.12.2/build/js/utils.js"
        })
        this.applyDisplayMask()
      })
      .catch(() => {})
      .finally(() => {
        this.initializing = false
      })
  }

  handleSubmit() {
    if (this.iti) {
      this.element.value = this.normalizeForSubmit(this.element.value)
      return
    }

    this.element.value = this.normalizeForSubmit(this.element.value)
  }

  handleInput() {
    this.applyDisplayMask()
  }

  handleCountryChange() {
    this.applyDisplayMask()
  }

  prepareInitialValue() {
    const value = this.element.value.trim()
    const digits = value.replace(/\D/g, "")

    if (digits.length === 0) return

    if (value.startsWith("+")) {
      this.element.value = digits.startsWith("55") ? this.formatBrazilianNational(digits) : `+${digits}`
      return
    }

    if (this.initialCountryValue === "br" && [10, 11].includes(digits.length)) {
      this.element.value = this.formatBrazilianNational(digits)
      return
    }

    if (digits.startsWith("55") && [12, 13].includes(digits.length)) {
      this.element.value = this.formatBrazilianNational(digits)
      return
    }

    this.element.value = this.initialCountryValue === "br" ? this.formatBrazilianNational(digits) : digits
  }

  normalizeForSubmit(value) {
    const rawValue = value.toString().trim()
    const digits = rawValue.replace(/\D/g, "")
    const normalizedDigits = this.normalizeBrazilianMobileDigits(digits)
    const selectedCountry = this.selectedCountryIso2()

    if (selectedCountry !== "br" && this.iti?.isValidNumber()) {
      return this.iti.getNumber().replace(/\D/g, "")
    }

    if (rawValue.startsWith("+")) return normalizedDigits

    if (selectedCountry === "br") {
      if (normalizedDigits.startsWith("55") && [12, 13].includes(normalizedDigits.length)) return normalizedDigits
      if ([10, 11].includes(normalizedDigits.length)) return `55${normalizedDigits}`
    }

    return normalizedDigits
  }

  applyDisplayMask() {
    if (this.selectedCountryIso2() !== "br") return

    const previousValue = this.element.value
    const maskedValue = this.formatBrazilianNational(previousValue)
    if (maskedValue === previousValue) return

    this.element.value = maskedValue
  }

  formatBrazilianNational(value) {
    const digits = value.toString().replace(/\D/g, "")
    const nationalDigits = digits.startsWith("55") && [12, 13].includes(digits.length) ? digits.slice(2) : digits
    const limitedDigits = nationalDigits.slice(0, 11)

    if (limitedDigits.length < 3) return limitedDigits

    const ddd = limitedDigits.slice(0, 2)
    const number = limitedDigits.slice(2)

    if (number.length <= 4) return `(${ddd}) ${number}`
    if (number.length <= 8) return `(${ddd}) ${number.slice(0, 4)}-${number.slice(4)}`

    return `(${ddd}) ${number.slice(0, 5)}-${number.slice(5)}`
  }

  selectedCountryIso2() {
    return this.iti?.getSelectedCountryData()?.iso2 || this.initialCountryValue
  }

  findInputGroup() {
    const explicitGroup = this.element.closest(".ax-input-group, .input-group")
    if (explicitGroup) return explicitGroup

    return this.element.parentElement?.classList.contains("tw-flex") ? this.element.parentElement : null
  }

  normalizeBrazilianMobileDigits(digits) {
    if (this.initialCountryValue !== "br") return digits

    if (digits.length === 8 && this.brazilianMobileSubscriberWithoutNinthDigit(digits)) {
      return `9${digits}`
    }

    if (digits.length === 10 && !digits.startsWith("55")) {
      const ddd = digits.slice(0, 2)
      const subscriber = digits.slice(2)
      if (this.brazilianMobileSubscriberWithoutNinthDigit(subscriber)) return `${ddd}9${subscriber}`
    }

    if (digits.length === 12 && digits.startsWith("55")) {
      const ddd = digits.slice(2, 4)
      const subscriber = digits.slice(4)
      if (this.brazilianMobileSubscriberWithoutNinthDigit(subscriber)) return `55${ddd}9${subscriber}`
    }

    return digits
  }

  brazilianMobileSubscriberWithoutNinthDigit(digits) {
    return digits.length === 8 && ["6", "7", "8", "9"].includes(digits[0])
  }

  loadIntlTelInput() {
    if (!intlTelInputPromise) {
      intlTelInputPromise = import("intl-tel-input").then((module) => module.default || module)
    }

    return intlTelInputPromise
  }

  loadStylesheet() {
    if (!document.querySelector("link[data-phone-input-css]")) {
      const link = document.createElement("link")
      link.rel = "stylesheet"
      link.href = "https://cdn.jsdelivr.net/npm/intl-tel-input@25.12.2/build/css/intlTelInput.css"
      link.dataset.phoneInputCss = "true"
      document.head.appendChild(link)
    }

    if (document.querySelector("style[data-phone-input-local-css]")) return

    const style = document.createElement("style")
    style.dataset.phoneInputLocalCss = "true"
    style.textContent = `
      .iti { width: 100%; display: block; }
      .iti input.ax-control,
      .iti input.form-control,
      .iti input[type="tel"] { width: 100%; }
      .iti--separate-dial-code .iti__selected-country {
        background: #f6f8fb;
        border-right: 1px solid #d8e0eb;
      }
      .phone-input-group { align-items: stretch; }
      .phone-input-group > .iti {
        flex: 1 1 auto;
        min-width: 0;
      }
      .phone-input-group > .ax-input-group__addon,
      .phone-input-group > span[class*="bg-"] {
        display: none;
      }
    `
    document.head.appendChild(style)
  }
}
