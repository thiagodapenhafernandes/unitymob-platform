// First touch and conversion-session touch are independent; internal navigation
// must not replace the arrival that started the session.
export const TRACKING_KEYS = ['utm_source','utm_medium','utm_campaign','utm_term','utm_content',
  'utm_id','campaign_id','campaign_name','ad_id','adset_id','form_id','gad_campaignid',
  'gclid','fbclid','msclkid','gbraid','wbraid','ttclid']
const FIRST_KEY = 'unitymob_first_touch_attribution_v1'
const SESSION_KEY = 'unitymob_conversion_touch_v2'
const FIRST_TTL = 90 * 24 * 60 * 60 * 1000
const SESSION_TTL = 30 * 60 * 1000

export class LeadAttribution {
  constructor(browser = window, doc = document, now = () => Date.now()) {
    this.browser = browser
    this.doc = doc
    this.now = now
    this.first = null
    this.session = null
    this.capture()
  }

  consent() {
    const cookies = this.doc.cookie.split(';').map(value => value.trim())
    if (cookies.includes('unitymob_lgpd_consent=rejected') || this.browser.UnitymobLgpdConsent?.rejected()) return 'rejected'
    if (cookies.includes('unitymob_lgpd_consent=accepted') || this.browser.UnitymobLgpdConsent?.accepted()) return 'accepted'
    return 'pending'
  }

  storage(kind) {
    try { return this.browser[kind] } catch (_) { return null }
  }

  read(kind, key) {
    try {
      const value = JSON.parse(this.storage(kind)?.getItem(key) || 'null')
      if (!value || !Number.isFinite(value.expires_at) || value.expires_at <= this.now() || !value.attribution || typeof value.attribution !== 'object' || Array.isArray(value.attribution)) return null
      return value.attribution
    } catch (_) { return null }
  }

  write(kind, key, attribution, ttl) {
    try { this.storage(kind)?.setItem(key, JSON.stringify({ attribution, expires_at: this.now() + ttl })) } catch (_) {}
  }

  clear() {
    for (const [kind, key] of [['localStorage', FIRST_KEY], ['sessionStorage', SESSION_KEY]]) {
      try { this.storage(kind)?.removeItem(key) } catch (_) {}
    }
    this.first = null
    this.session = null
  }

  current() {
    const url = new URL(this.browser.location.href)
    const result = { landing_url: url.href, referrer_url: this.doc.referrer }
    for (const key of TRACKING_KEYS) {
      const value = url.searchParams.get(key)
      if (value) result[key] = value.slice(0, 1024)
    }
    return result
  }

  externalReferrer(value) {
    try {
      const normalize = host => host.toLowerCase().replace(/^www\./, '')
      return normalize(new URL(value).hostname) !== normalize(this.browser.location.hostname)
    } catch (_) { return false }
  }

  capture() {
    if (this.consent() === 'rejected') { this.clear(); return }
    const current = this.current()
    const persist = this.consent() === 'accepted'
    this.first ||= persist ? this.read('localStorage', FIRST_KEY) : null
    this.first ||= current
    const saved = persist ? this.read('sessionStorage', SESSION_KEY) : null
    const tagged = TRACKING_KEYS.some(key => current[key])
    const newArrival = tagged || this.externalReferrer(current.referrer_url)
    this.session = newArrival ? current : (saved || current)
    if (persist) {
      // Keep the original first-touch expiry instead of extending it on every visit.
      if (!this.read('localStorage', FIRST_KEY)) this.write('localStorage', FIRST_KEY, this.first, FIRST_TTL)
      this.write('sessionStorage', SESSION_KEY, this.session, SESSION_TTL)
    }
  }

  payload() {
    if (this.consent() === 'rejected') { this.clear(); return {} }
    // A long-open page retains its own arrival; this doesn't borrow an unrelated tab's session.
    if (!this.session) this.capture()
    if (this.consent() === 'accepted') {
      if (!this.read('localStorage', FIRST_KEY)) this.write('localStorage', FIRST_KEY, this.first, FIRST_TTL)
      this.write('sessionStorage', SESSION_KEY, this.session, SESSION_TTL)
    }
    return { ...this.session, first_touch: this.first, conversion_touch: this.session }
  }
}
