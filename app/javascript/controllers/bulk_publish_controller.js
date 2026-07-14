import { Controller } from "@hotwired/stimulus"

const CHANNELS_WITH_OPTIONS = new Set([
  "chaves_na_mao",
  "casa_mineira",
  "imovelweb",
  "imovelweb_2",
  "viva_real_vrsync"
])

export default class extends Controller {
  static targets = [
    "item", "master", "toolbar", "count",
    "modal", "modalCount", "form",
    "channelSelect", "actionRadio",
    "channelOptionsWrapper",
    "eligTotal", "eligCount"
  ]
  static values = {
    url: String,
    csrf: String,
    eligibilityUrl: String,
    filteredTotal: Number,
    filtersJson: String
  }

  connect() {
    this._selectAllFiltered = false
    this.updateToolbar()
  }

  // --- Seleção ---

  // Checkbox individual alterado manualmente
  toggleOne() {
    // Sai do modo "todos filtrados" porque o usuário quer seleção pontual
    this._selectAllFiltered = false
    this.updateToolbar()
    this.syncMaster()
  }

  // Master checkbox alterado — marca TODOS os filtrados
  toggleAll(event) {
    const checked = event.currentTarget.checked
    this.itemTargets.forEach((el) => { el.checked = checked })
    this._selectAllFiltered = checked
    this.updateToolbar()
  }

  clearSelection() {
    this._selectAllFiltered = false
    this.itemTargets.forEach((el) => { el.checked = false })
    if (this.hasMasterTarget) {
      this.masterTarget.checked = false
      this.masterTarget.indeterminate = false
    }
    this.updateToolbar()
  }

  selectedVisibleIds() {
    return this.itemTargets.filter((el) => el.checked).map((el) => el.dataset.id)
  }

  effectiveCount() {
    if (this._selectAllFiltered && this.hasFilteredTotalValue) {
      return this.filteredTotalValue
    }
    return this.selectedVisibleIds().length
  }

  updateToolbar() {
    const count = this.effectiveCount()
    if (this.hasCountTarget) this.countTarget.textContent = count
    if (this.hasToolbarTarget) {
      this.toolbarTarget.hidden = count === 0
    }
  }

  syncMaster() {
    if (!this.hasMasterTarget) return
    const total = this.itemTargets.length
    const selected = this.selectedVisibleIds().length
    this.masterTarget.checked = total > 0 && selected === total
    this.masterTarget.indeterminate = selected > 0 && selected < total
  }

  // --- Modal ---

  openModal() {
    const count = this.effectiveCount()
    if (count === 0) {
      window.axToast({ message: "Selecione ao menos um imóvel.", type: "warning" })
      return
    }

    if (this.hasModalCountTarget) this.modalCountTarget.textContent = count
    if (this.hasEligTotalTarget) this.eligTotalTarget.textContent = count
    if (this.hasEligCountTarget) this.eligCountTarget.textContent = "—"

    this.resetForm()
    this.applyChannelVisibility()

    const modalEl = document.getElementById("bulkPublishModal")
    if (!modalEl) return
    modalEl.dispatchEvent(new CustomEvent("ax-modal:open"))
  }

  resetForm() {
    if (this.hasChannelSelectTarget) this.channelSelectTarget.value = ""
    this.actionRadioTargets.forEach((radio) => {
      radio.checked = (radio.value === "publicar")
    })
  }

  onChannelChange() {
    this.applyChannelVisibility()
    this.fetchEligibility()
  }

  onActionChange() {
    this.applyChannelVisibility()
    this.fetchEligibility()
  }

  currentChannel() {
    return this.hasChannelSelectTarget ? this.channelSelectTarget.value : ""
  }

  currentActionType() {
    const radio = this.actionRadioTargets.find((el) => el.checked)
    return radio ? radio.value : "publicar"
  }

  applyChannelVisibility() {
    if (!this.hasChannelOptionsWrapperTarget) return

    const channel = this.currentChannel()
    const action = this.currentActionType()
    const shouldShow = action === "publicar" && CHANNELS_WITH_OPTIONS.has(channel)

    this.channelOptionsWrapperTarget.hidden = !shouldShow

    const blocks = this.channelOptionsWrapperTarget.querySelectorAll(".channel-options-block")
    blocks.forEach((block) => {
      block.hidden = block.dataset.channel !== channel
    })
  }

  appendBulkParams(formData) {
    if (this._selectAllFiltered) {
      formData.append("select_all_filtered", "true")
      try {
        const filters = JSON.parse(this.filtersJsonValue || "{}")
        Object.entries(filters).forEach(([key, value]) => {
          if (Array.isArray(value)) {
            value.forEach((v) => formData.append(`filters[${key}][]`, v))
          } else if (value != null && value !== "") {
            formData.append(`filters[${key}]`, value)
          }
        })
      } catch (e) { /* ignore */ }
    } else {
      const ids = this.selectedVisibleIds()
      ids.forEach((id) => formData.append("selected_ids[]", id))
    }
  }

  async fetchEligibility() {
    if (!this.hasEligCountTarget) return

    const channel = this.currentChannel()
    const action = this.currentActionType()
    const count = this.effectiveCount()

    if (!channel || count === 0) {
      this.eligCountTarget.textContent = "—"
      return
    }

    this.eligCountTarget.textContent = "…"

    const formData = new FormData()
    this.appendBulkParams(formData)
    formData.append("channel", channel)
    formData.append("action_type", action)

    try {
      const response = await fetch(this.eligibilityUrlValue, {
        method: "POST",
        body: formData,
        headers: {
          "X-CSRF-Token": this.csrfValue,
          "Accept": "application/json"
        },
        credentials: "same-origin"
      })
      const data = await response.json().catch(() => ({}))
      if (response.ok) {
        this.eligCountTarget.textContent = data.eligible ?? "—"
      } else {
        this.eligCountTarget.textContent = "—"
      }
    } catch (_) {
      this.eligCountTarget.textContent = "—"
    }
  }

  // --- Submit ---

  async submit(event) {
    event.preventDefault()

    const count = this.effectiveCount()
    if (count === 0) {
      window.axToast({ message: "Selecione ao menos um imóvel.", type: "warning" })
      return
    }

    const channel = this.currentChannel()
    if (!channel) {
      window.axToast({ message: "Selecione um canal de divulgação.", type: "warning" })
      return
    }

    const form = document.getElementById("bulkPublishForm")
    if (!form) return

    const formData = new FormData(form)
    formData.delete("channel")
    formData.append("channels[]", channel)
    this.appendBulkParams(formData)

    const button = event.currentTarget
    const originalHTML = button.innerHTML
    button.disabled = true
    button.innerHTML = '<span class="ax-spinner" aria-hidden="true"></span> Processando...'

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        body: formData,
        headers: {
          "X-CSRF-Token": this.csrfValue,
          "Accept": "application/json"
        },
        credentials: "same-origin"
      })

      const data = await response.json().catch(() => ({}))

      if (response.ok) {
        const modalEl = document.getElementById("bulkPublishModal")
        modalEl.dispatchEvent(new CustomEvent("ax-modal:close"))
        window.axToast({ message: `${data.updated || count} imóvel(is) atualizado(s) com sucesso.`, type: "success" })
        setTimeout(() => window.location.reload(), 1200)
      } else {
        window.axToast({ message: `Erro: ${data.error || "Falha na requisição."}`, type: "danger" })
        button.disabled = false
        button.innerHTML = originalHTML
      }
    } catch (err) {
      window.axToast({ message: `Erro de conexão: ${err.message}`, type: "danger" })
      button.disabled = false
      button.innerHTML = originalHTML
    }
  }
}
