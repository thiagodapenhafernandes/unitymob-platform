import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body", "fileInput", "fileSummary", "fileName", "template", "modeLabel", "error", "submit", "presentationCard", "recordingBar", "recordTime", "recordPause", "recordPreview", "recordBars", "replyTo", "replyBar", "replyAuthor", "replySnippet"]

  connect() {
    this.submitting = false
    this.recording = false
    this.recorder = null
    this.recordChunks = []
    this.successTimer = null
    this.pendingMessageId = null
    this.optimisticObjectUrls = new Map()
    this.refreshState()
  }

  disconnect() {
    if (this.successTimer) clearTimeout(this.successTimer)
    if (this.recordTimer) clearInterval(this.recordTimer)
    if (this.waveTimer) clearInterval(this.waveTimer)
    if (this.recorder?.state === "recording" || this.recorder?.state === "paused") this.recorder.stop()
    this.revokeAllOptimisticObjectUrls()
  }

  fileChanged() {
    const file = this.fileInputTarget.files[0]
    if (!file) {
      this.hideSummary()
      this.refreshState()
      return
    }

    const rejection = this.mediaRejection(file)
    if (rejection) {
      this.clearFile()
      this.showError(rejection)
      return
    }

    this.hideError()
    if (this.hasTemplateTarget) this.templateTarget.value = ""
    this.fileNameTarget.textContent = `${this.fileKind(file)} · ${file.name} · ${this.humanSize(file.size)}`
    this.fileSummaryTarget.classList.remove("is-hidden")
    this.refreshState()
  }

  clearFile() {
    this.fileInputTarget.value = ""
    this.hideSummary()
    this.refreshState()
  }

  templateChanged() {
    if (!this.hasTemplateTarget) return

    if (this.templateTarget.value) {
      this.clearFile()
      this.bodyTarget.value = ""
      this.bodyTarget.disabled = true
      this.bodyTarget.placeholder = "Modelos aprovados são enviados sem texto livre adicional"
    } else {
      this.bodyTarget.disabled = false
      this.bodyTarget.placeholder = "Escreva uma mensagem..."
    }

    this.refreshState()
  }

  bodyChanged() {
    this.hideError()
    // Corretor limpou o texto → a apresentação preenchida deixa de valer.
    if (this.hasPresentationCardTarget && this.bodyTarget.value.trim() === "") {
      this.presentationCardTarget.value = ""
    }
    this.refreshState()
  }

  // Menu "Responder" da bolha: arma a citação e foca o campo
  setReply(event) {
    const { id, author, snippet } = event.detail || {}
    if (!id) return

    if (this.hasReplyToTarget) this.replyToTarget.value = id
    if (this.hasReplyAuthorTarget) this.replyAuthorTarget.textContent = author || ""
    if (this.hasReplySnippetTarget) this.replySnippetTarget.textContent = snippet || ""
    if (this.hasReplyBarTarget) this.replyBarTarget.classList.remove("is-hidden")
    this.bodyTarget.focus()
  }

  clearReply() {
    if (this.hasReplyToTarget) this.replyToTarget.value = ""
    if (this.hasReplyBarTarget) this.replyBarTarget.classList.add("is-hidden")
  }

  // Preenche o composer com um cartão de apresentação (evento do
  // presentation-picker). NÃO envia: o corretor revisa e usa o Enviar normal.
  fillPresentation(event) {
    const { cardId, body } = event.detail || {}
    if (!body) return

    if (this.hasTemplateTarget) this.templateTarget.value = ""
    this.bodyTarget.disabled = false
    this.bodyTarget.value = body
    if (this.hasPresentationCardTarget) this.presentationCardTarget.value = cardId || ""
    this.bodyChanged()
    this.bodyTarget.focus()
  }

  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey) return
    if (event.isComposing) return

    event.preventDefault()
    if (!this.hasContentToSend()) return

    this.element.requestSubmit()
  }

  hasContentToSend() {
    const hasTemplate = this.hasTemplateTarget && this.templateTarget.value.length > 0
    const hasFile = this.fileInputTarget.files.length > 0
    const hasBody = this.bodyTarget.value.trim().length > 0

    return hasTemplate || hasFile || hasBody
  }

  async submit(event) {
    event.preventDefault()

    if (this.recording) {
      // ➤ durante a gravação = parar e enviar direto (estilo WhatsApp)
      this.autoSendAfterRecording = true
      this.stopRecording()
      return
    }

    const mode = this.hasSubmitTarget ? this.submitTarget.dataset.mode : "send"
    if (mode === "mic") {
      this.startRecording()
      return
    }

    if (this.submitting) return

    if (this.successTimer) clearTimeout(this.successTimer)
    this.hideError()
    this.submitting = true
    const optimisticPayload = this.buildOptimisticPayload()
    if (optimisticPayload) {
      this.pendingMessageId = optimisticPayload.tempId
      window.dispatchEvent(new CustomEvent("wa:message-submitting", { detail: optimisticPayload }))
    }
    this.refreshState()

    try {
      const response = await fetch(this.element.action, {
        method: this.element.method || "POST",
        body: new FormData(this.element),
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        credentials: "same-origin"
      })

      const payload = await response.json().catch(() => ({}))
      if (!response.ok || payload.ok === false) {
        this.showError(payload.error || "Nao foi possivel enviar a mensagem.")
        this.dispatchFailedMessage()
        return
      }

      this.showSuccessState(payload)
      window.dispatchEvent(new CustomEvent("wa:message-sent", {
        detail: { ...payload, tempId: this.pendingMessageId }
      }))
      this.revokeOptimisticObjectUrl(this.pendingMessageId)
      this.resetForm()
    } catch (_error) {
      this.showError("Nao foi possivel enviar a mensagem.")
      this.dispatchFailedMessage()
    } finally {
      this.submitting = false
      this.pendingMessageId = null
      this.refreshState()
    }
  }

  hideSummary() {
    if (!this.hasFileSummaryTarget) return

    this.fileSummaryTarget.classList.add("is-hidden")
    if (this.hasFileNameTarget) this.fileNameTarget.textContent = "Nenhum arquivo"
  }

  refreshState() {
    const hasTemplate = this.hasTemplateTarget && this.templateTarget.value.length > 0
    const hasFile = this.fileInputTarget.files.length > 0
    const hasBody = this.bodyTarget.value.trim().length > 0

    if (!hasTemplate && this.bodyTarget.disabled) {
      this.bodyTarget.disabled = false
      this.bodyTarget.placeholder = "Escreva uma mensagem..."
    }

    if (this.hasModeLabelTarget) {
      this.modeLabelTarget.textContent = this.submitting
        ? "Enviando..."
        : hasTemplate
          ? "Modelo aprovado"
          : hasFile
            ? `${this.fileKind(this.fileInputTarget.files[0])} com legenda`
            : "Mensagem livre"
    }

    if (this.hasSubmitTarget) {
      const canSend = hasTemplate || hasFile || hasBody
      const mode = this.recording || canSend ? "send" : "mic"
      this.submitTarget.dataset.mode = mode
      this.submitTarget.disabled = this.submitting
      this.submitTarget.classList.toggle("is-loading", this.submitting)

      const icon = this.submitTarget.querySelector("i")
      if (icon) {
        icon.className = mode === "mic" ? "bi bi-mic-fill ax-ico" : "bi bi-send-fill ax-ico"
      }

      const label = this.recording ? "Enviar áudio" : mode === "mic" ? "Gravar áudio" : "Enviar mensagem"
      this.submitTarget.title = label
      this.submitTarget.setAttribute("aria-label", label)
    }
  }

  // ===== Gravação de voz (estilo WhatsApp): grava, anexa e o corretor revisa =====
  async startRecording() {
    if (this.recording) return

    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined") {
      // sem suporte: cai no seletor de arquivo de áudio
      this.fileInputTarget.setAttribute("accept", "audio/aac,audio/amr,audio/mpeg,audio/mp4,audio/ogg")
      this.fileInputTarget.click()
      return
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      const mime = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4"]
        .find((type) => MediaRecorder.isTypeSupported(type))
      this.recorder = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined)
      this.recordChunks = []
      this.recorder.addEventListener("dataavailable", (e) => { if (e.data.size) this.recordChunks.push(e.data) })
      this.recorder.addEventListener("stop", () => this.finishRecording())
      this.recorder.start()
      this.recording = true
      this.discardNext = false
      this.autoSendAfterRecording = false
      this.recordElapsedMs = 0
      this.recordResumedAt = Date.now()
      this.recordPaused = false
      this.recordTimer = setInterval(() => this.updateRecordingTimer(), 250)
      this.bodyTarget.disabled = true
      this.element.classList.add("is-recording-mode")
      if (this.hasRecordPauseTarget) {
        this.recordPauseTarget.hidden = typeof this.recorder.pause !== "function"
        this.setPauseIcon(false)
      }
      if (this.hasRecordPreviewTarget) this.recordPreviewTarget.hidden = true
      this.startWaveform(stream)
      this.hideError()
      this.updateRecordingTimer()
      this.refreshState()
    } catch (_error) {
      this.showError("Não foi possível acessar o microfone. Verifique a permissão do navegador.")
    }
  }

  stopRecording() {
    if (!this.recorder) return
    if (this.recorder.state === "recording" || this.recorder.state === "paused") this.recorder.stop()
  }

  discardRecording() {
    this.discardNext = true
    this.stopRecording()
  }

  togglePauseRecording() {
    if (!this.recorder || typeof this.recorder.pause !== "function") return

    if (this.recorder.state === "paused") {
      this.stopPreview()
      this.recorder.resume()
      this.recordPaused = false
      this.recordResumedAt = Date.now()
    } else if (this.recorder.state === "recording") {
      this.recorder.pause()
      this.recorder.requestData() // libera os chunks para a pré-escuta
      this.recordPaused = true
      this.recordElapsedMs += Date.now() - this.recordResumedAt
    }

    if (this.hasRecordPreviewTarget) this.recordPreviewTarget.hidden = !this.recordPaused
    this.element.classList.toggle("is-recording-paused", this.recordPaused)
    this.setPauseIcon(this.recordPaused)
  }

  setPauseIcon(paused) {
    if (!this.hasRecordPauseTarget) return

    // pausado: 🎤 deixa claro que o botão CONTINUA A GRAVAÇÃO (ouvir é o ▶ ao lado)
    const icon = this.recordPauseTarget.querySelector("i")
    if (icon) icon.className = paused ? "bi bi-mic-fill" : "bi bi-pause-fill"
    const label = paused ? "Continuar gravando" : "Pausar gravação"
    this.recordPauseTarget.title = label
    this.recordPauseTarget.setAttribute("aria-label", label)
  }

  // ===== Pré-escuta do trecho gravado (disponível com a gravação pausada) =====
  previewRecording() {
    if (this.previewAudio && !this.previewAudio.paused) {
      this.previewAudio.pause()
      return
    }

    // sempre remonta o blob: pode haver trecho novo desde a última pausa
    this.stopPreview()
    window.setTimeout(() => {
      if (!this.recordChunks.length) return

      const type = (this.recorder?.mimeType || "audio/webm").split(";")[0]
      this.previewUrl = URL.createObjectURL(new Blob(this.recordChunks, { type }))
      this.previewAudio = new Audio(this.previewUrl)
      ;["play", "pause", "ended"].forEach((name) => {
        this.previewAudio.addEventListener(name, () => this.syncPreviewIcon())
      })
      this.previewAudio.addEventListener("timeupdate", () => this.updatePreviewProgress())
      this.previewAudio.addEventListener("ended", () => this.resetPreviewProgress())
      this.element.classList.add("is-preview-active")
      this.previewAudio.play().catch(() => {})
    }, 120)
  }

  stopPreview() {
    if (this.previewAudio) {
      this.previewAudio.pause()
      this.previewAudio = null
    }
    if (this.previewUrl) {
      URL.revokeObjectURL(this.previewUrl)
      this.previewUrl = null
    }
    this.element.classList.remove("is-preview-active")
    this.resetPreviewProgress()
    this.syncPreviewIcon()
  }

  // Progresso da pré-escuta sobre o wave (bolinha + barras já tocadas).
  // Duração = tempo gravado conhecido: blob parcial não expõe duration confiável.
  updatePreviewProgress() {
    if (!this.hasRecordBarsTarget || !this.previewAudio) return

    const total = this.recordElapsedMs / 1000
    const progress = total > 0 ? Math.min(1, this.previewAudio.currentTime / total) : 0
    const cursor = this.recordBarsTarget.querySelector(".wa-rec-cursor")
    if (cursor) cursor.style.left = `calc(6px + ${(progress * 100).toFixed(1)}% - ${(progress * 12).toFixed(1)}px)`

    const bars = this.recordBarsTarget.querySelectorAll("i")
    const played = Math.round(progress * bars.length)
    bars.forEach((bar, index) => bar.classList.toggle("is-played", index < played))
  }

  resetPreviewProgress() {
    if (!this.hasRecordBarsTarget) return

    const cursor = this.recordBarsTarget.querySelector(".wa-rec-cursor")
    if (cursor) cursor.style.left = "0%"
    this.recordBarsTarget.querySelectorAll("i").forEach((bar) => bar.classList.remove("is-played"))
    this.syncPreviewIcon()
  }

  syncPreviewIcon() {
    if (!this.hasRecordPreviewTarget) return

    const playing = this.previewAudio && !this.previewAudio.paused && !this.previewAudio.ended
    const icon = this.recordPreviewTarget.querySelector("i")
    if (icon) icon.className = playing ? "bi bi-pause-fill" : "bi bi-play-fill"
  }

  // ===== Wave real: amplitude do microfone via AnalyserNode =====
  startWaveform(stream) {
    if (!this.hasRecordBarsTarget) return

    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    if (!AudioContextClass) return

    try {
      this.audioCtx = new AudioContextClass()
      this.audioCtx.resume?.().catch?.(() => {}) // iOS inicia suspenso
      this.waveAnalyser = this.audioCtx.createAnalyser()
      this.waveAnalyser.fftSize = 512
      this.audioCtx.createMediaStreamSource(stream).connect(this.waveAnalyser)
      this.waveSamples = new Uint8Array(this.waveAnalyser.fftSize)
      this.waveHistory = []
      this.recordBarsTarget.replaceChildren(
        ...Array.from({ length: 28 }, () => document.createElement("i"))
      )
      const cursor = document.createElement("b")
      cursor.className = "wa-rec-cursor"
      this.recordBarsTarget.append(cursor)
      this.waveTimer = setInterval(() => this.sampleWave(), 110)
    } catch (_error) {
      /* sem wave: gravação segue normal */
    }
  }

  sampleWave() {
    if (!this.waveAnalyser || this.recordPaused) return

    this.waveAnalyser.getByteTimeDomainData(this.waveSamples)
    let sum = 0
    for (let i = 0; i < this.waveSamples.length; i++) {
      const centered = (this.waveSamples[i] - 128) / 128
      sum += centered * centered
    }
    const rms = Math.sqrt(sum / this.waveSamples.length)
    this.waveHistory.push(Math.min(1, rms * 3.2))
    if (this.waveHistory.length > 28) this.waveHistory.shift()

    const bars = this.recordBarsTarget.querySelectorAll("i")
    const offset = bars.length - this.waveHistory.length
    for (let i = 0; i < bars.length; i++) {
      const value = i < offset ? 0 : this.waveHistory[i - offset]
      bars[i].style.height = `${Math.max(4, Math.round(value * 22))}px`
    }
  }

  stopWaveform() {
    if (this.waveTimer) clearInterval(this.waveTimer)
    this.waveTimer = null
    this.waveAnalyser = null
    this.audioCtx?.close?.().catch?.(() => {})
    this.audioCtx = null
  }

  finishRecording() {
    if (this.recordTimer) clearInterval(this.recordTimer)
    this.stopPreview()
    this.stopWaveform()
    this.recorder?.stream?.getTracks()?.forEach((track) => track.stop())

    const type = (this.recorder?.mimeType || "audio/webm").split(";")[0]
    const extension = type === "audio/mp4" ? "m4a" : type === "audio/ogg" ? "ogg" : "webm"
    const blob = new Blob(this.recordChunks, { type })
    const discarded = this.discardNext
    const autoSend = this.autoSendAfterRecording
    this.recording = false
    this.recordPaused = false
    this.discardNext = false
    this.autoSendAfterRecording = false
    this.recorder = null
    this.recordChunks = []
    this.bodyTarget.disabled = false
    this.element.classList.remove("is-recording-mode", "is-recording-paused")

    // descartado no 🗑 ou gravação relâmpago/vazia
    if (discarded || blob.size < 1200) {
      this.refreshState()
      return
    }

    const stamp = new Date().toTimeString().slice(0, 8).replaceAll(":", "")
    const file = new File([blob], `audio-${stamp}.${extension}`, { type })
    const transfer = new DataTransfer()
    transfer.items.add(file)
    this.fileInputTarget.files = transfer.files
    this.fileChanged()

    if (autoSend) requestAnimationFrame(() => this.element.requestSubmit())
  }

  updateRecordingTimer() {
    if (!this.hasRecordTimeTarget) return

    const elapsed = this.recordElapsedMs + (this.recordPaused ? 0 : Date.now() - this.recordResumedAt)
    const seconds = Math.floor(elapsed / 1000)
    this.recordTimeTarget.textContent = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`
  }

  resetForm() {
    if (this.hasBodyTarget) {
      this.bodyTarget.value = ""
      this.bodyTarget.disabled = false
      this.bodyTarget.placeholder = "Escreva uma mensagem..."
    }

    if (this.hasTemplateTarget) this.templateTarget.value = ""
    if (this.hasFileInputTarget) this.fileInputTarget.value = ""
    if (this.hasPresentationCardTarget) this.presentationCardTarget.value = ""
    this.clearReply()

    this.hideSummary()
    this.hideError()
  }

  showError(message) {
    if (!this.hasErrorTarget) {
      window.alert(message)
      return
    }

    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("is-hidden")
  }

  hideError() {
    if (!this.hasErrorTarget) return

    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("is-hidden")
  }

  showSuccessState(payload) {
    if (!this.hasModeLabelTarget) return

    const kind = payload?.type === "template"
      ? "Modelo enviado"
      : payload?.type === "text"
        ? "Mensagem enviada"
        : "Arquivo enviado"

    this.modeLabelTarget.textContent = kind
    this.modeLabelTarget.classList.add("is-success")
    this.successTimer = setTimeout(() => {
      this.modeLabelTarget.classList.remove("is-success")
      this.refreshState()
    }, 1800)
  }

  // Barra o arquivo na hora da escolha, antes do envio ir falhar na Meta.
  mediaRejection(file) {
    const rules = this.mediaRules
    if (!rules || !file.type) return null

    const maxBytes = rules[file.type]
    if (maxBytes === undefined) {
      return "Formato não suportado pela WhatsApp Cloud API. Use imagem JPG/PNG, vídeo MP4/3GP, áudio AAC/AMR/MP3/M4A/OGG ou documento TXT/PDF/DOC/DOCX/XLS/XLSX/PPT/PPTX."
    }

    if (file.size > maxBytes) {
      const maxMb = Math.round(maxBytes / (1024 * 1024))
      return `${this.fileKind(file)} excede o limite da WhatsApp Cloud API (${maxMb} MB).`
    }

    return null
  }

  get mediaRules() {
    if (this.parsedMediaRules !== undefined) return this.parsedMediaRules

    try {
      this.parsedMediaRules = JSON.parse(this.fileInputTarget.dataset.waMediaRules || "null")
    } catch (_error) {
      this.parsedMediaRules = null
    }

    return this.parsedMediaRules
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  humanSize(bytes) {
    const size = Number(bytes || 0)
    if (size < 1024) return `${size} B`
    if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`

    return `${(size / (1024 * 1024)).toFixed(1)} MB`
  }

  fileKind(file) {
    const type = String(file?.type || "")
    if (type.startsWith("image/")) return "Imagem"
    if (type.startsWith("video/")) return "Vídeo"
    if (type.startsWith("audio/")) return "Áudio"

    return "Documento"
  }

  buildOptimisticPayload() {
    const tempId = `wa-temp-${Date.now()}-${Math.floor(Math.random() * 10000)}`
    const body = this.hasBodyTarget ? this.bodyTarget.value.trim() : ""
    const file = this.hasFileInputTarget ? this.fileInputTarget.files[0] : null
    const templateName = this.hasTemplateTarget ? this.templateTarget.value.trim() : ""
    const html = this.optimisticHtml({ tempId, body, file, templateName })

    return html ? { tempId, html } : null
  }

  optimisticHtml({ tempId, body, file, templateName }) {
    const content = this.optimisticContent({ tempId, body, file, templateName })
    if (!content) return null
    const compactClass = this.element.classList.contains("wa-inbox-composer--compact") ? "wa-inbox-bubble--compact" : ""
    const meta = this.optimisticMeta()

    return `
      <div class="wa-inbox-bubble-row wa-inbox-bubble-row--outbound is-optimistic" data-wa-temp-id="${tempId}">
        <div class="wa-inbox-bubble wa-inbox-bubble--outbound ${file ? "wa-inbox-bubble--media" : ""} ${compactClass}">
          <div class="wa-inbox-bubble__surface">
            ${content}
          </div>
          ${meta}
        </div>
      </div>
    `
  }

  optimisticContent({ tempId, body, file, templateName }) {
    if (templateName) {
      return `
        <div class="wa-inbox-bubble__eyebrow"><i class="bi bi-file-text"></i> modelo ${this.escapeHtml(templateName)}</div>
      `
    }

    if (file) {
      const kind = this.fileKind(file)
      const meta = `${kind} · ${this.humanSize(file.size)}`
      const bodyHtml = body ? `<div class="wa-inbox-bubble__body wa-inbox-bubble__body--media">${this.escapeHtml(body)}</div>` : ""
      const objectUrl = this.optimisticObjectUrl(tempId, file)
      const mediaBlock = kind === "Imagem" && objectUrl
        ? `
          <div class="wa-inbox-bubble__media-block wa-inbox-bubble__media-block--image">
            <div class="wa-inbox-media-frame wa-inbox-media-frame--image wa-inbox-media wa-inbox-media--image-link">
              <img src="${this.escapeHtml(objectUrl)}" alt="${this.escapeHtml(file.name)}" class="wa-inbox-media wa-inbox-media--image">
            </div>
            <div class="wa-inbox-media-card__meta">${this.escapeHtml(meta)}</div>
          </div>
        `
        : kind === "Vídeo" && objectUrl
          ? `
            <div class="wa-inbox-bubble__media-block wa-inbox-bubble__media-block--video">
              <div class="wa-inbox-media-frame wa-inbox-media-frame--video wa-inbox-media wa-inbox-media--video-link">
                <video src="${this.escapeHtml(objectUrl)}#t=0.001" class="wa-inbox-media wa-inbox-media--video" muted playsinline preload="metadata"></video>
                <span class="wa-inbox-media__play" aria-hidden="true">
                  <i class="bi bi-play-fill"></i>
                </span>
              </div>
              <div class="wa-inbox-media-card__meta">${this.escapeHtml(meta)}</div>
            </div>
          `
          : kind === "Áudio"
        ? `
          <div class="wa-inbox-bubble__media-block wa-inbox-bubble__media-block--audio">
            <div class="wa-audio-preview wa-audio-preview--message">
              <button type="button" class="wa-audio-preview__toggle" aria-label="Áudio pendente" disabled>
                <i class="bi bi-play-fill"></i>
              </button>
              <div class="wa-audio-preview__body">
                <button type="button" class="wa-audio-preview__track" aria-label="Áudio pendente" disabled>
                  <span class="wa-audio-preview__track-fill" style="width:0%"></span>
                </button>
                <div class="wa-audio-preview__footer">
                  <span class="wa-audio-preview__time"><span>0:00</span><span>/</span><span>0:00</span></span>
                  <span class="wa-audio-preview__summary">${this.escapeHtml(meta)}</span>
                </div>
              </div>
              <span class="wa-audio-preview__badge"><i class="bi bi-headphones"></i></span>
            </div>
          </div>
        `
        : `
          <div class="wa-inbox-bubble__media-block wa-inbox-bubble__media-block--document">
            <div class="wa-inbox-media-card wa-inbox-media-card--document wa-inbox-media-card--message">
              <span class="wa-inbox-media-card__row">
                <span class="wa-inbox-media-card__icon"><i class="bi bi-file-earmark-text-fill"></i></span>
                <span class="wa-inbox-media-card__copy">
                  <span class="wa-inbox-media-card__title">${this.escapeHtml(file.name)}</span>
                  <span class="wa-inbox-media-card__meta">${this.escapeHtml(meta)}</span>
                </span>
                <span class="wa-inbox-media-card__action"><i class="bi bi-clock"></i></span>
              </span>
            </div>
          </div>
        `
      return `
        ${mediaBlock}
        ${bodyHtml}
      `
    }

    if (body) {
      return `
        <div class="wa-inbox-bubble__body wa-inbox-bubble__body--text">${this.escapeHtml(body)}</div>
      `
    }

    return null
  }

  optimisticMeta() {
    return `
      <div class="wa-inbox-bubble__meta" data-wa-message-status="pending">
        <div class="wa-inbox-bubble__time">
          ${this.escapeHtml(this.currentTimeLabel())}
          <i class="bi bi-clock" data-wa-message-status-icon title="Enviando" aria-label="Enviando"></i>
        </div>
      </div>
    `
  }

  currentTimeLabel() {
    return new Intl.DateTimeFormat("pt-BR", {
      hour: "2-digit",
      minute: "2-digit"
    }).format(new Date())
  }

  escapeHtml(value) {
    return String(value || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }

  dispatchFailedMessage() {
    if (!this.pendingMessageId) return

    window.dispatchEvent(new CustomEvent("wa:message-send-failed", {
      detail: { tempId: this.pendingMessageId }
    }))
  }

  optimisticObjectUrl(tempId, file) {
    if (!tempId || !file || typeof URL === "undefined" || typeof URL.createObjectURL !== "function") return null
    if (this.optimisticObjectUrls.has(tempId)) return this.optimisticObjectUrls.get(tempId)

    const objectUrl = URL.createObjectURL(file)
    this.optimisticObjectUrls.set(tempId, objectUrl)
    return objectUrl
  }

  revokeOptimisticObjectUrl(tempId) {
    const objectUrl = this.optimisticObjectUrls.get(tempId)
    if (!objectUrl) return

    URL.revokeObjectURL(objectUrl)
    this.optimisticObjectUrls.delete(tempId)
  }

  revokeAllOptimisticObjectUrls() {
    this.optimisticObjectUrls.forEach((objectUrl) => URL.revokeObjectURL(objectUrl))
    this.optimisticObjectUrls.clear()
  }
}
