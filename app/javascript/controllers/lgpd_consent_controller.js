import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "salute_lgpd_consent_v1"
const COOKIE_KEY = "salute_lgpd_consent"
const ACCEPTED_VALUE = "accepted"
const COOKIE_MAX_AGE = 180 * 24 * 60 * 60

function consentAccepted() {
  if (document.cookie.split(";").some((cookie) => cookie.trim() === `${COOKIE_KEY}=${ACCEPTED_VALUE}`)) return true

  try {
    return window.localStorage.getItem(STORAGE_KEY) === ACCEPTED_VALUE
  } catch (_error) {
    return false
  }
}

window.SaluteLgpdConsent = {
  accepted: consentAccepted
}

export default class extends Controller {
  static targets = ["banner"]

  connect() {
    this.bannerTarget.classList.toggle("hidden", consentAccepted())
  }

  accept() {
    try {
      window.localStorage.setItem(STORAGE_KEY, ACCEPTED_VALUE)
      document.cookie = `${COOKIE_KEY}=${ACCEPTED_VALUE}; Max-Age=${COOKIE_MAX_AGE}; Path=/; SameSite=Lax`
    } catch (_error) {
      window.SaluteLgpdConsent.accepted = () => true
    }

    window.dispatchEvent(new CustomEvent("salute:lgpd-consent-accepted"))
    this.bannerTarget.classList.add("hidden")
  }
}
