import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["consentBanner"]

  static values = {
    enabled: { type: Boolean, default: true },
    consentRequired: { type: Boolean, default: false },
    propertyId: String,
    propertyCode: String,
    propertyCategory: String,
    propertyCity: String,
    propertyNeighborhood: String,
    propertyBedrooms: Number,
    propertyPriceCents: Number
  }

  connect() {
    this.startedAt = Date.now()
    this.tracked = new Set()
    this.formStarted = false
    this.trackPage()
    this.boundClick = this.trackClick.bind(this)
    this.boundFocusIn = this.trackFocusIn.bind(this)
    this.boundSubmit = this.trackSubmit.bind(this)
    this.boundVisibility = this.trackVisibility.bind(this)
    this.boundPageHide = this.trackPageHide.bind(this)
    document.addEventListener("click", this.boundClick, { capture: true })
    document.addEventListener("focusin", this.boundFocusIn, { capture: true })
    document.addEventListener("submit", this.boundSubmit, { capture: true })
    document.addEventListener("visibilitychange", this.boundVisibility)
    window.addEventListener("pagehide", this.boundPageHide)
    this.renderConsentState()
  }

  disconnect() {
    if (this.boundClick) document.removeEventListener("click", this.boundClick, { capture: true })
    if (this.boundFocusIn) document.removeEventListener("focusin", this.boundFocusIn, { capture: true })
    if (this.boundSubmit) document.removeEventListener("submit", this.boundSubmit, { capture: true })
    if (this.boundVisibility) document.removeEventListener("visibilitychange", this.boundVisibility)
    if (this.boundPageHide) window.removeEventListener("pagehide", this.boundPageHide)
  }

  trackPage() {
    if (!this.canTrack()) return

    const eventName = this.hasPropertyIdValue && this.propertyIdValue ? "property_view" : "page_view"
    this.enqueue(eventName)
    if (!this.hasPropertyIdValue && Object.keys(this.searchParams()).length > 0) {
      this.enqueue("property_search")
      window.setTimeout(() => this.trackSearchOutcome(), 800)
    }
  }

  trackSearchOutcome() {
    if (document.querySelector("[data-property-id], [data-property-code], .property-card, .tw-property-card")) return

    this.enqueue("search_no_results", { metadata: { search_without_visible_results: true } })
  }

  trackClick(event) {
    const trigger = event.target.closest("[data-action*='lead-capture#open']")
    const phoneTrigger = event.target.closest("a[href^='tel:']")
    const shareTrigger = event.target.closest("[data-share], a[href*='whatsapp://send'], a[href*='api.whatsapp.com/send']")

    if (trigger) {
      this.enqueue("property_whatsapp_click", {
        habitation_id: trigger.dataset.propertyId || this.propertyIdValue,
        metadata: {
          property_title: trigger.dataset.propertyTitle || "",
          lead_origin: trigger.dataset.leadOrigin || "",
          interaction: "lead_capture_open"
        }
      })
    } else if (phoneTrigger) {
      this.enqueue("property_phone_click", { metadata: { href: phoneTrigger.href } })
    } else if (shareTrigger) {
      this.enqueue("property_share", { metadata: { href: shareTrigger.href || "", label: shareTrigger.textContent?.trim() || "" } })
    }
  }

  trackFocusIn(event) {
    if (this.formStarted) return
    if (!event.target.closest("#lead-capture-modal form")) return

    this.formStarted = true
    this.enqueue("lead_form_started")
  }

  trackSubmit(event) {
    if (!event.target.closest("#lead-capture-modal form")) return

    this.track("lead_form_submitted")
  }

  trackVisibility() {
    if (document.visibilityState === "hidden") this.trackEngagement()
  }

  trackPageHide() {
    this.trackEngagement()
  }

  trackEngagement() {
    const duration = Math.max(Math.round((Date.now() - this.startedAt) / 1000), 0)
    if (duration < 8) return

    this.track(this.hasPropertyIdValue && this.propertyIdValue ? "property_engaged" : "page_view", {
      metadata: { engagement: true },
      beacon: true
    })
  }

  acceptConsent() {
    window.localStorage.setItem(this.consentKey(), "accepted")
    document.cookie = "unitymob_interest_consent=accepted; max-age=15552000; path=/; SameSite=Lax"
    this.renderConsentState()
    this.trackPage()
  }

  rejectConsent() {
    window.localStorage.setItem(this.consentKey(), "rejected")
    document.cookie = "unitymob_interest_consent=rejected; max-age=15552000; path=/; SameSite=Lax"
    this.renderConsentState()
  }

  enqueue(name, overrides = {}) {
    if (!this.canTrack()) return

    window.requestIdleCallback
      ? window.requestIdleCallback(() => this.track(name, overrides), { timeout: 1200 })
      : window.setTimeout(() => this.track(name, overrides), 250)
  }

  track(name, overrides = {}) {
    if (!this.canTrack()) return

    const csrfToken = document.querySelector("[name='csrf-token']")?.content
    const dedupeKey = `${name}:${overrides.habitation_id || this.propertyIdValue || ""}:${Math.floor((Date.now() - this.startedAt) / 5000)}`
    if (this.tracked.has(dedupeKey) && !overrides.beacon) return
    this.tracked.add(dedupeKey)

    const body = JSON.stringify({
      navigation_event: {
        name,
        path: window.location.pathname,
        habitation_id: overrides.habitation_id || this.propertyIdValue || "",
        duration_seconds: Math.max(Math.round((Date.now() - this.startedAt) / 1000), 0),
        search_params: this.searchParams(),
        property_snapshot: this.propertySnapshot(),
        metadata: {
          title: document.title,
          referrer: document.referrer,
          url: window.location.href,
          consent_granted: this.consentAccepted(),
          ...(overrides.metadata || {})
        }
      }
    })

    if (overrides.beacon && navigator.sendBeacon) {
      navigator.sendBeacon("/navigation_events", new Blob([body], { type: "application/json" }))
      return
    }

    fetch("/navigation_events", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {}),
        "Accept": "application/json"
      },
      body
    }).catch(() => {})
  }

  canTrack() {
    if (!this.enabledValue) return false
    if (navigator.doNotTrack === "1") return false
    if (!this.consentRequiredValue) return true
    return this.consentAccepted()
  }

  consentAccepted() {
    return window.localStorage.getItem(this.consentKey()) === "accepted" || document.cookie.includes("unitymob_interest_consent=accepted")
  }

  renderConsentState() {
    if (!this.hasConsentBannerTarget) return
    this.consentBannerTarget.hidden = !this.consentRequiredValue || this.consentAccepted() || window.localStorage.getItem(this.consentKey()) === "rejected"
  }

  consentKey() {
    return "unitymob_interest_consent"
  }

  searchParams() {
    const params = new URLSearchParams(window.location.search)
    const payload = {}
    params.forEach((value, key) => {
      if (value) payload[key] = value
    })
    return payload
  }

  propertySnapshot() {
    return {
      codigo: this.propertyCodeValue || "",
      category: this.propertyCategoryValue || "",
      city: this.propertyCityValue || "",
      neighborhood: this.propertyNeighborhoodValue || "",
      bedrooms: this.propertyBedroomsValue || "",
      parking_spaces: document.body.dataset.publicInterestTrackerPropertyParkingSpacesValue || "",
      price_cents: this.propertyPriceCentsValue || ""
    }
  }
}
