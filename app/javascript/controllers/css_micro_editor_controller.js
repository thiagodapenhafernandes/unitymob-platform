import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "highlight"]

  connect() {
    this.element.classList.add("is-enhanced")
    this.sync()
  }

  sync() {
    if (!this.hasInputTarget || !this.hasHighlightTarget) return

    const value = this.inputTarget.value || ""
    this.highlightTarget.innerHTML = this.highlight(value)
    this.syncScroll()
  }

  syncScroll() {
    if (!this.hasInputTarget || !this.hasHighlightTarget) return

    const wrapper = this.highlightTarget.parentElement
    wrapper.scrollTop = this.inputTarget.scrollTop
    wrapper.scrollLeft = this.inputTarget.scrollLeft
  }

  handleKeydown(event) {
    if (event.key === "Tab") {
      event.preventDefault()
      this.insertAtSelection("  ")
      return
    }

    if (event.key === "Enter" && event.shiftKey) {
      event.preventDefault()
      this.insertAtSelection("\n")
    }
  }

  insertAtSelection(text) {
    const input = this.inputTarget
    const start = input.selectionStart
    const end = input.selectionEnd

    input.value = `${input.value.slice(0, start)}${text}${input.value.slice(end)}`
    input.selectionStart = input.selectionEnd = start + text.length
    input.dispatchEvent(new Event("input", { bubbles: true }))
  }

  highlight(source) {
    return this.escape(source || " ")
      .replace(/(\/\*[\s\S]*?\*\/)/g, '<span class="cm-comment">$1</span>')
      .replace(/(&quot;[^&]*?&quot;|&#39;[^&]*?&#39;)/g, '<span class="cm-string">$1</span>')
      .replace(/(@media|\b(?:min|max)-width\b)/g, '<span class="cm-at-rule">$1</span>')
      .replace(/(\.custom-logo(?:::?before|::?after)?|\s\.custom-logo\s+img)/g, '<span class="cm-selector">$1</span>')
      .replace(/([a-z-]+)(\s*:)/g, '<span class="cm-property">$1</span>$2')
      .replace(/(:\s*)(#[0-9a-fA-F]{3,8}|-?\d+(?:\.\d+)?(?:px|rem|em|%|vh|vw)?)/g, '$1<span class="cm-value">$2</span>')
      .replace(/([{};])/g, '<span class="cm-punctuation">$1</span>')
  }

  escape(value) {
    return value
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
  }
}
