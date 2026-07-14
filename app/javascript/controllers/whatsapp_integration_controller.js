import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["signupButton", "signupFeedback", "testResult", "testTo"]
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
    this.receiveMetaMessage = this.receiveMetaMessage.bind(this)
    window.addEventListener("message", this.receiveMetaMessage)
    this.prepareMetaSdk()
  }

  disconnect() {
    window.removeEventListener("message", this.receiveMetaMessage)
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
      extras: { setup: {} }
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
      .then((response) => this.showTestResult(response.ok ? "success" : "warning", this.escapeHtml(response.json?.message || "Sem resposta do servidor.")))
      .catch((error) => this.showTestResult("danger", error.message))
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
    if (!event.origin.endsWith("facebook.com")) return

    try {
      const data = JSON.parse(event.data)
      if (data.type === "WA_EMBEDDED_SIGNUP") this.latestSession = data
    } catch (_error) {
      this.latestSession = {}
    }
  }

  prepareMetaSdk() {
    window.fbAsyncInit = () => {
      window.FB.init({ appId: this.appIdValue, cookie: true, xfbml: false, version: this.apiVersionValue })
    }

    if (document.getElementById("facebook-jssdk")) return

    const script = document.createElement("script")
    script.id = "facebook-jssdk"
    script.src = "https://connect.facebook.net/pt_BR/sdk.js"
    document.body.appendChild(script)
  }

  submitSignupResult(response) {
    const code = response?.authResponse?.code
    const payload = {
      code,
      event: this.latestSession.event || (code ? "FINISH" : "ERROR"),
      session_info: this.latestSession.data || {}
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
