import { Controller } from "@hotwired/stimulus"

// Exportação assíncrona de imóveis (CSV): envia o pedido, mostra progresso e lista
// as últimas exportações (baixar / excluir). Convive com o controller ax-modal.
export default class extends Controller {
  static targets = ["form", "list", "progress", "progressBar", "progressLabel", "submit"]
  static values = { listUrl: String }

  connect() {
    this.exports = []
    this.trackedExportId = null
    this.onOpen = () => this.loadList()
    this.element.addEventListener("ax-modal:opened", this.onOpen)
  }

  disconnect() {
    this.element.removeEventListener("ax-modal:opened", this.onOpen)
    this.clearPoll()
  }

  get csrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  // Envia o formulário (POST) sem recarregar a página.
  async submit(event) {
    event.preventDefault()
    this.setSubmitting(true)
    this.showProgress(0, "Enviando pedido…")
    try {
      const resp = await fetch(this.formTarget.action, {
        method: "POST",
        headers: { "X-CSRF-Token": this.csrf, Accept: "application/json" },
        body: new FormData(this.formTarget)
      })
      if (!resp.ok) throw new Error("Falha ao iniciar a exportação.")
      const data = await resp.json()
      this.trackedExportId = data.id
      this.upsertExport(data)
      this.showProgress(data.progress || 0, "Gerando o CSV…")
      this.scheduleRefresh()
    } catch (e) {
      this.showError(e.message)
      this.setSubmitting(false)
    }
  }

  poll(id) {
    this.trackedExportId = id
    this.scheduleRefresh(0)
  }

  async loadList() {
    if (!this.hasListTarget) return
    this.clearPoll()
    try {
      const resp = await fetch(this.listUrlValue, { headers: { Accept: "application/json" } })
      if (!resp.ok) throw new Error("Falha ao carregar exportações.")
      const data = await resp.json()
      this.exports = data.exports || []
      this.renderList(this.exports)
      this.handleTrackedExport(this.exports.find((item) => String(item.id) === String(this.trackedExportId)))
      if (this.exports.some((item) => this.processing(item))) this.scheduleRefresh()
    } catch (_e) { /* silencioso */ }
  }

  async destroy(event) {
    event.preventDefault()
    const id = event.currentTarget.dataset.id
    if (!id) return
    event.currentTarget.disabled = true
    await fetch(`${this.listUrlValue}/${id}`, {
      method: "DELETE",
      headers: { "X-CSRF-Token": this.csrf, Accept: "application/json" }
    })
    this.loadList()
  }

  upsertExport(data) {
    if (!data?.id) return

    this.exports = [
      data,
      ...this.exports.filter((item) => String(item.id) !== String(data.id))
    ].slice(0, 5)
    this.renderList(this.exports)
  }

  renderList(exports) {
    if (!exports.length) {
      this.listTarget.innerHTML = ""
      return
    }
    const rows = exports.map((e) => {
      const progress = Number(e.progress) || 0
      const badge = e.status === "completed"
        ? '<span class="ax-badge ax-badge--green ax-badge--dot">Pronto</span>'
        : e.status === "failed"
          ? '<span class="ax-badge ax-badge--red ax-badge--dot">Falhou</span>'
          : `<span class="ax-badge ax-badge--amber ax-badge--dot">${progress}%</span>`
      const download = e.ready
        ? `<a class="ax-icon-btn" href="${this.escapeHtml(e.download_url)}" title="Baixar" download="${this.escapeHtml(e.filename)}" data-controller="ax-async-download" data-action="ax-async-download#download" data-turbo="false" data-admin-navigation-ignore="true" data-ax-async-download-accept-value="text/csv,*/*"><i class="bi bi-download"></i></a>`
        : ""
      return `
        <div class="habitations-export-recent-item tw-flex tw-items-center tw-gap-2 tw-py-2">
          <i class="bi bi-filetype-csv habitations-export-recent-item__icon"></i>
          <div class="tw-flex-1 habitations-export-recent-item__content">
            <div class="tw-text-sm tw-font-semibold habitations-export-recent-item__filename">${this.escapeHtml(e.filename)}</div>
            <div class="tw-text-xs tw-text-ink-muted">${this.escapeHtml(e.record_count)} imóveis · ${this.escapeHtml(e.created_at)}</div>
          </div>
          ${badge}
          ${download}
          <button type="button" class="ax-icon-btn" title="Excluir" data-id="${this.escapeHtml(e.id)}" data-action="habitation-export#destroy"><i class="bi bi-x-lg"></i></button>
        </div>`
    }).join("")
    this.listTarget.innerHTML = `<div class="ax-label tw-mb-1">Exportações recentes</div>${rows}`
  }

  handleTrackedExport(data) {
    if (!this.trackedExportId) return

    if (!data) {
      this.hideProgress()
      this.setSubmitting(false)
      this.trackedExportId = null
      return
    }

    if (data.status === "completed") {
      this.hideProgress()
      this.setSubmitting(false)
      this.trackedExportId = null
    } else if (data.status === "failed") {
      this.showError(data.error || "Falha ao gerar o CSV.")
      this.setSubmitting(false)
      this.trackedExportId = null
    } else {
      this.showProgress(data.progress || 0, "Gerando o CSV…")
    }
  }

  processing(exportItem) {
    return ["pending", "processing"].includes(exportItem?.status)
  }

  scheduleRefresh(delay = 1200) {
    this.clearPoll()
    this.pollTimer = setTimeout(() => this.loadList(), delay)
  }

  clearPoll() {
    if (this.pollTimer) clearTimeout(this.pollTimer)
    this.pollTimer = null
  }

  escapeHtml(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
  }

  showProgress(pct, label) {
    if (!this.hasProgressTarget) return
    this.progressTarget.hidden = false
    if (this.hasProgressBarTarget) {
      const progress = Math.min(Math.max(Number(pct) || 0, 0), 100)
      this.progressBarTarget.value = progress
      this.progressBarTarget.textContent = `${progress}%`
      this.progressBarTarget.setAttribute("aria-label", `Progresso da exportação: ${progress}%`)
    }
    if (this.hasProgressLabelTarget) this.progressLabelTarget.textContent = label
  }

  hideProgress() {
    if (this.hasProgressTarget) this.progressTarget.hidden = true
  }

  showError(message) {
    this.showProgress(0, `Erro: ${message}`)
  }

  setSubmitting(on) {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = on
      this.submitTarget.textContent = on ? "Gerando…" : "Exportar"
    }
  }
}
