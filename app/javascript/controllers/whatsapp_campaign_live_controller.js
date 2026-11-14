import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "statusBadge",
    "metric",
    "metricHint",
    "rate",
    "progressMeter",
    "progressPercent",
    "pendingCount",
    "responseCards",
    "outcomeCards",
    "interactionHistory",
    "messagesBody"
  ]

  static values = {
    statusUrl: String,
    interval: { type: Number, default: 3000 }
  }

  connect() {
    this.timer = null
    this.fetching = false
    this.boundVisibilityChange = this.handleVisibilityChange.bind(this)
    document.addEventListener("visibilitychange", this.boundVisibilityChange)
    this.refresh()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.boundVisibilityChange)
    this.stop()
  }

  handleVisibilityChange() {
    if (document.hidden) return

    this.refresh() // refresh imediato ao voltar para a aba
  }

  start() {
    if (this.timer || !this.hasStatusUrlValue) return

    this.schedule(this.intervalValue)
  }

  stop() {
    if (!this.timer) return

    window.clearTimeout(this.timer)
    this.timer = null
  }

  schedule(interval) {
    this.stop()
    if (!this.hasStatusUrlValue) return

    this.timer = window.setTimeout(() => this.refresh(), Number(interval || this.intervalValue))
  }

  async refresh() {
    if (this.fetching || !this.hasStatusUrlValue) return

    if (document.hidden) {
      // Aba oculta: não busca; só re-checa em cadência lenta até voltar.
      this.schedule(this.intervalValue * 5)
      return
    }

    this.stop()
    this.fetching = true
    try {
      const response = await fetch(this.statusUrlValue, {
        headers: {
          Accept: "application/json",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })

      if (!response.ok) return

      const data = await response.json()
      this.render(data)

      if (data.active) {
        this.schedule(data.next_poll_interval_ms || this.intervalValue)
      }
    } catch (_error) {
      this.stop()
    } finally {
      this.fetching = false
    }
  }

  render(data) {
    this.renderStatus(data)
    this.renderMetrics(data.metrics || {})
    this.renderProgress(data)
    this.renderResponseCards(data.response_cards || [])
    if (this.hasOutcomeCardsTarget) this.outcomeCardsTarget.innerHTML = (data.outcome_cards || []).map((card) => this.interactionCard(card)).join("") || "<p>Nenhum resultado interno confirmado.</p>"
    this.renderInteractionHistory(data.recent_interactions || [])
    this.renderMessages(data.recent_messages || [])
  }

  renderStatus(data) {
    if (!this.hasStatusBadgeTarget) return

    const tone = this.badgeTone(data.status_tone)
    this.statusBadgeTarget.innerHTML = `<span class="ax-badge ${tone}">${this.escape(data.status_label || data.status || "-")}</span>`
  }

  renderMetrics(metrics) {
    this.metricTargets.forEach((element) => {
      const key = element.dataset.metricKey
      if (!key || !(key in metrics)) return

      element.textContent = this.metricValue(key, metrics[key])
    })

    this.metricHintTargets.forEach((element) => {
      const key = element.dataset.metricKey
      const text = this.metricHint(key, metrics)
      if (text) element.textContent = text
    })

    this.rateTargets.forEach((element) => {
      const key = element.dataset.rateKey
      if (!key || !(key in metrics)) return

      element.textContent = `${this.percent(metrics[key])}%`
    })
  }

  renderProgress(data) {
    const percent = Number(data.progress_percent || 0)

    if (this.hasProgressMeterTarget) {
      this.progressMeterTarget.value = percent
    }

    if (this.hasProgressPercentTarget) {
      this.progressPercentTarget.textContent = `${this.percent(percent)}%`
    }

    if (this.hasPendingCountTarget) {
      this.pendingCountTarget.textContent = this.number(data.pending_count || 0)
    }
  }

  renderMessages(messages) {
    if (!this.hasMessagesBodyTarget) return

    if (!messages.length) {
      this.messagesBodyTarget.innerHTML = '<tr><td colspan="7" class="ax-table__empty">Nenhuma mensagem encontrada para os filtros atuais.</td></tr>'
      return
    }

    this.messagesBodyTarget.innerHTML = messages.map((message) => this.messageRow(message)).join("")
  }

  renderResponseCards(cards) {
    if (!this.hasResponseCardsTarget) return

    if (!cards.length) {
      this.responseCardsTarget.innerHTML = `
        <div class="ax-inline-notice ax-inline-notice--info">
          Este template não possui botões mensuráveis. Respostas por texto continuam aparecendo em Mensagens recentes e podem ser tratadas pela Automação.
        </div>
      `
      return
    }

    this.responseCardsTarget.innerHTML = cards.map((card) => this.interactionCard(card)).join("")
  }

  interactionCard(card) {
    const count = card.count == null ? "Não mensurável" : this.number(card.count)
    const rate = card.rate == null ? "" : `<small>${this.percent(card.rate)}% das entregues</small>`
    return `<article class="whatsapp-response-card whatsapp-response-card--${this.escapeAttribute(card.tone || "slate")}">
      <i class="bi ${this.escapeAttribute(card.icon || "bi-grid")}" aria-hidden="true"></i>
      <span>${this.escape(card.label || "-")}</span><strong>${count}</strong>${rate}
      <small>${this.escape(card.action_label || "")}</small><small>${this.escape(card.hint || "")}</small>
    </article>`
  }

  renderInteractionHistory(events) {
    if (!this.hasInteractionHistoryTarget) return
    this.interactionHistoryTarget.innerHTML = events.map((event) => `<tr>
      <td>${this.escape(event.occurred_at)}</td><td>${this.escape(event.recipient)}</td>
      <td>${this.escape(event.kind)}${event.legacy ? " · registro anterior" : ""}</td>
      <td>${this.escape(event.label)}</td><td>${this.escape(event.action || "—")}</td>
    </tr>`).join("") || '<tr><td colspan="5" class="ax-table__empty">Nenhum evento detalhado registrado. Respostas antigas continuam em Mensagens recentes.</td></tr>'
  }

  messageRow(message) {
    const badgeTone = this.badgeTone(message.status_tone)
    const responseTone = this.badgeTone(message.response_status_tone)
    const recipientName = this.escape(message.recipient_name || message.lead_name || "-")
    const recipientUrl = this.escapeAttribute(message.recipient_url || message.lead_url || "#")
    const recipientCell = message.recipient_url || message.lead_url
      ? `<a class="ax-link" href="${recipientUrl}">${recipientName}</a>`
      : `${recipientName}<small class="tw-block tw-text-slate-500">Ainda não convertido em lead</small>`

    return `
      <tr>
        <td><strong>${recipientCell}</strong></td>
        <td>${this.escape(message.phone_number || "-")}</td>
        <td><code class="whatsapp-message-table__wamid">${this.escape(message.external_message_id || "-")}</code></td>
        <td><span class="ax-badge ${badgeTone}">${this.escape(message.status_label || message.status || "-")}</span></td>
        <td>
          <span class="ax-badge ${responseTone}">${this.escape(message.response_status_label || "Sem resposta")}</span>
          <small class="tw-block tw-text-slate-500">${this.escape(message.response_status_note || "Aguardando resposta do destinatário.")}</small>
        </td>
        <td>${this.escape(message.failure_reason || "-")}</td>
        <td>${this.escape(message.updated_at || "-")}</td>
      </tr>
    `
  }

  metricValue(key, value) {
    if (["cpl", "cost"].includes(key)) return "—"

    return this.number(value)
  }

  metricHint(key, metrics) {
    const hints = {
      total: "mensagens criadas",
      sent: `${this.percent(metrics.sent_rate)}% do total`,
      delivered: `${this.percent(metrics.delivery_rate)}% das enviadas`,
      read: `${this.percent(metrics.read_rate)}% das entregues`,
      interactions: `${this.percent(metrics.reply_rate)}% das entregues · destinatários únicos`,
      clicks: "repetições legítimas preservadas",
      free_responses: "destinatários únicos · texto ou mídia",
      failed: `${this.percent(metrics.failure_rate)}% do total`,
      replied: `${this.percent(metrics.reply_rate)}% resposta`,
      attended: "Atendimentos aceitos na Unitymob",
      unattended: "Interações sem aceite de atendimento",
      cpl: "Custo por disparo não informado pela Meta",
      cost: "A Meta não informa custo por disparo; consulte o número e período abaixo."
    }

    return hints[key]
  }

  badgeTone(tone) {
    const allowed = ["gray", "green", "amber", "red", "blue", "orange", "cyan"]
    return `ax-badge--${allowed.includes(tone) ? tone : "gray"}`
  }

  number(value) {
    return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 }).format(Number(value || 0))
  }

  percent(value) {
    return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 1 }).format(Number(value || 0))
  }

  escape(value) {
    const element = document.createElement("span")
    element.textContent = value
    return element.innerHTML
  }

  escapeAttribute(value) {
    return this.escape(value).replace(/"/g, "&quot;")
  }
}
