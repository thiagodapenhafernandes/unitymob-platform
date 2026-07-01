import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Inbox WhatsApp: ActionCable primeiro, com sync de reconciliação só quando necessário.
export default class extends Controller {
  static targets = ["context", "scroll", "list", "jump"]
  static values = {
    last: Number,
    conversationId: Number,
    focusMode: Boolean,
    statusCursor: String
  }

  connect() {
    this.handleSubmittingMessage = this.handleSubmittingMessage.bind(this)
    this.handleSentMessage = this.handleSentMessage.bind(this)
    this.handleFailedMessage = this.handleFailedMessage.bind(this)
    this.handleScroll = this.handleScroll.bind(this)
    this.handleCableConnected = this.handleCableConnected.bind(this)
    this.handleCableDisconnected = this.handleCableDisconnected.bind(this)
    this.handleVisibilityChange = this.handleVisibilityChange.bind(this)
    this.handleWindowFocus = this.handleWindowFocus.bind(this)
    this.stickToBottom = true
    this.cableConnected = false
    this.recoveryAttempt = 0
    this.lastServerActivityAt = Date.now()
    window.addEventListener("wa:message-submitting", this.handleSubmittingMessage)
    window.addEventListener("wa:message-sent", this.handleSentMessage)
    window.addEventListener("wa:message-send-failed", this.handleFailedMessage)
    document.addEventListener("visibilitychange", this.handleVisibilityChange)
    window.addEventListener("focus", this.handleWindowFocus)
    if (this.hasScrollTarget) {
      this.scrollTarget.addEventListener("scroll", this.handleScroll, { passive: true })
    }
    this.scrollBottom({ force: true })
    this.updateJumpButton()
    this.refreshInboxCounters()
    this.connectCable()
  }

  disconnect() {
    window.removeEventListener("wa:message-submitting", this.handleSubmittingMessage)
    window.removeEventListener("wa:message-sent", this.handleSentMessage)
    window.removeEventListener("wa:message-send-failed", this.handleFailedMessage)
    document.removeEventListener("visibilitychange", this.handleVisibilityChange)
    window.removeEventListener("focus", this.handleWindowFocus)
    if (this.hasScrollTarget) {
      this.scrollTarget.removeEventListener("scroll", this.handleScroll)
    }
    this.disconnectCable()
    this.clearRecoverySync()
  }

  scrollBottom({ force = false } = {}) {
    const scroller = this.hasScrollTarget ? this.scrollTarget : this.element
    if (!force && !this.stickToBottom) return

    scroller.scrollTop = scroller.scrollHeight
    this.stickToBottom = true
    this.updateJumpButton()
  }

  handleScroll() {
    const scroller = this.hasScrollTarget ? this.scrollTarget : this.element
    const threshold = 48
    const distanceFromBottom = scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight
    this.stickToBottom = distanceFromBottom <= threshold
    this.updateJumpButton()
  }

  jumpToLatest() {
    this.scrollBottom({ force: true })
  }

  append(m) {
    if (!m?.html) return
    if (m.id && this.listTarget.querySelector(`[data-message-id="${m.id}"]`)) return

    const emptyState = this.listTarget.querySelector(".wa-inbox-thread__empty")
    if (emptyState) emptyState.remove()
    this.listTarget.insertAdjacentHTML("beforeend", m.html)
  }

  handleSubmittingMessage(event) {
    const message = event.detail || {}
    if (!message.tempId || !message.html) return

    this.removeOptimisticMessage(message.tempId)
    this.append({ html: message.html })
    this.scrollBottom({ force: true })
  }

  handleFailedMessage(event) {
    const message = event.detail || {}
    if (!message.tempId) return

    const optimistic = this.findOptimisticMessage(message.tempId)
    if (!optimistic) return

    optimistic.classList.remove("is-optimistic")
    optimistic.classList.add("is-failed")

    const icon = optimistic.querySelector("[data-wa-message-status-icon]")
    if (icon) {
      icon.className = "bi bi-exclamation-circle is-failed"
      icon.title = "Falhou"
      icon.setAttribute("aria-label", "Falhou")
    }

    const status = optimistic.querySelector("[data-wa-message-status]")
    if (status) status.dataset.waMessageStatus = "failed"
  }

