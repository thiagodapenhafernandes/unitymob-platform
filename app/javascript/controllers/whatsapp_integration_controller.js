import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "signupButton",
    "signupFeedback",
    "testResult",
    "testTo",
    "notificationTemplateSelect",
    "notificationVariableMap"
  ]
  static values = {
    appId: String,
    apiVersion: String,
    configId: String,
    callbackUrl: String,
    testUrl: String,
    sendUrl: String
  }

  connect() {
    this.latestSession = {}
    this.submittingSignup = false
    this.statusPollTimer = null
    this.receiveMetaMessage = this.receiveMetaMessage.bind(this)
    window.addEventListener("message", this.receiveMetaMessage)
    this.prepareMetaSdk()
  }

  disconnect() {
    window.removeEventListener("message", this.receiveMetaMessage)
    this.clearStatusPolling()
  }

  launchSignup() {
    if (!window.FB) {
      this.showSignupFeedback("warning", "SDK da Meta ainda está carregando. Tente novamente em alguns segundos.")
      return
    }

    this.signupButtonTarget.disabled = true
    this.showSignupFeedback("info", "Abrindo fluxo de conexão da Meta...")
    this.latestSession = {}

    window.FB.login(this.submitSignupResult.bind(this), {
      config_id: this.configIdValue,
      response_type: "code",
      override_default_response_type: true,
      extras: {
        setup: {},
        sessionInfoVersion: "3"
      }
    })
  }

  testConnection() {
    this.showTestResult("info", "Testando conexão...")
    this.post(this.testUrlValue).then((response) => {
      const json = response.json || {}
      const send = json.send || {}
      const receive = json.receive || {}
      const sendLine = send.ok
        ? `<strong>Envio pronto</strong> - numero ${this.escapeHtml(send.label || "valido")}`
        : `<strong>Envio:</strong> ${this.escapeHtml(send.error || "falha ao validar credenciais")}`
      const receiveLine = receive.ok
        ? `<strong>Recebimento pronto</strong> - app inscrito no webhook${receive.apps?.length ? ` (${receive.apps.map((app) => this.escapeHtml(app)).join(", ")})` : ""}`
        : `<strong>Recebimento:</strong> ${this.escapeHtml(receive.error || "nenhum app inscrito no webhook da WABA. Assine o webhook no painel da Meta.")}`

      this.showTestResult(send.ok && receive.ok ? "success" : "warning", `${sendLine}<br>${receiveLine}`)
    }).catch((error) => this.showTestResult("danger", error.message))
  }

  sendTest() {
    const to = this.hasTestToTarget ? this.testToTarget.value.trim() : ""
    if (!to) {
      this.showTestResult("warning", "Informe um número para o teste.")
      return
    }

    this.showTestResult("info", "Enviando mensagem de teste...")
    this.post(this.sendUrlValue, { to })
      .then((response) => {
        const message = this.escapeHtml(response.json?.message || "Sem resposta do servidor.")
        this.showTestResult(response.ok ? "success" : "warning", message)
        if (response.ok && response.json?.status_url) this.pollTestMessageStatus(response.json.status_url)
      })
      .catch((error) => this.showTestResult("danger", error.message))
  }

  syncNotificationTemplateVariables() {
    if (!this.hasNotificationTemplateSelectTarget || !this.hasNotificationVariableMapTarget) return

    const selected = this.notificationTemplateSelectTarget.selectedOptions[0]
    const references = this.parseJson(selected?.dataset.variableReferences, [])
    const sources = this.parseJson(this.notificationVariableMapTarget.dataset.variableSources, [])
    const defaultMapping = this.parseJson(this.notificationVariableMapTarget.dataset.defaultMapping, {})
    const count = references.reduce((max, item) => Math.max(max, Number(item.index) || 0), 0)

    if (!selected?.value || count === 0) {
      this.notificationVariableMapTarget.innerHTML = ""
      return
    }

    const referencesByIndex = new Map(references.map((item) => [Number(item.index), item]))
    this.notificationVariableMapTarget.innerHTML = Array.from({ length: count }, (_value, offset) => {
      const index = offset + 1
      const reference = referencesByIndex.get(index) || {}
      const context = reference.context || `Variável {{${index}}}`
      const selectedSource = this.inferNotificationVariableSource(context, defaultMapping[String(index)])
      const options = sources.map(([label, value]) => (
        `<option value="${this.escapeHtml(value)}"${value === selectedSource ? " selected" : ""}>${this.escapeHtml(label)}</option>`
      )).join("")

      return `
        <label class="wa-variable-map__row">
          <span>{{${index}}}<small>${this.escapeHtml(context)}</small></span>
          <select name="notification_template_setting[variable_mapping][${index}]" class="ax-control">
            ${options}
          </select>
        </label>
      `
    }).join("")
  }

  inferNotificationVariableSource(context, fallback) {
    const text = this.normalizeForMatch(context)
    if (text.match(/corretor|broker|responsavel|atendente/)) {
      if (text.match(/telefone|celular|whatsapp|fone/)) return "broker_phone"
      if (text.match(/email|e-mail/)) return "broker_email"
      return "broker_name"
    }
    if (text.match(/telefone|celular|whatsapp|fone|contato/)) return "lead_phone_or_link"
    if (text.match(/email|e-mail/)) return "lead_email_or_link"
    if (text.match(/origem|canal|fonte/)) return "lead_origin"
    if (text.match(/produto|imovel|imobiliario|interesse|empreendimento|link/)) return "lead_other_or_link"
    if (text.match(/nome|cliente|lead/)) return "lead_name"

    return fallback || "lead_other_or_link"
  }

  normalizeForMatch(value) {
    return String(value || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
  }

  pollTestMessageStatus(url, attempt = 1) {
    this.clearStatusPolling()
    const maxAttempts = 12

    this.statusPollTimer = window.setTimeout(() => {
      fetch(url, { headers: this.jsonHeaders() })
        .then((response) => response.json().then((json) => ({ ok: response.ok, json })))
        .then((response) => {
          if (!response.ok) throw new Error(response.json?.message || "Não foi possível consultar a entrega.")

          const status = response.json?.status
          const label = this.escapeHtml(response.json?.label || "Aguardando retorno da Meta.")
          const tone = status === "failed" ? "warning" : (["delivered", "read"].includes(status) ? "success" : "info")
          this.showTestResult(tone, label)

          if (!response.json?.terminal && attempt < maxAttempts) {
            this.pollTestMessageStatus(url, attempt + 1)
          }
        })
        .catch((error) => this.showTestResult("warning", this.escapeHtml(error.message)))
    }, attempt === 1 ? 2500 : 5000)
  }

  clearStatusPolling() {
    if (!this.statusPollTimer) return

    window.clearTimeout(this.statusPollTimer)
    this.statusPollTimer = null
  }

  testSenderConnection(event) {
    const button = event.currentTarget
    const url = button.dataset.testUrl
    const resultTarget = button.closest(".wa-number-row")?.querySelector("[data-wa-number-test-result]")
    if (!url || !resultTarget) return

    button.disabled = true
    this.paintNotice(resultTarget, "info")
    resultTarget.textContent = "Testando número..."

    this.post(url).then((response) => {
      const json = response.json || {}
      const send = json.send || {}
      const receive = json.receive || {}
      const sendLine = send.ok
        ? `<strong>Envio pronto</strong> - número ${this.escapeHtml(send.label || "válido")}`
        : `<strong>Envio:</strong> ${this.escapeHtml(send.error || json.message || "falha ao validar credenciais")}`
      const receiveLine = receive.ok
        ? `<strong>Recebimento pronto</strong>${receive.apps?.length ? ` - ${receive.apps.map((app) => this.escapeHtml(app)).join(", ")}` : ""}`
        : `<strong>Recebimento:</strong> ${this.escapeHtml(receive.error || "nenhum app inscrito no webhook da WABA")}`

      this.paintNotice(resultTarget, send.ok && receive.ok ? "success" : "warning")
      resultTarget.innerHTML = `${sendLine}<br>${receiveLine}`
    }).catch((error) => {
      this.paintNotice(resultTarget, "danger")
      resultTarget.textContent = error.message
    }).finally(() => {
      button.disabled = false
    })
  }

  receiveMetaMessage(event) {
    if (!this.trustedMetaOrigin(event.origin)) return

    const data = this.parseMetaMessage(event.data)
    if (data.type === "WA_EMBEDDED_SIGNUP") {
      this.latestSession = {
        ...data,
        data: this.parseSessionInfo(data.data)
      }
    }
  }

  trustedMetaOrigin(origin) {
    try {
      const hostname = new URL(origin).hostname
      return hostname === "facebook.com" || hostname.endsWith(".facebook.com")
    } catch (_error) {
      return false
    }
  }

  parseSessionInfo(value) {
    if (!value) return {}
    if (typeof value === "object") return value

    try {
      return JSON.parse(value)
    } catch (_error) {
      return {}
    }
  }

  parseMetaMessage(value) {
    if (!value) return {}
    if (typeof value === "object") return value

    try {
      return JSON.parse(value)
    } catch (_error) {
      return {}
    }
  }

  parseJson(value, fallback) {
    if (!value) return fallback

    try {
      return JSON.parse(value)
    } catch (_error) {
      return fallback
    }
  }

  prepareMetaSdk() {
    window.fbAsyncInit = () => {
      window.FB.init({ appId: this.appIdValue, cookie: true, xfbml: true, version: this.apiVersionValue })
    }

    if (document.getElementById("facebook-jssdk")) return

    const script = document.createElement("script")
    script.id = "facebook-jssdk"
    script.src = "https://connect.facebook.net/pt_BR/sdk.js"
    document.body.appendChild(script)
  }

  submitSignupResult(response) {
    const code = response?.authResponse?.code
    const delay = code ? 1500 : 0

    window.setTimeout(() => {
      const sessionInfo = this.latestSession.data || {}
      if (code && !this.hasSignupIds(sessionInfo)) {
        this.showSignupFeedback("warning", "A Meta autorizou o login, mas não enviou os dados da WABA e do número. Reabra o fluxo e conclua a seleção do número.")
        this.signupButtonTarget.disabled = false
        return
      }

      const payload = {
        code,
        event: this.latestSession.event || (code ? "FINISH" : "ERROR"),
        session_info: sessionInfo
      }

      fetch(this.callbackUrlValue, {
        method: "POST",
        headers: this.jsonHeaders(),
        body: JSON.stringify(payload)
      }).then((result) => (
        result.json().then((body) => {
          if (!result.ok) throw new Error(body.message || "Não foi possível concluir a conexão.")
          return body
        })
      )).then((body) => {
        this.showSignupFeedback("success", body.message || "WhatsApp conectado com sucesso.")
        window.setTimeout(() => {
          if (window.Turbo) window.Turbo.visit(window.location.href, { action: "replace" })
          else window.location.reload()
        }, 900)
      }).catch((error) => {
        this.showSignupFeedback("warning", error.message)
      }).finally(() => {
        this.signupButtonTarget.disabled = false
      })
    }, delay)
  }

  hasSignupIds(sessionInfo) {
    return Boolean(sessionInfo?.waba_id && sessionInfo?.phone_number_id)
  }

  post(url, body = {}) {
    return fetch(url, {
      method: "POST",
      headers: this.jsonHeaders(),
      body: JSON.stringify(body)
    }).then((response) => response.json().then((json) => ({ ok: response.ok, json })))
  }

  showSignupFeedback(type, message) {
    if (!this.hasSignupFeedbackTarget) return
    this.paintNotice(this.signupFeedbackTarget, type)
    this.signupFeedbackTarget.textContent = message
  }

  showTestResult(type, html) {
    if (!this.hasTestResultTarget) return
    this.paintNotice(this.testResultTarget, type)
    this.testResultTarget.innerHTML = html
  }

  paintNotice(element, type) {
    const tone = ["success", "warning", "danger", "info"].includes(type) ? type : "info"
    element.classList.remove(
      "ax-inline-notice--success",
      "ax-inline-notice--warning",
      "ax-inline-notice--danger",
      "ax-inline-notice--info"
    )
    element.classList.add(`ax-inline-notice--${tone}`)
    element.hidden = false
  }

  jsonHeaders() {
    return {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
    }
  }

  escapeHtml(value) {
    return String(value).replace(/[&<>"']/g, (char) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      "\"": "&quot;",
      "'": "&#039;"
    }[char]))
  }
}
