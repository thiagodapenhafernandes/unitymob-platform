import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["notice", "preview"]
  static values = { leadId: Number, cursor: Number }

  update({ detail: data }) {
    if (Number(data.lead_id) !== this.leadIdValue) return
    if (data.event === "unread_changed" && Number(data.cursor) >= this.cursorValue) {
      this.noticeTarget.hidden = true
    } else if (data.kind === "instagram_message" && Number(data.instagram_message_id) >= this.cursorValue) {
      this.cursorValue = Number(data.instagram_message_id)
      this.previewTarget.textContent = data.body || ""
      this.noticeTarget.title = data.body || ""
      this.noticeTarget.hidden = false
    }
  }
}
