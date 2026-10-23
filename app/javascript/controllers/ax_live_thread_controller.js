import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// O frame de leitura nunca contém o composer: atualizações preservam o rascunho.
export default class extends Controller {
  static targets = ["frame", "input", "submit"]
  static values = { channel: String, params: Object }

  connect() {
    this.subscription = consumer.subscriptions.create(
      { ...this.paramsValue, channel: this.channelValue },
      { connected: () => this.refresh(), received: () => this.refresh() }
    )
    this.onVisible = () => { if (!document.hidden) this.refresh() }
    document.addEventListener("visibilitychange", this.onVisible)
  }

  disconnect() {
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
