import { Controller } from "@hotwired/stimulus"

// Busca do hero (layouts Clássico, Barra e Cartão, em todos os temas):
//   - abas Comprar/Alugar: gravam a finalidade e trocam as faixas de valor;
//   - botão de voz: troca o formulário de filtros por uma barra de gravação no estilo do WhatsApp. Tocar no microfone da barra
//     começa a gravar (onda sonora real e cronômetro) e o mesmo botão vira "enviar";
//   - tudo vai para /busca-ia, que devolve a URL da listagem já filtrada. O áudio só é enviado para transcrição.
const MAX_SECONDS = 30
const MIME_TYPES = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4", "audio/ogg;codecs=opus"]
const BAR_WIDTH = 3
const BAR_GAP = 3
const WAVE_FPS = 24

export default class extends Controller {
  static targets = [
    "transaction", "tab", "priceSelect", "filtersPanel", "aiPanel", "aiText", "aiSubmit", "mic", "error",
    "voiceToggle", "status", "action", "wave", "timer"
  ]
  static values = { aiUrl: String, voice: Boolean, salePriceOptions: Array, rentPriceOptions: Array }

  connect() {
    this.recording = false
    this.cancelled = false
    this.idleLabel = this.hasAiSubmitTarget ? this.aiSubmitTarget.querySelector("span")?.textContent : ""
    // Voz é uma aba exclusiva: tocar em Comprar/Alugar (de qualquer layout) volta aos filtros.
    this.onTransactionClick = (event) => {
      if (this.element.dataset.voice !== "on") return

      const tab = event.target.closest("[data-search-tabs-target='tab'], [data-transaction-type], [data-hero-search-target='tab']")
      if (tab && !tab.matches("[data-hero-search-target='voiceToggle']")) this.setVoiceMode(false)
    }
    this.element.addEventListener("click", this.onTransactionClick)
    this.canRecord = this.voiceValue && this.voiceSupported()
    if (this.hasMicTarget) this.micTarget.hidden = !this.canRecord
    // Painel em barra: sem gravação possível (navegador sem suporte ou conta sem voz) ele vira só escrita.
    if (this.hasActionTarget) this.setPanelState(this.canRecord ? "idle" : "text")
  }

  disconnect() {
    this.element.removeEventListener("click", this.onTransactionClick)
    this.cancelRecording()
  }

  // ---- Finalidade ----

  transaction(event) {
    const value = event.currentTarget.dataset.value
    if (this.hasTransactionTarget) this.transactionTarget.value = value
    this.tabTargets.forEach((tab) => tab.setAttribute("aria-pressed", tab.dataset.value === value))
    this.updatePriceOptions(value)
  }

  updatePriceOptions(value) {
    if (!this.hasPriceSelectTarget) return

    const options = value === "aluguel" ? this.rentPriceOptionsValue : this.salePriceOptionsValue
    if (!options.length) return

    const select = this.priceSelectTarget
    const current = select.value
    select.innerHTML = ""
    select.append(new Option(select.dataset.placeholder || "Valor aproximado", ""))
    options.slice(1).forEach(([label, optionValue]) => select.append(new Option(label, optionValue)))
    if ([...select.options].some((option) => option.value === current)) select.value = current
  }

  // ---- Botão de voz (Clássico e Barra) ----

  toggleVoice() {
    this.setVoiceMode(this.element.dataset.voice !== "on")
  }

  // "Cancelar" da barra de gravação: descarta o áudio e volta aos filtros.
  cancelVoice() {
    this.setVoiceMode(false)
  }

  setVoiceMode(on) {
    this.element.dataset.voice = on ? "on" : "off"
    if (this.hasFiltersPanelTarget) this.filtersPanelTarget.hidden = on
    if (this.hasAiPanelTarget) this.aiPanelTarget.hidden = !on
    this.voiceToggleTargets.forEach((button) => button.setAttribute("aria-pressed", on))
    this.clearError()
    if (!on) return this.cancelRecording()

    // Dois passos, como no WhatsApp: tocar em "Voz" só mostra a barra (com o microfone parado); gravar começa ao tocar no microfone.
    if (this.canRecord && this.hasActionTarget) {
      this.setPanelState("idle")
      this.actionTarget.focus({ preventScroll: true })
    } else if (this.hasAiTextTarget) {
      this.aiTextTarget.focus({ preventScroll: true })
    }
  }

  // Botão de ação da barra: microfone (iniciar) → enviar (durante a gravação) → carregando; no modo texto, envia o texto.
  primary() {
    if (this.busy) return
    if (this.panelState === "recording") return this.stopRecording()
    if (this.panelState === "idle" && this.canRecord) return this.startRecording()

    return this.submitAi()
  }

  suggestion(event) {
    this.aiTextTarget.value = event.currentTarget.textContent.trim()
    this.aiTextTarget.focus()
  }

