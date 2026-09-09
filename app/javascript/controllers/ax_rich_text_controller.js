import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { uploadUrl: String }
  static targets = ["message", "menu", "link", "linkDetails", "menuMessage", "image"]

  get editorElement() { return this.element.querySelector("trix-editor") }

  openMenu(event) {
    if (!event.target.closest("trix-editor") || !this.menuTarget.showPopover) return
    event.preventDefault()
    event.stopPropagation()
    this.range = this.editorElement.editor.getSelectedRange()
    this.menuMessageTarget.textContent = ""
    this.linkTarget.value = ""
    this.linkDetailsTarget.open = false
    this.menuTarget.querySelectorAll("[data-attribute]").forEach(button => {
      button.setAttribute("aria-pressed", String(this.editorElement.editor.attributeIsActive(button.dataset.attribute)))
    })
    this.menuTarget.showPopover()
    const bounds = this.menuTarget.getBoundingClientRect()
    const selection = window.getSelection()
    const anchor = selection.rangeCount ? selection.getRangeAt(0).getBoundingClientRect() : this.editorElement.getBoundingClientRect()
    this.menuTarget.style.left = `${Math.max(8, Math.min(event.clientX || anchor.left, window.innerWidth - bounds.width - 8))}px`
    this.menuTarget.style.top = `${Math.max(8, Math.min(event.clientY || anchor.bottom, window.innerHeight - bounds.height - 8))}px`
    this.menuTarget.querySelector("button").focus()
  }

  dismissMenu(event) {
    if (!this.menuTarget.matches(":popover-open")) return
    if (event.type === "keydown" && event.key === "Escape") {
      event.preventDefault()
      this.menuTarget.hidePopover()
      this.restoreSelection()
    } else if (event.type === "pointerdown" && event.button === 0 && !this.menuTarget.contains(event.target)) {
      // The right-button release that opens a context menu must not dismiss it.
      this.menuTarget.hidePopover()
    }
  }

  disconnect() {
    if (this.hasMenuTarget && this.menuTarget.matches(":popover-open")) this.menuTarget.hidePopover()
  }

  keyboardMenu(event) {
    if (event.key === "ContextMenu" || (event.shiftKey && event.key === "F10")) this.openMenu(event)
  }

  restoreSelection() {
    this.editorElement.focus()
    this.editorElement.editor.setSelectedRange(this.range)
    return this.editorElement.editor
  }

  format(event) {
    const editor = this.restoreSelection()
    const attribute = event.currentTarget.dataset.attribute
    editor.recordUndoEntry("Formatar texto")
    if (["small", "normal", "large"].includes(attribute)) {
      editor.deactivateAttribute("small")
      editor.deactivateAttribute("large")
      if (attribute !== "normal") editor.activateAttribute(attribute)
    } else {
      editor.attributeIsActive(attribute) ? editor.deactivateAttribute(attribute) : editor.activateAttribute(attribute)
    }
    this.menuTarget.hidePopover()
  }

  link() {
    let url
    try { url = new URL(this.linkTarget.value.trim()) } catch { return this.linkError() }
    if (!["https:", "http:", "mailto:", "tel:"].includes(url.protocol)) return this.linkError()
    const editor = this.restoreSelection()
    editor.recordUndoEntry("Inserir link")
    if (this.range[0] === this.range[1]) {
      editor.insertString(url.href)
      editor.setSelectedRange([this.range[0], this.range[0] + url.href.length])
    }
    editor.activateAttribute("href", url.href)
    this.menuTarget.hidePopover()
  }

  linkError() { this.menuMessageTarget.textContent = "Informe uma URL válida (https://, http://, mailto: ou tel:)." }

  unlink() {
    const editor = this.restoreSelection()
    editor.recordUndoEntry("Remover link")
    editor.deactivateAttribute("href")
    this.menuTarget.hidePopover()
  }

  pickImage() {
    this.menuTarget.hidePopover()
    this.imageTarget.click()
  }

  insertImage() {
    const file = this.imageTarget.files[0]
    if (file) this.restoreSelection().insertFile(file)
    this.imageTarget.value = ""
  }

  accept(event) {
    if (!["image/jpeg", "image/png", "image/webp", "image/gif", "application/pdf"].includes(event.file.type) || event.file.size > 20 * 1024 * 1024) {
      event.preventDefault()
      this.messageTarget.textContent = "Use imagens ou PDF de até 20 MB."
    }
  }

  async upload(event) {
    const attachment = event.attachment
    if (!attachment.file) return
    // Prevent Action Text's global direct-upload handler: this endpoint enforces account and Spaces.
    event.stopPropagation()
    const data = new FormData()
    data.append("file", attachment.file)
    this.element.dataset.uploading = String(Number(this.element.dataset.uploading || 0) + 1)
    this.messageTarget.textContent = "Enviando anexo…"
    try {
      const response = await fetch(this.uploadUrlValue, { method: "POST", headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content, Accept: "application/json" }, body: data })
      const blob = await response.json()
      if (!response.ok) throw new Error(blob.error || "Não foi possível enviar o anexo.")
      attachment.setAttributes({ sgid: blob.sgid, url: blob.url, href: blob.url, filename: blob.filename, contentType: blob.content_type, filesize: blob.filesize })
      this.messageTarget.textContent = "Anexo enviado."
    } catch (error) {
      attachment.remove()
      this.messageTarget.textContent = error.message
    } finally {
      this.element.dataset.uploading = String(Math.max(0, Number(this.element.dataset.uploading) - 1))
    }
  }
}
