import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "unitymob_lgpd_consent_v1"
const COOKIE_KEY = "unitymob_lgpd_consent"
const COOKIE_MAX_AGE = 180 * 24 * 60 * 60
let sessionChoice = null

function choice() {
  const value = document.cookie.split(";").map(cookie => cookie.trim()).find(cookie => cookie.startsWith(`${COOKIE_KEY}=`))?.split("=")[1]
  return ["accepted", "rejected"].includes(value) ? value : sessionChoice
}

window.UnitymobLgpdConsent = {
  accepted: () => choice() === "accepted",
  rejected: () => choice() === "rejected"
}

export default class extends Controller {
  static targets = ["banner", "preferences"]

  connect() {
    this.render()
    this.onStorage = event => {
      if (event.key === STORAGE_KEY) window.location.reload()
    }
    window.addEventListener("storage", this.onStorage)
  }

  disconnect() {
    window.removeEventListener("storage", this.onStorage)
  }

  render() {
    this.bannerTarget.classList.toggle("hidden", choice() !== null)
    this.preferencesTarget.classList.toggle("hidden", choice() === null)
  }

  manage() {
    this.bannerTarget.classList.remove("hidden")
    this.preferencesTarget.classList.add("hidden")
    this.bannerTarget.querySelector("button")?.focus()
  }

  accept() {
    this.save("accepted")
    document.cookie = "unitymob_interest_consent=; Max-Age=0; Path=/; SameSite=Lax"
    try { window.localStorage.removeItem("unitymob_interest_consent") } catch (_) {}
    window.dispatchEvent(new CustomEvent("unitymob:lgpd-consent-accepted"))
    this.render()
  }

  reject() {
    const previouslyAccepted = choice() === "accepted"
    this.save("rejected")
    // Also withdraw the separate interest choice; do not touch authentication cookies.
    document.cookie = "unitymob_interest_consent=rejected; Max-Age=15552000; Path=/; SameSite=Lax"
    try { window.localStorage.setItem("unitymob_interest_consent", "rejected") } catch (_) {}
    window.dispatchEvent(new CustomEvent("unitymob:lgpd-consent-rejected"))
    this.render()
    // Third-party scripts already loaded cannot be reliably unloaded individually.
    if (previouslyAccepted) window.location.reload()
  }

  save(value) {
    sessionChoice = value
    document.cookie = `${COOKIE_KEY}=${value}; Max-Age=${COOKIE_MAX_AGE}; Path=/; SameSite=Lax`
    try { window.localStorage.setItem(STORAGE_KEY, value) } catch (_) {}
  }
}