  handleSentMessage(event) {
    const message = event.detail || {}
    if (!message.id) return

    if (message.tempId) {
      const optimistic = this.findOptimisticMessage(message.tempId)
      const existing = this.listTarget.querySelector(`[data-message-id="${message.id}"]`)
      if (optimistic && existing) {
        optimistic.remove()
      } else if (optimistic && message.html) {
        optimistic.insertAdjacentHTML("afterend", message.html)
        optimistic.remove()
      } else {
        this.append(message)
      }
    } else {
      this.append(message)
    }

    this.lastValue = Math.max(this.lastValue || 0, Number(message.id) || 0)
    if (message.status_cursor) this.statusCursorValue = message.status_cursor
    this.markServerActivity()
    this.syncContext(message)
    this.syncQueue(message)
    this.scrollBottom({ force: true })
  }

  syncContext(payload) {
    if (!payload?.context_html || !this.hasContextTarget) return

    this.contextTarget.innerHTML = payload.context_html
  }

  syncContextFragments(payload) {
    const fragments = payload?.context_fragments
    if (!fragments || !this.hasContextTarget) return

    this.replaceContextNode("contextSummary", fragments.summary_html)
    this.replaceContextNode("contextCrmCopy", fragments.crm_copy_html)
    this.replaceContextNode("contextCrmBadges", fragments.crm_badges_html)
    this.replaceContextNode("contextCrmSummary", fragments.crm_summary_html)
    this.replaceContextNode("contextActionsMetrics", fragments.actions_metrics_html)
  }

  syncQueue(payload) {
    const queue = payload?.queue
    if (!queue?.id || !queue.html) return

    const list = document.querySelector("[data-wa-queue-list]")
    const current = document.querySelector(`.wa-inbox-conversation[data-conversation-id="${queue.id}"]`)
    if (current) {
      const wasActive = current.classList.contains("is-active")
      const wrapper = document.createElement("div")
      wrapper.innerHTML = queue.html.trim()
      const next = wrapper.firstElementChild
      if (!next) return
      if (wasActive) next.classList.add("is-active")
      this.preservePrivateLabels(current, next, ".wa-inbox-conversation__labels", ".wa-inbox-conversation__preview")
      this.normalizeQueueItem(next, queue.id)
      if (this.sameQueueItem(current, next)) {
        this.refreshInboxCounters()
        return
      }
      current.replaceWith(next)
      if (list?.contains(next) && !wasActive) {
        list.prepend(next)
      }
      this.flashQueueItem(next, { silent: wasActive })
      this.refreshInboxCounters()
      return
    }

    if (list) {
      list.insertAdjacentHTML("afterbegin", queue.html)
      const inserted = list.querySelector(`.wa-inbox-conversation[data-conversation-id="${queue.id}"]`)
      if (inserted) {
        this.normalizeQueueItem(inserted, queue.id)
        this.flashQueueItem(inserted)
      }
      this.refreshInboxCounters()
    }
  }

  normalizeQueueItem(item, conversationId) {
    const inFocusMode = Boolean(document.querySelector(".wa-inbox-page--focus"))
    const href = inFocusMode ? item.dataset.conversationFocusHref : item.dataset.conversationDefaultHref
    if (href) item.setAttribute("href", href)

    if (Number(conversationId) !== this.conversationIdValue) return

    item.dataset.unread = "false"
    item.classList.add("is-active")
    item.querySelector(".wa-inbox-conversation__unread")?.remove()
  }

  flashQueueItem(item, { silent = false } = {}) {
    if (silent) return

    item.classList.remove("is-updated")
    item.offsetHeight
    item.classList.add("is-updated")
    window.setTimeout(() => item.classList.remove("is-updated"), 1600)
  }

