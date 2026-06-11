import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "propertyProgressValue",
    "propertiesWithPhotos",
    "totalProperties",
    "pendingProperties",
    "migratedImages",
    "imageProgress",
    "workerBadge",
    "workerPid",
    "executionPanel",
    "executionProgressBar",
    "executionProgressPercent",
    "executionLabel",
    "executionDetail",
    "executionStatus",
    "executionFailed",
    "executionRemaining",
    "executionPropertiesAdded",
    "executionImagesAdded",
    "summaryTotalProperties",
    "summaryPropertiesWithPhotos",
    "summaryPendingProperties",
    "summaryPublicPendingProperties",
    "summaryTotalSourceImages",
    "downloadedFileAssets",
    "pendingFileAssets",
    "summaryDownloadedFileAssets",
    "summaryPendingFileAssets",
    "failedProperties",
    "latestAttachmentAt",
    "syncButton",
    "retryButton"
  ]

  static values = {
    url: String,
    runningInterval: { type: Number, default: 2500 },
    idleInterval: { type: Number, default: 10000 }
  }

  connect() {
    this.refresh()
  }

  disconnect() {
    this.stop()
  }

  refresh() {
    if (!this.hasUrlValue || document.hidden) {
      this.schedule(this.idleIntervalValue)
      return
    }

    fetch(this.urlWithCacheBust(), { headers: { Accept: "application/json" } })
      .then((response) => {
        if (!response.ok) throw new Error("status_request_failed")
        return response.json()
      })
      .then((status) => {
        this.render(status)
        this.schedule(status.worker?.running ? this.runningIntervalValue : this.idleIntervalValue)
      })
      .catch(() => this.schedule(this.idleIntervalValue))
  }

  stop() {
    if (!this.timer) return

    clearTimeout(this.timer)
    this.timer = null
  }

  schedule(interval) {
    this.stop()
    this.timer = setTimeout(() => this.refresh(), interval)
  }

  render(status) {
    const execution = status.execution || {}

    this.setTextIfPresent("propertyProgressValue", this.percent(status.property_progress))
    this.setTextIfPresent("propertiesWithPhotos", this.integer(status.properties_with_photos))
    this.setTextIfPresent("totalProperties", this.integer(status.total_properties))
    this.setTextIfPresent("pendingProperties", this.integer(status.pending_properties))
    this.setTextIfPresent("migratedImages", this.integer(status.migrated_images))
    this.setTextIfPresent("imageProgress", this.percent(status.image_progress))

    this.renderWorker(status.worker || {})
    this.renderExecution(execution)
    this.renderSummary(status)
    this.renderControls(status)
  }

  renderWorker(worker) {
    if (this.hasWorkerBadgeTarget) {
      this.workerBadgeTarget.textContent = worker.status || "N/D"
      this.workerBadgeTarget.classList.toggle("bg-success", !!worker.running)
      this.workerBadgeTarget.classList.toggle("bg-secondary", !worker.running)
      this.workerBadgeTarget.classList.remove("bg-danger")
    }

    this.setTextIfPresent("workerPid", worker.pid ? `PID ${worker.pid}` : "Sem execução ativa")
  }

  renderExecution(execution) {
    const progress = Number(execution.progress || 0)
    this.setProgressIfPresent("executionProgressBar", progress)
    this.setTextIfPresent("executionProgressPercent", this.percent(progress))
    this.setTextIfPresent("executionLabel", execution.label || "Aguardando execução")
    this.setTextIfPresent("executionStatus", execution.running ? "Rodando" : "Parado")
    this.setTextIfPresent("executionFailed", this.integer(execution.failed || 0))
    this.setTextIfPresent("executionRemaining", this.integer(execution.remaining || 0))
    this.setTextIfPresent("executionPropertiesAdded", this.integer(execution.properties_added || 0))
    this.setTextIfPresent("executionImagesAdded", this.integer(execution.images_added || 0))

    const current = this.integer(execution.current || 0)
    const total = this.integer(execution.total || 0)
    this.setTextIfPresent("executionDetail", `${current} de ${total}`)

    if (this.hasExecutionProgressBarTarget) {
      this.executionProgressBarTarget.classList.toggle("progress-bar-animated", !!execution.running)
      this.executionProgressBarTarget.classList.toggle("progress-bar-striped", !!execution.running)
    }
  }

  renderSummary(status) {
    this.setTextIfPresent("summaryTotalProperties", this.integer(status.total_properties))
    this.setTextIfPresent("summaryPropertiesWithPhotos", this.integer(status.properties_with_photos))
    this.setTextIfPresent("summaryPendingProperties", this.integer(status.pending_properties))
    this.setTextIfPresent("summaryPublicPendingProperties", this.integer(status.public_pending_properties))
    this.setTextIfPresent("summaryTotalSourceImages", this.integer(status.total_source_images))
    this.setTextIfPresent("downloadedFileAssets", this.integer(status.downloaded_file_assets))
    this.setTextIfPresent("pendingFileAssets", this.integer(status.pending_file_assets))
    this.setTextIfPresent("summaryDownloadedFileAssets", this.integer(status.downloaded_file_assets))
    this.setTextIfPresent("summaryPendingFileAssets", this.integer(status.pending_file_assets))
    this.setTextIfPresent("failedProperties", this.integer(status.failed_properties))
    this.setTextIfPresent("latestAttachmentAt", this.dateTime(status.latest_attachment_at) || "N/D")
  }

  renderControls(status) {
    const running = !!status.worker?.running

    if (this.hasSyncButtonTarget) this.syncButtonTarget.disabled = running
    if (this.hasRetryButtonTarget) this.retryButtonTarget.disabled = running || Number(status.failed_properties || 0) === 0
  }

  setText(target, value) {
    if (!target) return
    target.textContent = value
  }

  setProgress(target, value) {
    if (!target) return

    const progress = Math.max(0, Math.min(100, Number(value || 0)))
    target.style.width = `${progress}%`
    target.setAttribute("aria-valuenow", progress.toString())
  }

  setTextIfPresent(name, value) {
    if (!this[`has${this.capitalize(name)}Target`]) return

    this.setText(this[`${name}Target`], value)
  }

  setProgressIfPresent(name, value) {
    if (!this[`has${this.capitalize(name)}Target`]) return

    this.setProgress(this[`${name}Target`], value)
  }

  capitalize(value) {
    return value.charAt(0).toUpperCase() + value.slice(1)
  }

  integer(value) {
    return new Intl.NumberFormat("pt-BR").format(Number(value || 0))
  }

  percent(value) {
    return `${new Intl.NumberFormat("pt-BR", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    }).format(Number(value || 0))}%`
  }

  dateTime(value) {
    if (!value) return null

    const date = new Date(value)
    if (Number.isNaN(date.getTime())) return null

    return date.toLocaleString("pt-BR", {
      day: "2-digit",
      month: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    })
  }

  urlWithCacheBust() {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("_ts", Date.now().toString())
    return url.toString()
  }
}
