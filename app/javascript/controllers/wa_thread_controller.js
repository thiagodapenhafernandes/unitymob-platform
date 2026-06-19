import { Controller } from "@hotwired/stimulus"

// Inbox WhatsApp: rola para o fim e faz polling leve das mensagens novas.
export default class extends Controller {
  static targets = ["list"]
  static values = {
    url: String,
    last: Number,
    interval: { type: Number, default: 8000 }
  }

  connect() {
    this.scrollBottom()
    if (this.urlValue) {
      this.timer = setInterval(() => this.poll(), this.intervalValue)
    }
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer)
  }

  scrollBottom() {
    this.element.scrollTop = this.element.scrollHeight
  }

  async poll() {
    if (document.hidden) return
    try {
      const res = await fetch(`${this.urlValue}?after=${this.lastValue}`, {
        headers: { Accept: "application/json" }
      })
      if (!res.ok) return
      const messages = await res.json()
      if (!messages.length) return
      messages.forEach((m) => this.append(m))
      this.lastValue = messages[messages.length - 1].id
      this.scrollBottom()
    } catch (_e) {
      /* silencioso */
    }
  }

  append(m) {
    const wrap = document.createElement("div")
    wrap.className = `wa-bubble-row wa-bubble-row--${m.direction}`
    const bubble = document.createElement("div")
    bubble.className = `wa-bubble wa-bubble--${m.direction}`
    const text = document.createElement("div")
    text.textContent = m.body || ""
    const time = document.createElement("div")
    time.className = "wa-time"
    time.textContent = m.at
    bubble.appendChild(text)
    bubble.appendChild(time)
    wrap.appendChild(bubble)
    this.listTarget.appendChild(wrap)
  }
}