  sameQueueItem(current, next) {
    const currentClone = current.cloneNode(true)
    const nextClone = next.cloneNode(true)

    ;[currentClone, nextClone].forEach((item) => {
      item.classList.remove("is-updated")
      item.classList.remove("is-active")
      item.hidden = false
    })

    return currentClone.outerHTML === nextClone.outerHTML
  }

  updateJumpButton() {
    if (!this.hasJumpTarget) return

    this.jumpTarget.classList.toggle("is-hidden", this.stickToBottom)
  }

  findOptimisticMessage(tempId) {
    return this.listTarget.querySelector(`[data-wa-temp-id="${tempId}"]`)
  }

  removeOptimisticMessage(tempId) {
    const optimistic = this.findOptimisticMessage(tempId)
    if (optimistic) optimistic.remove()
  }

  replace(message) {
    if (!message?.id || !message?.html) return

    const current = this.listTarget.querySelector(`[data-message-id="${message.id}"]`)
    if (!current) {
      this.append(message)
      return
    }

    const next = this.messageElementFromHtml(message.html, message.id)
    if (!next) return

    if (this.replaceStatusOnly(current, next)) return

    current.replaceWith(next)
  }

  messageElementFromHtml(html, messageId) {
    const wrapper = document.createElement("template")
    wrapper.innerHTML = html.trim()

    return wrapper.content.querySelector(`[data-message-id="${messageId}"]`)
  }

  replaceStatusOnly(current, next) {
    const currentStatus = current.querySelector("[data-wa-message-status]")
    const nextStatus = next.querySelector("[data-wa-message-status]")
    if (!currentStatus || !nextStatus) return false

    const currentSurface = current.querySelector(".wa-inbox-bubble__surface")
    const nextSurface = next.querySelector(".wa-inbox-bubble__surface")
    if (!currentSurface || !nextSurface) return false
    if (currentSurface.innerHTML !== nextSurface.innerHTML) return false

    currentStatus.replaceWith(nextStatus)
    current.dataset.messageDirection = next.dataset.messageDirection || current.dataset.messageDirection
    current.className = next.className

    const currentBubble = current.querySelector(".wa-inbox-bubble")
    const nextBubble = next.querySelector(".wa-inbox-bubble")
    if (currentBubble && nextBubble) currentBubble.className = nextBubble.className

    return true
  }

  connectCable() {
    if (!this.hasConversationIdValue) return

    this.subscription = consumer.subscriptions.create(
      { channel: "WhatsappConversationChannel", conversation_id: this.conversationIdValue, focus_mode: this.focusModeValue },
      {
        connected: this.handleCableConnected,
        disconnected: this.handleCableDisconnected,
        rejected: this.handleCableDisconnected,
        received: (payload) => this.handleBroadcast(payload)
      }
    )
  }

  disconnectCable() {
    if (!this.subscription) return

    consumer.subscriptions.remove(this.subscription)
    this.subscription = null
  }

  handleCableConnected() {
    this.cableConnected = true
    this.recoveryAttempt = 0
    this.markServerActivity()
    this.clearRecoverySync()
  }

  handleCableDisconnected() {
    this.cableConnected = false
    this.scheduleRecoverySync(3000)
  }

  handleVisibilityChange() {
    if (document.hidden) return

    this.reopenCableConnectionIfNeeded()
  }

  handleWindowFocus() {
    this.reopenCableConnectionIfNeeded()
  }

  handleBroadcast(payload) {
    const messages = Array.isArray(payload?.messages) ? payload.messages : []
    const updates = Array.isArray(payload?.updates) ? payload.updates : []
    if (!messages.length && !updates.length && !payload?.queue && !payload?.context_fragments) return

    const shouldStick = this.stickToBottom
    messages.forEach((message) => this.append(message))
    updates.forEach((message) => this.replace(message))
    if (messages.length) this.lastValue = Math.max(this.lastValue || 0, Number(messages[messages.length - 1].id) || 0)
    if (payload.status_cursor) this.statusCursorValue = payload.status_cursor
    this.markServerActivity()
    this.syncContextFragments(payload)
    this.syncQueue(payload)
    this.scrollBottom({ force: shouldStick })
    this.updateJumpButton()
  }

