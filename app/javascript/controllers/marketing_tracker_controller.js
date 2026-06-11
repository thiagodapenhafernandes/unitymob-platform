import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    eventType: String,
    placement: String,
    label: String,
    targetUrl: String,
    campaignId: Number,
    habitationId: Number,
    component: String
  }

  track(event) {
    if (!this.canTrack()) return

    const target = event.currentTarget
    const payload = new FormData()

    payload.append("event_type", this.valueFor(target, "eventType") || this.eventTypeValue || "campaign_click")
    payload.append("placement", this.valueFor(target, "placement") || this.placementValue || "")
    payload.append("label", this.valueFor(target, "label") || this.labelValue || target.textContent?.trim() || "")
    payload.append("target_url", this.valueFor(target, "targetUrl") || this.targetUrlValue || target.href || "")
    payload.append("page_url", window.location.href)
    payload.append("component", this.valueFor(target, "component") || this.componentValue || "")

    const campaignId = this.valueFor(target, "campaignId") || this.campaignIdValue
    const habitationId = this.valueFor(target, "habitationId") || this.habitationIdValue
    if (campaignId) payload.append("marketing_campaign_id", campaignId)
    if (habitationId) payload.append("habitation_id", habitationId)

    if (navigator.sendBeacon) {
      navigator.sendBeacon("/marketing/events", payload)
      return
    }

    fetch("/marketing/events", {
      method: "POST",
      body: payload,
      credentials: "same-origin",
      keepalive: true
    }).catch(() => {})
  }

  valueFor(element, name) {
    return element.dataset[`marketingTracker${this.capitalize(name)}Value`]
  }

  capitalize(value) {
    return value.charAt(0).toUpperCase() + value.slice(1)
  }

  canTrack() {
    return window.SaluteLgpdConsent?.accepted?.() === true
  }
}
