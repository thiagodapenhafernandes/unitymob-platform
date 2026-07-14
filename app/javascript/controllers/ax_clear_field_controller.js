import { Controller } from "@hotwired/stimulus"

// Clears a single form control while preserving the form's existing submit/filter flow.
export default class extends Controller {
  static targets = ["control", "button"]

  connect() {
    this.update()
  }

  clear(event) {
    event.preventDefault()
    event.stopPropagation()

    if (!this.hasControlTarget) return

    const control = this.controlTarget
    const tomSelect = control.tomselect
    if (this.controlUnavailable(control, tomSelect)) return

    if (tomSelect) {
      tomSelect.clear()
      tomSelect.refreshOptions(false)
    } else if (control.multiple) {
      Array.from(control.options || []).forEach((option) => {
        option.selected = false
      })
      this.dispatchControlEvents(control)
    } else {
      control.value = ""
      this.dispatchControlEvents(control)
    }

    this.update()

    if (tomSelect) {
      tomSelect.focus()
    } else {
      control.focus({ preventScroll: true })
    }
  }

  update() {
    if (!this.hasControlTarget || !this.hasButtonTarget) return

    const control = this.controlTarget
    this.buttonTarget.hidden = this.controlUnavailable(control, control.tomselect) || !this.hasValue(control)
  }

  controlUnavailable(control, tomSelect = control?.tomselect) {
    return Boolean(
      !control ||
      control.disabled ||
      control.readOnly ||
      tomSelect?.isDisabled ||
      tomSelect?.isLocked
    )
  }

  hasValue(control) {
    if (control.tomselect) {
      return control.tomselect.items.length > 0
    }

    if (control.multiple) {
      return Array.from(control.selectedOptions || []).some((option) => option.value !== "")
    }

    return control.value.toString().trim() !== ""
  }

  dispatchControlEvents(control) {
    control.dispatchEvent(new Event("input", { bubbles: true }))
    control.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