  replaceContextNode(targetName, html) {
    if (!html) return

    const current = this.contextTarget.querySelector(`[data-wa-thread-target="${targetName}"]`)
    if (!current) return

    const wrapper = document.createElement("div")
    wrapper.innerHTML = html.trim()
    if (targetName === "contextSummary") {
      this.preservePrivateLabels(current, wrapper, ".wa-inbox-thread__labels")
    }

    current.innerHTML = wrapper.innerHTML
  }

  preservePrivateLabels(current, next, selector, afterSelector = null) {
    const currentLabels = current.querySelector(selector)
    if (!currentLabels || next.querySelector(selector)) return

    const clone = currentLabels.cloneNode(true)
    const insertionAnchor = afterSelector ? next.querySelector(afterSelector) : null
    if (insertionAnchor) {
      insertionAnchor.insertAdjacentElement("afterend", clone)
    } else {
      next.appendChild(clone)
    }
  }

  refreshInboxCounters() {
    const list = document.querySelector("[data-wa-queue-list]")
    if (!list) return

    const items = Array.from(list.querySelectorAll(".wa-inbox-conversation[data-conversation-id]"))
    const total = items.length
    const unread = items.filter((item) => item.dataset.unread === "true").length
    const unlinked = items.filter((item) => item.dataset.lead !== "true").length
    const totalUnread = items.reduce((sum, item) => {
      const badge = item.querySelector(".wa-inbox-conversation__unread")
      return sum + (badge ? Number.parseInt(badge.textContent, 10) || 0 : 0)
    }, 0)

    document.querySelectorAll('[data-wa-inbox-filter-count="all"]').forEach((node) => {
      node.textContent = String(total)
    })
    document.querySelectorAll('[data-wa-inbox-filter-count="unread"]').forEach((node) => {
      node.textContent = String(unread)
    })
    document.querySelectorAll('[data-wa-inbox-filter-count="unlinked"]').forEach((node) => {
      node.textContent = String(unlinked)
    })

    document.querySelectorAll('[data-wa-inbox-heading-metric="conversations"] strong').forEach((node) => {
      node.textContent = String(total)
    })
    document.querySelectorAll('[data-wa-inbox-heading-metric="unread"] strong').forEach((node) => {
      node.textContent = String(totalUnread)
    })

  }

  markServerActivity() {
    this.lastServerActivityAt = Date.now()
  }

  scheduleRecoverySync(delay = this.nextRecoveryDelay()) {
    if (this.cableConnected) return

    this.clearRecoverySync()
    this.recoveryTimer = setTimeout(() => {
      this.recoveryTimer = null
      if (this.cableConnected || document.hidden) return

      this.reopenCableConnection()

      if (!this.cableConnected) {
        this.recoveryAttempt += 1
        this.scheduleRecoverySync()
      }
    }, delay)
  }

  clearRecoverySync() {
    if (!this.recoveryTimer) return

    clearTimeout(this.recoveryTimer)
    this.recoveryTimer = null
  }

  nextRecoveryDelay() {
    const delays = [3000, 5000, 8000, 13000, 21000, 30000]
    return delays[Math.min(this.recoveryAttempt, delays.length - 1)]
  }

  reopenCableConnectionIfNeeded() {
    if (this.cableConnected) return

    this.reopenCableConnection()
  }

  reopenCableConnection() {
    try {
      if (typeof consumer?.connection?.reopen === "function") {
        consumer.connection.reopen()
        return
      }

      if (typeof consumer?.connection?.open === "function") {
        consumer.connection.open()
      }
    } catch (_error) {
      /* silencioso */
    }
  }

}
