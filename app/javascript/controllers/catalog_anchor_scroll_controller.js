import { Controller } from "@hotwired/stimulus"

// Scrolls the admin catalog to a returned property card after Turbo renders.
export default class extends Controller {
  connect() {
    this.scrollAttempts = []
    this.scheduleScroll()
    this.boundScheduleScroll = this.scheduleScroll.bind(this)
    document.addEventListener("turbo:render", this.boundScheduleScroll)
    document.addEventListener("turbo:load", this.boundScheduleScroll)
  }

  disconnect() {
    this.scrollAttempts.forEach((timer) => clearTimeout(timer))
    this.scrollAttempts = []
    document.removeEventListener("turbo:render", this.boundScheduleScroll)
    document.removeEventListener("turbo:load", this.boundScheduleScroll)
  }

  scheduleScroll() {
    const targetId = this.targetId()
    if (!targetId) return

    this.scrollAttempts.forEach((timer) => clearTimeout(timer))
    this.scrollAttempts = [0, 120, 420].map((delay) => {
      return setTimeout(() => this.scrollToTarget(targetId), delay)
    })
  }

  scrollToTarget(targetId) {
    const target = document.getElementById(targetId)
    if (!target) return

    target.scrollIntoView({ block: "center", inline: "nearest", behavior: "auto" })
  }

  targetId() {
    const hash = window.location.hash.toString().replace(/^#/, "")
    return hash.startsWith("habitation_") ? hash : null
  }
}
