import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["query", "micButton", "recordingState", "timer", "recordBars", "pauseButton", "submitButton", "status", "processing", "processingText", "confirmation", "filterChips", "results", "newSearch", "selectionBar", "selectionCount", "previewDialog", "previewBody", "previewTitle"]
  static values = { createUrl: String, selectUrl: String, shareUrl: String, maxDuration: Number, processingMessage: String, selectionMessage: String, shareErrorMessage: String, linkCopiedMessage: String, autoStart: Boolean }

  connect() {
    this.resetRecordingState()
    this.pendingFilters = null
    this.transcription = null
    this.currentFilters = {}
    this.selectedIds = new Set()
    this.previewCloseHandler = () => document.documentElement.classList.remove("field-preview-open")
    if (this.hasPreviewDialogTarget) this.previewDialogTarget.addEventListener("close", this.previewCloseHandler)
    if (this.autoStartValue && this.hasMicButtonTarget) window.requestAnimationFrame(() => this.startRecording())
  }

  disconnect() {
    this.discardNext = true
    this.stopRecording()
    this.stopTracks()
    this.stopWaveform()
    this.closePreview()
    if (this.hasPreviewDialogTarget && this.previewCloseHandler) this.previewDialogTarget.removeEventListener("close", this.previewCloseHandler)
  }

  async startRecording() {
    if (this.recording || this.loading) return
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined") return this.showError("Gravação de áudio não é suportada neste aparelho.")

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      const mimeType = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4", "audio/ogg;codecs=opus"].find((type) => MediaRecorder.isTypeSupported(type))
      this.recorder = new MediaRecorder(this.stream, mimeType ? { mimeType } : undefined)
      this.chunks = []
      this.discardNext = false
      this.sendAfterStop = false
      this.recording = true
      this.recordPaused = false
      this.recordedSeconds = 0
      this.startedAt = Date.now()
      this.pausedElapsedMs = 0
      this.recorder.addEventListener("dataavailable", (event) => { if (event.data.size) this.chunks.push(event.data) })
      this.recorder.addEventListener("stop", () => this.finishRecording())
      this.recorder.start(250)
      this.element.classList.add("is-recording")
      this.recordingStateTarget.hidden = false
      this.statusTarget.hidden = true
      this.startWaveform(this.stream)
      this.timerId = window.setInterval(() => this.updateRecordingTimer(), 250)
      this.updateRecordingTimer()
    } catch (_) {
      this.showError("Não foi possível acessar o microfone. Verifique a permissão do navegador.")
    }
  }

  sendRecording() {
    if (!this.recording) return
    this.sendAfterStop = true
    this.stopRecording()
  }

  discardRecording() {
    this.discardNext = true
    this.stopRecording()
  }

  togglePauseRecording() {
    if (!this.recorder || typeof this.recorder.pause !== "function") return
    if (this.recorder.state === "paused") {
      this.recorder.resume()
      this.recordPaused = false
      this.startedAt = Date.now()
    } else if (this.recorder.state === "recording") {
      this.recorder.pause()
      this.recordPaused = true
      this.pausedElapsedMs += Date.now() - this.startedAt
    }
    this.element.classList.toggle("is-recording-paused", this.recordPaused)
    const icon = this.pauseButtonTarget.querySelector("i")
    if (icon) icon.className = this.recordPaused ? "bi bi-mic-fill" : "bi bi-pause-fill"
    this.pauseButtonTarget.setAttribute("aria-label", this.recordPaused ? "Continuar gravação" : "Pausar gravação")
  }

  stopRecording() {
    if (this.recorder?.state === "recording" || this.recorder?.state === "paused") this.recorder.stop()
  }

  finishRecording() {
    window.clearInterval(this.timerId)
    this.stopWaveform()
    this.stopTracks()
    const type = (this.recorder?.mimeType || "audio/webm").split(";")[0]
    const blob = new Blob(this.chunks, { type })
    const shouldSend = this.sendAfterStop && !this.discardNext && blob.size >= 100
    this.audioBlob = shouldSend ? blob : null
    this.recorder = null
    this.recording = false
    this.recordPaused = false
    this.element.classList.remove("is-recording", "is-recording-paused")
    this.recordingStateTarget.hidden = true
    if (shouldSend) requestAnimationFrame(() => this.submit(false))
    else this.resetRecordingState()
  }

  updateRecordingTimer() {
    const elapsedMs = this.pausedElapsedMs + (this.recordPaused ? 0 : Date.now() - this.startedAt)
    this.recordedSeconds = Math.max(0, Math.floor(elapsedMs / 1000))
    this.timerTarget.textContent = `${Math.floor(this.recordedSeconds / 60)}:${String(this.recordedSeconds % 60).padStart(2, "0")}`
    if (this.recordedSeconds >= this.maxDurationValue) this.sendRecording()
  }

  startWaveform(stream) {
    if (!this.hasRecordBarsTarget) return
    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    this.recordBarsTarget.replaceChildren(...Array.from({ length: 30 }, () => document.createElement("i")))
    if (!AudioContextClass) return
    try {
      this.audioContext = new AudioContextClass()
      this.analyser = this.audioContext.createAnalyser()
      this.analyser.fftSize = 256
      this.audioContext.createMediaStreamSource(stream).connect(this.analyser)
      this.waveSamples = new Uint8Array(this.analyser.fftSize)
      this.waveHistory = []
      this.waveTimer = window.setInterval(() => this.sampleWave(), 100)
    } catch (_) { /* a gravação continua sem waveform */ }
  }

  sampleWave() {
    if (!this.analyser || this.recordPaused) return
    this.analyser.getByteTimeDomainData(this.waveSamples)
    let sum = 0
    this.waveSamples.forEach((sample) => { const value = (sample - 128) / 128; sum += value * value })
    this.waveHistory.push(Math.min(1, Math.sqrt(sum / this.waveSamples.length) * 3.4))
    if (this.waveHistory.length > 30) this.waveHistory.shift()
    const bars = this.recordBarsTarget.querySelectorAll("i")
    const offset = bars.length - this.waveHistory.length
    bars.forEach((bar, index) => { const value = index < offset ? 0 : this.waveHistory[index - offset]; bar.style.height = `${Math.max(4, Math.round(value * 25))}px` })
  }

  stopWaveform() {
    window.clearInterval(this.waveTimer)
    this.waveTimer = null
    this.analyser = null
    this.audioContext?.close?.().catch?.(() => {})
    this.audioContext = null
  }

  search() { this.submit(false) }
  confirmSearch() { this.submit(true) }

  async submit(confirmed) {
    const query = this.queryTarget.value.trim()
    if (!confirmed && !query && !this.audioBlob) return this.showError("Digite uma busca ou toque no microfone para gravar.")
    const body = new FormData()
    body.append("query", confirmed ? this.transcription : query)
    body.append("current_filters", JSON.stringify(this.currentFilters || {}))
    if (!confirmed && this.audioBlob) {
      const extension = this.audioBlob.type.includes("mp4") ? "m4a" : this.audioBlob.type.includes("ogg") ? "ogg" : "webm"
      body.append("audio", this.audioBlob, `busca.${extension}`)
      body.append("audio_duration_seconds", Math.max(1, this.recordedSeconds))
    }
    if (confirmed) {
      body.append("confirmed", "1")
      body.append("filters", JSON.stringify(this.pendingFilters || {}))
    }

    this.setLoading(true, this.audioBlob ? "Enviando e interpretando seu áudio…" : this.processingMessageValue)
    try {
      const response = await fetch(this.createUrlValue, { method: "POST", headers: { "X-CSRF-Token": this.csrfToken, Accept: "application/json" }, body })
      const payload = await response.json()
      if (!response.ok) throw new Error(payload.error || "Falha ao buscar imóveis.")
      this.audioBlob = null
      this.handleResponse(payload)
    } catch (error) { this.showError(error.message) }
    finally { this.setLoading(false) }
  }

  handleResponse(payload) {
    this.transcription = payload.transcription || this.queryTarget.value
    this.queryTarget.value = this.transcription
    if (payload.status === "clarification_required") {
      if (payload.development_options?.length) return this.renderDevelopmentOptions(payload)
      return this.showError(payload.question)
    }
    if (payload.status === "confirmation_required") {
      this.pendingFilters = payload.filters
      this.filterChipsTarget.replaceChildren(...Object.entries(payload.filters).map(([key, value]) => this.chip(`${key}: ${Array(value).join(", ")}`)))
      this.confirmationTarget.hidden = false
      this.showStatus("Confira os filtros que entendi antes de buscar.")
      return
    }
    this.confirmationTarget.hidden = true
    this.currentFilters = payload.filters || {}
    if (this.hasNewSearchTarget) this.newSearchTarget.hidden = false
    this.renderResults(payload)
  }

  newSearch() {
    this.currentFilters = {}
    this.transcription = null
    this.queryTarget.value = ""
    this.resultsTarget.replaceChildren()
    this.selectedIds.clear(); this.syncSelectionBar()
    this.statusTarget.hidden = true
    this.newSearchTarget.hidden = true
    this.queryTarget.focus()
  }

  renderResults(payload) {
    this.resultsTarget.replaceChildren()
    const corrections = this.locationCorrectionsMessage(payload)
    const hasExact = Boolean(payload.results?.length)
    const hasApproximate = Boolean(payload.suggestions?.length)

    if (!hasExact && !hasApproximate) {
      return this.showError(payload.no_results_message || "Nenhum imóvel encontrado, mesmo após ampliar os critérios de forma segura.")
    }

    let status
    if (hasExact) {
      status = payload.flexible ? "Não houve correspondência exata; exibimos opções dentro da margem configurada." : `${payload.results.length} imóvel(is) encontrado(s).`
    } else {
      status = payload.suggestion_message || "Não houve correspondência exata. Encontramos estas opções próximas ao que você pediu."
    }
    this.showStatus(corrections ? `${corrections} ${status}` : status)

    if (hasExact) {
      if (hasApproximate) this.resultsTarget.append(this.resultsHeading("Resultados exatos"))
      payload.results.forEach((property) => this.resultsTarget.append(this.resultCard(property, payload.history_id)))
    }
    if (hasApproximate) {
      this.resultsTarget.append(this.resultsHeading("Opções próximas"))
      if (payload.relaxed_labels?.length) this.resultsTarget.append(this.relaxedChips(payload.relaxed_labels))
      payload.suggestions.forEach((property) => this.resultsTarget.append(this.resultCard(property, payload.history_id, true)))
    }
  }

  locationCorrectionsMessage(payload) {
    const corrections = payload.location_corrections || []
    if (!corrections.length) return ""
    return corrections.map((correction) => `Entendi «${correction.from}» como «${correction.to}».`).join(" ")
  }

  resultsHeading(content) {
    const heading = document.createElement("h3")
    heading.className = "field-ai-results-heading"
    heading.textContent = content
    return heading
  }

  relaxedChips(labels) {
    const list = document.createElement("div")
    list.className = "field-ai-relaxed-chips"
    labels.forEach((label) => {
      const chip = this.chip(label)
      chip.className = "field-ai-relaxed-chip"
      list.append(chip)
    })
    return list
  }

  renderDevelopmentOptions(payload) {
    this.showStatus(payload.question)
    this.resultsTarget.replaceChildren()
    payload.development_options.forEach((development) => {
      const button = document.createElement("button"); button.type = "button"; button.className = "field-ai-development-option"
      const location = [development.neighborhood, development.city].filter(Boolean).join(" · ")
      button.append(this.text("strong", development.name))
      if (development.developer_name) button.append(this.text("small", development.developer_name))
      if (location) button.append(this.text("small", location))
      button.addEventListener("click", () => { this.pendingFilters = { ...(payload.filters || {}), development_name: development.name }; this.transcription = payload.transcription || this.queryTarget.value; this.submit(true) })
      this.resultsTarget.append(button)
    })
  }

  resultCard(property, historyId, approximate = false) {
    const wrapper = document.createElement("div"); wrapper.className = approximate ? "field-ai-property-choice field-ai-property-choice--approximate" : "field-ai-property-choice"
    const select = document.createElement("button"); select.type = "button"; select.className = "field-ai-property-choice__select"; select.setAttribute("aria-label", "Selecionar imóvel"); select.innerHTML = '<i class="bi bi-check-lg"></i>'
    select.addEventListener("click", () => { this.selectedIds.has(property.id) ? this.selectedIds.delete(property.id) : this.selectedIds.add(property.id); wrapper.classList.toggle("is-selected", this.selectedIds.has(property.id)); this.syncSelectionBar() })
    const link = document.createElement("a"); link.className = "field-ai-property-card"; link.href = property.path
    link.dataset.previewUrl = property.preview_path || property.path
    const cardTitle = property.card_title || property.title || property.property_code || "Imóvel"
    link.dataset.propertyTitle = cardTitle
    link.addEventListener("click", (event) => this.openPreview(event, historyId, property.id))
    if (property.cover_image) { const image = document.createElement("img"); image.src = property.cover_image; image.alt = cardTitle; image.loading = "lazy"; link.append(image) }
    const body = document.createElement("span"); body.className = "field-ai-property-card__body"
    const title = document.createElement("strong"); title.textContent = cardTitle; body.append(title)
    const location = [property.neighborhood, property.city].filter(Boolean).join(" · "); if (location) body.append(this.text("small", location))
    const facts = [property.bedrooms && `${property.bedrooms} qtos`, property.suites && `${property.suites} suítes`, property.parking_spaces && `${property.parking_spaces} vagas`, property.private_area && `${property.private_area} m²`].filter(Boolean).join(" · "); if (facts) body.append(this.text("small", facts))
    if (property.price) body.append(this.text("b", new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(property.price)))
    link.append(body)
    if (approximate) { const badge = document.createElement("span"); badge.className = "field-ai-property-choice__badge"; badge.textContent = "aproximado"; wrapper.append(badge) }
    wrapper.append(select, link); return wrapper
  }

  syncSelectionBar() { this.selectionCountTarget.textContent = this.selectionMessageValue.replace("%{count}", this.selectedIds.size); this.selectionBarTarget.hidden = this.selectedIds.size === 0 }

  async shareSelection() {
    const body = new FormData(); this.selectedIds.forEach((id) => body.append("habitation_ids[]", id))
    const response = await fetch(this.shareUrlValue, { method: "POST", headers: { "X-CSRF-Token": this.csrfToken, Accept: "application/json" }, body })
    const payload = await response.json(); if (!response.ok) return this.showError(payload.error || this.shareErrorMessageValue)
    const data = { title: payload.share_title, text: payload.share_message, url: payload.url }
    if (navigator.share) await navigator.share(data).catch(() => {})
    else { await navigator.clipboard.writeText(payload.url); this.showStatus(this.linkCopiedMessageValue) }
  }

  recordSelection(historyId, habitationId) {
    if (!historyId) return
    const body = new FormData(); body.append("history_id", historyId); body.append("habitation_id", habitationId)
    fetch(this.selectUrlValue, { method: "POST", headers: { "X-CSRF-Token": this.csrfToken, Accept: "application/json" }, body, keepalive: true }).catch(() => {})
  }

  async openPreview(event, historyId, habitationId) {
    event.preventDefault()
    const link = event.currentTarget
    this.recordSelection(historyId, habitationId)
    if (!this.hasPreviewDialogTarget || !this.hasPreviewBodyTarget) {
      window.location.href = link.href
      return
    }

    this.previewTitleTarget.textContent = link.dataset.propertyTitle || "Detalhes do imóvel"
    this.previewBodyTarget.innerHTML = '<div class="field-property-preview__loading">Carregando detalhes...</div>'
    if (!this.previewDialogTarget.open) this.previewDialogTarget.showModal()
    document.documentElement.classList.add("field-preview-open")

    try {
      const response = await fetch(link.dataset.previewUrl || link.href, { headers: { Accept: "text/html" } })
      if (!response.ok) throw new Error("Falha ao carregar detalhes.")
      this.previewBodyTarget.innerHTML = await response.text()
    } catch (error) {
      this.previewBodyTarget.innerHTML = `<div class="field-property-preview__error">${error.message}</div>`
    }
  }

  closePreview() {
    if (!this.hasPreviewDialogTarget || !this.previewDialogTarget.open) return

    this.previewDialogTarget.close()
    document.documentElement.classList.remove("field-preview-open")
  }

  resetRecordingState() { this.recording = false; this.recordPaused = false; this.audioBlob = null; this.recordedSeconds = 0; this.pausedElapsedMs = 0; this.discardNext = false; this.sendAfterStop = false }
  chip(content) { const span = document.createElement("span"); span.textContent = content; return span }
  text(tag, content) { const node = document.createElement(tag); node.textContent = content; return node }
  setLoading(active, message = "") { this.loading = active; this.submitButtonTarget.disabled = active; this.processingTarget.hidden = !active; this.processingTextTarget.textContent = message; this.element.classList.toggle("is-processing", active) }
  showStatus(message) { this.statusTarget.textContent = message; this.statusTarget.hidden = !message; this.statusTarget.classList.remove("is-error") }
  showError(message) { this.processingTarget.hidden = true; this.statusTarget.textContent = message; this.statusTarget.hidden = false; this.statusTarget.classList.add("is-error") }
  stopTracks() { this.stream?.getTracks().forEach((track) => track.stop()); this.stream = null }
  get csrfToken() { return document.querySelector("meta[name='csrf-token']")?.content || "" }
}
