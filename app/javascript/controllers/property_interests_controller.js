import { Controller } from "@hotwired/stimulus"

// Imóveis de interesse do lead (painel de contexto do WhatsApp).
// O autocomplete em si é o tom-select (data-controller="tom-select" no select,
// com URL remota); aqui só orquestramos create/destroy via fetch e trocamos os
// chips renderizados pelo servidor — mesmo padrão do lead_labels_controller.
//
//   <div data-controller="property-interests"
//        data-property-interests-create-url-value="/admin/leads/1/property_interests">
//     <div data-property-interests-target="list">…chips…</div>
//     <select data-property-interests-target="select"
//             data-action="change->property-interests#add">…</select>
//   </div>
export default class extends Controller {
  static targets = ["list", "select", "error", "shareCheckbox", "shareButton", "suggestButton", "shareResult", "shareLink", "whatsappLink", "expires"]
  static values = { createUrl: String, shareUrl: String, suggestUrl: String }

  connect() {
    this.busy = false
    this.lastShareMessage = ""
    this.lastShareUrl = ""
    this.updateShareButton()
  }

  add(event) {
    const habitationId = event.target.value
    if (!habitationId) return

    const body = new FormData()
    body.append("property_interest[habitation_id]", habitationId)
    this.request(this.createUrlValue, "POST", body).then((ok) => {
      if (ok) this.clearSelect()
    })
  }

  remove(event) {
    const url = event.currentTarget.dataset.url
    if (url) this.request(url, "DELETE")
  }

  toggleShareSelection() {
    this.updateShareButton()
  }

  async share() {
    if (!this.hasShareUrlValue || this.busy) return

    const ids = this.selectedShareIds()
    if (ids.length === 0) {
      this.showError("Selecione ao menos um imóvel para compartilhar.")
      return
    }

    this.busy = true
    this.setShareBusy(true)
    try {
      const body = new FormData()
      ids.forEach((id) => body.append("habitation_ids[]", id))
      if (this.hasExpiresTarget) body.append("expires_in_days", this.expiresTarget.value)

      const response = await fetch(this.shareUrlValue, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken(),
          "X-Requested-With": "XMLHttpRequest"
        },
        body
      })
      const data = await response.json().catch(() => ({}))

      if (!response.ok) {
        this.showError(data.error || "Não foi possível gerar o link.")
        return
      }

      if (typeof data.chips_html === "string" && this.hasListTarget) {
        this.listTarget.innerHTML = data.chips_html
      }
      this.showShareResult(data)
      if (this.hasErrorTarget) this.errorTarget.hidden = true
    } catch (_error) {
      this.showError("Falha de conexão. Tente novamente.")
    } finally {
      this.busy = false
      this.setShareBusy(false)
      this.updateShareButton()
    }
  }

  async suggest() {
    if (!this.hasSuggestUrlValue || this.busy) return

    this.busy = true
    this.setSuggestBusy(true)
    this.setShareBusy(true)
    try {
      const response = await fetch(this.suggestUrlValue, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken(),
          "X-Requested-With": "XMLHttpRequest"
        }
      })
      const data = await response.json().catch(() => ({}))

      if (!response.ok) {
        this.showError(data.error || "Não foi possível sugerir imóveis semelhantes.")
        return
      }

      if (typeof data.chips_html === "string" && this.hasListTarget) {
        this.listTarget.innerHTML = data.chips_html
      }
      if (this.hasErrorTarget) this.errorTarget.hidden = true
    } catch (_error) {
      this.showError("Falha de conexão. Tente novamente.")
    } finally {
      this.busy = false
      this.setSuggestBusy(false)
      this.setShareBusy(false)
      this.updateShareButton()
    }
  }

  async copyLink() {
    const text = this.lastShareUrl || (this.hasShareLinkTarget ? this.shareLinkTarget.value : "")
    if (!text) return

    await this.copyText(text)
  }

  sendInternally() {
    const body = this.lastShareMessage || this.lastShareUrl || (this.hasShareLinkTarget ? this.shareLinkTarget.value : "")
    if (!body) return

    window.dispatchEvent(new CustomEvent("wa-property-share:fill", {
      detail: { body }
    }))
  }

  clearSelect() {
    if (!this.hasSelectTarget) return
    const ts = this.selectTarget.tomselect
    if (ts) {
      ts.clear(true)
      ts.blur()
    } else {
      this.selectTarget.value = ""
    }
  }

  async request(url, method, body = null) {
    if (this.busy) return false
    this.busy = true
    try {
      const response = await fetch(url, {
        method,
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken(),
          "X-Requested-With": "XMLHttpRequest"
        },
        body
      })
      const data = await response.json().catch(() => ({}))

      if (!response.ok) {
        this.showError(data.error || "Não foi possível concluir a ação.")
        return false
      }

      if (typeof data.chips_html === "string" && this.hasListTarget) {
        this.listTarget.innerHTML = data.chips_html
        this.updateShareButton()
      }
      if (this.hasErrorTarget) this.errorTarget.hidden = true
      return true
    } catch (_error) {
      this.showError("Falha de conexão. Tente novamente.")
      return false
    } finally {
      this.busy = false
    }
  }

  selectedShareIds() {
    if (!this.hasShareCheckboxTarget) return []

    return this.shareCheckboxTargets.filter((checkbox) => checkbox.checked).map((checkbox) => checkbox.value)
  }

  updateShareButton() {
    if (!this.hasShareButtonTarget) return

    this.shareButtonTarget.disabled = this.selectedShareIds().length === 0 || this.busy
  }

  setShareBusy(active) {
    if (!this.hasShareButtonTarget) return

    this.shareButtonTarget.disabled = active
    this.shareButtonTarget.setAttribute("aria-busy", active ? "true" : "false")
    this.shareButtonTarget.classList.toggle("is-loading", active)
  }

  setSuggestBusy(active) {
    if (!this.hasSuggestButtonTarget) return

    this.suggestButtonTarget.disabled = active
    this.suggestButtonTarget.setAttribute("aria-busy", active ? "true" : "false")
  }

  showShareResult(data) {
    this.lastShareUrl = data.url || ""
    this.lastShareMessage = data.message || this.lastShareUrl
    if (this.hasShareResultTarget) this.shareResultTarget.hidden = false
    if (this.hasShareLinkTarget) this.shareLinkTarget.value = this.lastShareUrl
    if (this.hasWhatsappLinkTarget) {
      if (data.whatsapp_url) {
        this.whatsappLinkTarget.href = data.whatsapp_url
        this.whatsappLinkTarget.hidden = false
      } else {
        this.whatsappLinkTarget.hidden = true
      }
    }
  }

  async copyText(text) {
    if (!text) return

    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text)
      return
    }

    if (!this.hasShareLinkTarget) return
    this.shareLinkTarget.value = text
    this.shareLinkTarget.select()
    document.execCommand("copy")
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
