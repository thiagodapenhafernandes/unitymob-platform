import { Controller } from "@hotwired/stimulus"
import { LeadAttribution, TRACKING_KEYS } from "lib/lead_attribution"

export default class extends Controller {
  connect() {
    this.attribution = new LeadAttribution()
    this.onConsent = () => this.attribution.payload()
    window.addEventListener("unitymob:lgpd-consent-accepted", this.onConsent)
    window.addEventListener("unitymob:lgpd-consent-rejected", this.onConsent)
  }

  disconnect() {
    window.removeEventListener("unitymob:lgpd-consent-accepted", this.onConsent)
    window.removeEventListener("unitymob:lgpd-consent-rejected", this.onConsent)
  }

  append({ formData }) {
    const payload = this.attribution.payload()
    for (const touch of [null, "first_touch", "conversion_touch"]) {
      for (const key of [...TRACKING_KEYS, "landing_url", "referrer_url"]) {
        const name = touch ? `attribution[${touch}][${key}]` : `attribution[${key}]`
        const value = (touch ? payload[touch] : payload)?.[key]
        formData.delete(name)
        if (value) formData.set(name, value)
      }
    }
  }
}