  // "Filtro detalhado": abre o drawer global de filtros (a página o renderiza sempre que o hero é a Barra); sem drawer, leva à listagem.
  openFilters(event) {
    const request = new CustomEvent("public-filter-drawer:open", { detail: { handled: false } })
    window.dispatchEvent(request)
    if (!request.detail.handled) window.location.assign(event.currentTarget.dataset.href)
  }

  // ---- IA: texto ----

  async submitAi() {
    const query = this.aiTextTarget.value.trim()
    if (!query) return this.showError("Descreva o imóvel que você procura.")

    const body = new FormData()
    body.append("query", query)
    await this.send(body)
  }

  // ---- IA: voz ----

  voiceSupported() {
    return Boolean(navigator.mediaDevices?.getUserMedia && typeof MediaRecorder !== "undefined" && this.mimeType() !== undefined)
  }

  mimeType() {
    if (typeof MediaRecorder.isTypeSupported !== "function") return ""
    return MIME_TYPES.find((type) => MediaRecorder.isTypeSupported(type))
  }

  // Microfone do cartão: alterna entre gravar e parar (parar envia).
  async toggleRecording() {
    if (this.recording) return this.stopRecording()

    await this.startRecording()
  }

  async startRecording() {
    this.clearError()
    this.cancelled = false
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch (_error) {
      this.setPanelState("text")
      this.setStatus(null)
      return this.showError("Não consegui acessar o microfone. Libere a permissão ou escreva a descrição.")
    }

    const mimeType = this.mimeType()
    this.chunks = []
    this.startedAt = Date.now()
    this.recorder = new MediaRecorder(this.stream, mimeType ? { mimeType } : undefined)
    this.recorder.addEventListener("dataavailable", (event) => event.data.size && this.chunks.push(event.data))
    this.recorder.addEventListener("stop", () => this.finishRecording())
    this.recorder.start()
    this.setRecording(true)
    this.limitTimer = setTimeout(() => this.stopRecording(), MAX_SECONDS * 1000)
  }

  // Parar = enviar (como o botão de enviar do WhatsApp).
  stopRecording() {
    clearTimeout(this.limitTimer)
    if (this.recorder?.state === "recording") this.recorder.stop()
  }

  // Cancelar = descartar o áudio.
  cancelRecording() {
    this.cancelled = true
    clearTimeout(this.limitTimer)
    if (this.recorder?.state === "recording") this.recorder.stop()
    else this.cleanupRecording()
  }

  async finishRecording() {
    const seconds = Math.max(1, Math.round((Date.now() - this.startedAt) / 1000))
    const type = (this.recorder.mimeType || "audio/webm").split(";")[0]
    const blob = new Blob(this.chunks, { type })
    this.cleanupRecording()
    if (this.cancelled) return

    if (blob.size < 1000) {
      this.setPanelState(this.canRecord ? "idle" : "text")
      return this.showError("Não ouvi nada. Fale a descrição do imóvel e tente de novo.")
    }

    const body = new FormData()
    body.append("audio", blob, `busca.${type.split("/")[1] || "webm"}`)
    body.append("audio_duration_seconds", seconds)
    await this.send(body)
  }

  cleanupRecording() {
    this.stopWave()
    this.stream?.getTracks().forEach((track) => track.stop())
    this.stream = null
    this.setRecording(false)
  }

  setRecording(recording) {
    this.recording = recording
    if (this.hasMicTarget) {
      this.micTarget.setAttribute("aria-pressed", recording)
      this.micTarget.classList.toggle("is-recording", recording)
      this.micTarget.querySelector("i").className = recording ? "bi bi-stop-fill" : "bi bi-mic"
      this.micTarget.setAttribute("aria-label", recording ? "Parar a gravação" : "Falar a descrição do imóvel")
    }
    if (this.hasActionTarget) {
      this.setPanelState(recording ? "recording" : (this.busy ? "busy" : (this.canRecord ? "idle" : "text")))
      if (recording) this.startWave()
    }
    this.setStatus(recording ? "Gravando… toque em enviar quando terminar." : null)
  }

  // ---- Onda sonora real (Web Audio): amplitude do microfone em barras que rolam da direita para a esquerda ----

  startWave() {
    if (!this.hasWaveTarget || !this.stream) return

    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    if (!AudioContextClass) return

    this.audioContext = new AudioContextClass()
    this.analyser = this.audioContext.createAnalyser()
    this.analyser.fftSize = 512
    this.audioContext.createMediaStreamSource(this.stream).connect(this.analyser)
    this.samples = new Uint8Array(this.analyser.fftSize)
    this.levels = []
    this.waveTimer = setInterval(() => this.sampleWave(), 1000 / WAVE_FPS)
    this.clockTimer = setInterval(() => this.updateClock(), 250)
    this.updateClock()
  }

