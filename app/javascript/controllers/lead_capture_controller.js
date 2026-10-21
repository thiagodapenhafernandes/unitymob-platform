import { Controller } from "@hotwired/stimulus"
import { LeadAttribution } from "lib/lead_attribution"

export default class extends Controller {

  static targets = ["modal", "propertyId", "leadType", "origin", "shareToken", "name", "phone", "email", "submitButton", "phoneError"]
  static values = {
    enabled: Boolean,
    phoneSettings: Object,
    shareToken: String
  }

  connect() {
    this.attribution = new LeadAttribution()
    this.onAttributionConsent = () => this.attribution.payload()
    window.addEventListener('unitymob:lgpd-consent-accepted', this.onAttributionConsent)
    window.addEventListener('unitymob:lgpd-consent-rejected', this.onAttributionConsent)

    // Close on escape key
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && this.hasModalTarget && !this.modalTarget.classList.contains('hidden')) {
        this.close()
      }
    })
  }

  disconnect() {
    window.removeEventListener('unitymob:lgpd-consent-accepted', this.onAttributionConsent)
    window.removeEventListener('unitymob:lgpd-consent-rejected', this.onAttributionConsent)
  }

  async open(event) {
    event.preventDefault()
    event.stopPropagation()

    // Get data from the trigger element
    const trigger = event.currentTarget
    const propertyId = trigger.dataset.propertyId
    const propertyTitle = trigger.dataset.propertyTitle || ""
    const propertyCode = trigger.dataset.propertyCode || ""
    const message = trigger.dataset.whatsappMessage || `Olá, gostaria de mais informações sobre o imóvel ${propertyTitle} (Cód: ${propertyCode})`
    const leadOrigin = trigger.dataset.leadOrigin || "Site"
    const shareToken = trigger.dataset.shareToken || this.shareTokenValue || ""
    const negotiationType = trigger.dataset.negotiationType || "sale"
    const forceLeadForm = trigger.dataset.requireLeadForm === "true" || shareToken.startsWith("broker-page-")
    const requiresLeadForm = forceLeadForm || this.requiresLeadForm(negotiationType)

    // Store message for redirect
    this.whatsappMessage = message
    this.negotiationType = negotiationType

    if (!requiresLeadForm) {
      window.open(this.whatsappUrlFor(negotiationType, message), "_blank")
      return
    }

    const routing = await this.fetchWhatsappRouting(propertyId, message)
    if (!forceLeadForm && routing && routing.capture_required === false && routing.whatsapp_url) {
      window.location.href = routing.whatsapp_url
      return
    }

    // Set hidden fields
    if (this.hasPropertyIdTarget) this.propertyIdTarget.value = propertyId
    if (this.hasLeadTypeTarget) this.leadTypeTarget.value = 'whatsapp_click' // Default
    if (this.hasOriginTarget) this.originTarget.value = leadOrigin
    if (this.hasShareTokenTarget) this.shareTokenTarget.value = shareToken

    // Show modal
    this.modalTarget.classList.remove('hidden')
    document.body.style.overflow = 'hidden' // Prevent scrolling

    // Focus name input
    setTimeout(() => {
      if (this.hasNameTarget) this.nameTarget.focus()
    }, 100)
  }

  close() {
    this.modalTarget.classList.add('hidden')
    document.body.style.overflow = ''
  }

  async submit(event) {
    event.preventDefault()
    if (this.submitting) return

    const name = this.nameTarget.value.trim()
    const phoneWithMask = this.phoneTarget.value
    const email = this.hasEmailTarget ? this.emailTarget.value : ""

    // Validation
    if (name.length < 3) {
      window.axToast({ message: "Por favor, informe seu nome completo.", type: "warning" })
      this.nameTarget.focus()
      return
    }

    this.submitting = true
    if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = true

    try {
      const { validatePublicWhatsapp } = await import("lib/public_whatsapp")
      const validation = validatePublicWhatsapp(phoneWithMask)
      if (validation.error) {
        this.showPhoneError(validation.error)
        return
      }
      this.clearPhoneError()
      const phone = validation.e164
      const result = await this.sendLeadData({
        name,
        phone,
        email,
        property_id: this.propertyIdTarget.value,
        origin: this.hasOriginTarget ? this.originTarget.value : "",
        share_token: this.hasShareTokenTarget ? this.shareTokenTarget.value : "",
        whatsapp_message: this.whatsappMessage,
        business_type: this.negotiationType,
        page_url: window.location.href,
        referrer_url: document.referrer,
        ...this.trackingParams()
      })

      if (!result?.success) {
        if (result?.field_errors?.phone) this.showPhoneError(result.field_errors.phone)
        else window.axToast({ message: result?.errors?.join(" ") || "Não foi possível enviar seu contato. Tente novamente.", type: "warning" })
        return
      }

      await this.trackConfirmedLead(result)

      if (result?.success && !result.whatsapp_url) {
        this.showSuccessMessage(result.message || "Recebemos seu contato. Um corretor da nossa equipe irá falar com você em breve.")
        this.close()
        event.target.reset()
        return
      }

      const whatsappUrl = result?.whatsapp_url || this.whatsappUrlFor(this.negotiationType, this.whatsappMessage)

      // Redirect to WhatsApp
      window.location.href = whatsappUrl

      // Close modal
      this.close()

      // Optional: Reset form
      event.target.reset()
    } catch (_) {
      window.axToast({ message: "Não foi possível validar e enviar seu contato. Tente novamente.", type: "warning" })
    } finally {
      this.submitting = false
      if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = false
    }
  }

  showPhoneError(message) {
    this.phoneTarget.setAttribute("aria-invalid", "true")
    this.phoneErrorTarget.textContent = message
    this.phoneErrorTarget.hidden = false
    this.phoneTarget.focus()
  }

  clearPhoneError() {
    this.phoneTarget.removeAttribute("aria-invalid")
    this.phoneErrorTarget.textContent = ""
    this.phoneErrorTarget.hidden = true
  }

  async trackConfirmedLead(result) {
    const confirmed = result?.analytics_event
    if (!result?.success || confirmed?.event !== "generate_lead" || !confirmed.event_id) return
    if (!window.UnitymobTracking?.track) return

    // Aguarda as tags antes de sair para o WhatsApp, sem bloquear contato se falharem.
    await new Promise(resolve => {
      const timeout = setTimeout(resolve, 700)
      const complete = () => { clearTimeout(timeout); resolve() }
      try {
        const tracked = window.UnitymobTracking.track("generate_lead", {
          event_id: confirmed.event_id,
          phone_e164: confirmed.phone_e164,
          business_type: confirmed.business_type,
          property_code: confirmed.property_code,
          form_id: confirmed.form_id,
          page_url: window.location.origin + window.location.pathname
        }, { onComplete: complete })
        if (!tracked) complete()
      } catch (_) {
        complete()
      }
    })
  }

  showSuccessMessage(message) {
    if (typeof window.axToast === "function") {
      window.axToast({ message, type: "success" })
    } else {
      window.alert(message)
    }
  }

  async sendLeadData(data) {
    const csrfToken = document.querySelector("[name='csrf-token']").content

    return fetch('/leads', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken
      },
      body: JSON.stringify({ lead: { ...data, lead_type: 'whatsapp_modal' } })
    }).then(async response => {
      const result = await response.json()
      return response.ok || response.status === 422 ? result : null
    }).catch(error => {
      console.error("Error capturing lead:", error)
      return null
    })
  }

  async fetchWhatsappRouting(propertyId, message) {
    if (!propertyId) return null

    const params = new URLSearchParams({
      property_id: propertyId,
      message: message || ""
    })

    return fetch(`/leads/whatsapp_url?${params.toString()}`, {
      headers: {
        "Accept": "application/json"
      }
    }).then(response => {
      if (!response.ok) return null
      return response.json()
    }).catch(error => {
      console.error("Error fetching WhatsApp routing:", error)
      return null
    })
  }

  whatsappUrlFor(negotiationType, message) {
    const phoneNumber = this.phoneNumberFor(negotiationType)
    const text = encodeURIComponent(message)
    return `https://wa.me/${phoneNumber}?text=${text}`
  }

  phoneNumberFor(negotiationType) {
    const settings = this.phoneSettingsValue || {}
    const negotiations = settings.negotiations || {}
    const config = negotiations[negotiationType] || {}
    return config.phone || settings.default_phone || "554733111067"
  }

  requiresLeadForm(negotiationType) {
    const settings = this.phoneSettingsValue || {}
    const negotiations = settings.negotiations || {}
    const config = negotiations[negotiationType] || {}
    return config.requires_form !== false
  }

  trackingParams() {
    return this.attribution.payload()
  }
}
