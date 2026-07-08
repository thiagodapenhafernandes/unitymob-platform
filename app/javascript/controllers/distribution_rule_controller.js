import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["represamentoSection", "pocketSection", "metaSection", "webhookSection", "notifyWebhookSection",
                    "notifyWebhookSelect", "notifyWebhookError",
                    "channelModal", "channelModalName", "channelModalInstructions", "channelModalLink",
                    "checkinStoreSelect", "storeContextSection"]

  connect() {
    this.toggleRepresamento()
    this.togglePocket()
    this.toggleMeta()
    this.toggleMeta()
    this.toggleWebhook()
    this.toggleNotifyWebhook()
    this.toggleMode()
    this.toggleStoreContext()
  }

  // Rails f.check_box renderiza 2 inputs (hidden "0" + checkbox "1") com mesmo name,
  // então sempre buscamos explicitamente por type=checkbox pra pegar o certo.
  findCheckbox(selector) {
    return this.element.querySelector(`${selector}[type="checkbox"]`) ||
           this.element.querySelector(selector)
  }

  toggleRepresamento(event) {
    const checkbox = event ? event.target : this.findCheckbox('#checkRepresamento')
    if (this.hasRepresamentoSectionTarget && checkbox) {
      this.setVisible(this.represamentoSectionTarget, checkbox.checked)
    }
  }

  togglePocket(event) {
    const checkbox = event ? event.target : this.findCheckbox('#checkPocket')
    if (this.hasPocketSectionTarget && checkbox) {
      this.setVisible(this.pocketSectionTarget, checkbox.checked)
    }
  }

  toggleMeta(event) {
    const checkbox = event ? event.target : this.findCheckbox('[name="distribution_rule[source_meta]"]')
    if (this.hasMetaSectionTarget && checkbox) {
      this.setVisible(this.metaSectionTarget, checkbox.checked)
    }
  }

  toggleWebhook(event) {
    const checkbox = event ? event.target : this.findCheckbox('[name="distribution_rule[source_webhook]"]')
    if (this.hasWebhookSectionTarget && checkbox) {
      this.setVisible(this.webhookSectionTarget, checkbox.checked)
    }
  }

  toggleNotifyWebhook(event) {
    const checkbox = event ? event.target : this.findCheckbox('[name="distribution_rule[notify_webhook]"]')
    if (this.hasNotifyWebhookSectionTarget && checkbox) {
      this.setVisible(this.notifyWebhookSectionTarget, checkbox.checked)
    }
    if (checkbox && checkbox.checked && this.hasNotifyWebhookErrorTarget) {
      this.setVisible(this.notifyWebhookErrorTarget, false)
    }
  }

  // Bloqueia marcar um canal (WhatsApp/E-mail/Push) ainda não configurado:
  // reverte o toggle e abre o modal com instruções + link de configuração.
  guardChannel(event) {
    const input = event.target
    if (!input.checked) return
    if (input.dataset.configured === "true") return

    input.checked = false
    input.closest(".ax-toggle-chip")?.classList.remove("is-checked")
    this.openChannelModal(input)
  }

  openChannelModal(input) {
    if (!this.hasChannelModalTarget) return

    if (this.hasChannelModalNameTarget) this.channelModalNameTarget.textContent = input.dataset.channelLabel || "este canal"
    if (this.hasChannelModalInstructionsTarget) this.channelModalInstructionsTarget.textContent = input.dataset.configInstructions || ""
    if (this.hasChannelModalLinkTarget) this.channelModalLinkTarget.href = input.dataset.configPath || "#"

    this.channelModalTarget.dispatchEvent(new CustomEvent("ax-modal:open", { bubbles: true }))
  }

  // No submit: impede salvar com canal selecionado-e-não-configurado (abre modal)
  // e exige ao menos uma URL quando o Webhook externo está ligado.
  validateBeforeSubmit(event) {
    const guarded = this.element.querySelectorAll('input[type="checkbox"][data-channel]')
    for (const input of guarded) {
      if (input.checked && input.dataset.configured !== "true") {
        event.preventDefault()
        this.openChannelModal(input)
        return
      }
    }

    const webhook = this.findCheckbox('[name="distribution_rule[notify_webhook]"]')
    if (webhook && webhook.checked && this.webhookUrlCount() === 0) {
      event.preventDefault()
      if (this.hasNotifyWebhookSectionTarget) this.setVisible(this.notifyWebhookSectionTarget, true)
      if (this.hasNotifyWebhookErrorTarget) {
        this.setVisible(this.notifyWebhookErrorTarget, true)
        this.notifyWebhookErrorTarget.scrollIntoView({ behavior: "smooth", block: "center" })
      }
    }
  }

  webhookUrlCount() {
    const select = this.hasNotifyWebhookSelectTarget
      ? this.notifyWebhookSelectTarget
      : this.notifyWebhookSectionTarget?.querySelector("select")
    return select ? select.selectedOptions.length : 0
  }

  toggleMode(event) {
    const selectedMode = event ? event.target.value : (this.element.querySelector('input[name="distribution_rule[distribution_mode]"]:checked')?.value || 'rotary')

    const performanceFields = document.querySelectorAll('.performance-field')
    const rotaryFields = document.querySelectorAll('.rotary-field')

    performanceFields.forEach(el => this.setVisible(el, selectedMode === 'performance'))
    rotaryFields.forEach(el => this.setVisible(el, selectedMode === 'rotary'))
  }

  toggleStoreContext() {
    if (!this.hasStoreContextSectionTarget) return

    const hasSelectedStore = this.selectedCheckinStoreIds().length > 0
    this.setVisible(this.storeContextSectionTarget, hasSelectedStore)
  }

  selectedCheckinStoreIds() {
    const select = this.hasCheckinStoreSelectTarget
      ? this.checkinStoreSelectTarget
      : this.element.querySelector('select[name="distribution_rule[checkin_store_ids][]"]')

    if (!select) return []

    const tomSelectValues = select.tomselect?.items || select.tomSelect?.items
    if (tomSelectValues) return tomSelectValues.map(value => value.toString()).filter(Boolean)

    return Array.from(select.selectedOptions || [])
      .map(option => option.value)
      .filter(Boolean)
  }

  stopTooltipClick(event) {
    event.preventDefault()
    event.stopPropagation()
  }

  setVisible(element, visible) {
    element.hidden = !visible
    element.classList.toggle("tw-hidden", !visible)
  }
}