  stopWave() {
    clearInterval(this.waveTimer)
    clearInterval(this.clockTimer)
    this.waveTimer = this.clockTimer = null
    this.audioContext?.close().catch(() => {})
    this.audioContext = this.analyser = null
    if (this.hasWaveTarget) this.drawWave([])
  }

  sampleWave() {
    this.analyser.getByteTimeDomainData(this.samples)
    let sum = 0
    for (const value of this.samples) {
      const centered = (value - 128) / 128
      sum += centered * centered
    }
    const rms = Math.sqrt(sum / this.samples.length)
    this.levels.push(Math.min(1, rms * 5)) // ganho: voz normal fica visível sem estourar
    this.drawWave(this.levels)
  }

  drawWave(levels) {
    const canvas = this.waveTarget
    const ratio = window.devicePixelRatio || 1
    const width = canvas.clientWidth
    const height = canvas.clientHeight
    if (!width || !height) return

    if (canvas.width !== Math.round(width * ratio) || canvas.height !== Math.round(height * ratio)) {
      canvas.width = Math.round(width * ratio)
      canvas.height = Math.round(height * ratio)
    }
    const context = canvas.getContext("2d")
    context.setTransform(ratio, 0, 0, ratio, 0, 0)
    context.clearRect(0, 0, width, height)
    context.fillStyle = getComputedStyle(canvas).color

    const slots = Math.floor(width / (BAR_WIDTH + BAR_GAP))
    const visible = levels.slice(-slots)
    visible.forEach((level, index) => {
      const barHeight = Math.max(3, level * height)
      const x = width - (visible.length - index) * (BAR_WIDTH + BAR_GAP)
      context.beginPath()
      context.roundRect(x, (height - barHeight) / 2, BAR_WIDTH, barHeight, BAR_WIDTH / 2)
      context.fill()
    })
  }

  updateClock() {
    if (!this.hasTimerTarget) return

    const seconds = Math.floor((Date.now() - this.startedAt) / 1000)
    this.timerTarget.textContent = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`
  }

  // ---- Estado visual da barra de voz ----

  setPanelState(state) {
    this.panelState = state
    if (!this.hasAiPanelTarget) return

    this.aiPanelTarget.dataset.state = state
    if (!this.hasActionTarget) return

    const labels = { idle: "Gravar a descrição do imóvel", recording: "Enviar a gravação", busy: "Interpretando", text: "Buscar" }
    const icons = { idle: "bi-mic-fill", recording: "bi-send-fill", busy: "bi-arrow-repeat", text: "bi-send-fill" }
    this.actionTarget.setAttribute("aria-label", labels[state])
    this.actionTarget.querySelector("i").className = `bi ${icons[state]}`
    if (state === "text" && this.hasAiTextTarget && this.aiPanelTarget.offsetParent) this.aiTextTarget.focus({ preventScroll: true })
  }

  // Texto de apoio do painel de voz (alvo "status", lido por leitores de tela); null volta ao texto inicial.
  setStatus(text) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = text ?? this.statusTarget.dataset.idle ?? ""
  }

  // ---- Envio ----

  async send(body) {
    this.clearError()
    // Finalidade: o campo do próprio layout ou o do formulário do hero Clássico (que tem as abas de outro controller).
    const transaction = this.hasTransactionTarget ? this.transactionTarget : this.element.querySelector("input[name='transaction_type']")
    if (transaction) body.append("transaction_type", transaction.value)
    this.setBusy(true)
    this.setStatus("Interpretando o que você pediu…")
    try {
      const response = await fetch(this.aiUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content, Accept: "application/json" },
        credentials: "same-origin",
        body
      })
      const data = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(data.error || "Não foi possível buscar agora. Use os filtros.")

      if (data.transcription && this.hasAiTextTarget) this.aiTextTarget.value = data.transcription
      this.setStatus(data.transcription ? `Buscando: “${data.transcription}”` : "Buscando…")
      window.location.assign(data.redirect_url)
    } catch (error) {
      this.setBusy(false)
      this.setPanelState(this.canRecord ? "idle" : "text")
      this.setStatus(null)
      this.showError(error.message)
    }
  }

  setBusy(busy) {
    this.busy = busy
    if (this.hasAiSubmitTarget) {
      this.aiSubmitTarget.disabled = busy
      this.aiSubmitTarget.classList.toggle("is-busy", busy)
      const label = this.aiSubmitTarget.querySelector("span")
      if (label) label.textContent = busy ? "Interpretando…" : this.idleLabel
    }
    if (this.hasActionTarget) {
      this.actionTarget.disabled = busy
      if (busy) this.setPanelState("busy")
    }
  }

  showError(message) {
    if (!this.hasErrorTarget) return

    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  clearError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
  }
}
