import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// O frame de leitura nunca contém o composer: atualizações preservam o rascunho.
export default class extends Controller {
  static targets = ["frame", "input", "submit"]
  static values = { channel: String, params: Object, readUrl: String }

  connect() {
    this.subscription = consumer.subscriptions.create(
      { ...this.paramsValue, channel: this.channelValue },
      { connected: () => this.refresh(), received: () => this.refresh() }
    )
    this.onVisible = () => { if (!document.hidden) this.refresh() }
    this.onFocus = () => this.frameLoaded()
    window.addEventListener("focus", this.onFocus)
    window.addEventListener("scroll", this.onFocus, { passive: true })
    document.addEventListener("visibilitychange", this.onVisible)
  }

  disconnect() {
    window.removeEventListener("focus", this.onFocus)
    window.removeEventListener("scroll", this.onFocus)
    consumer.subscriptions.remove(this.subscription)
    document.removeEventListener("visibilitychange", this.onVisible)
  }

  refresh() {
    if (document.hidden) return
    if (this.frameTarget.hasAttribute("busy")) {
      this.pendingRefresh = true
      return
    }
    this.frameTarget.reload()
  }

  frameLoaded() {
    const state = this.frameTarget.querySelector("[data-thread-reply-open]")
    const cursor = Number(state?.dataset.threadReadCursor || 0)
    const visible = this.hasReadUrlValue && this.frameTarget.getBoundingClientRect().bottom > 0 && this.frameTarget.getBoundingClientRect().top < window.innerHeight
    if (visible && cursor > (this.readCursor || 0) && !document.hidden && document.hasFocus()) {
      this.readCursor = cursor
      const token = document.querySelector("meta[name='csrf-token']")?.content
      fetch(this.readUrlValue, { method: "POST", credentials: "same-origin", headers: { "X-CSRF-Token": token, "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ cursor }) })
        .then((response) => { if (!response.ok) this.readCursor = 0 })
        .catch(() => { this.readCursor = 0 })
    }
    if (state && this.hasInputTarget) {
      const closed = state.dataset.threadReplyOpen !== "true"
      this.inputTarget.disabled = closed
      this.submitTarget.disabled = closed || this.sending
    }
    if (this.pendingRefresh) {
      this.pendingRefresh = false
      this.refresh()
    }
  }

  submitting() {
    this.sending = true
    if (this.hasInputTarget) this.sentBody = this.inputTarget.value
  }

  submitted(event) {
    this.sending = false
    if (event.detail.success && this.hasInputTarget && this.inputTarget.value === this.sentBody) {
      this.inputTarget.value = ""
    }
    this.frameLoaded()
  }
}
