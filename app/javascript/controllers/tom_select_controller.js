import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

// Connects to data-controller="tom-select"
export default class extends Controller {
  static values = {
    options: Object,
    create: Boolean,
    tags: Boolean // New value to enable tagging behavior clearly
  }

  connect() {
    if (this.shouldDeferInitialization()) {
      this.bindDeferredInitialization()
      return
    }

    this.initializeTomSelect()
  }

  shouldDeferInitialization() {
    const isHidden = this.element.offsetParent === null
    const inHiddenTabPane = this.element.closest(".tab-pane")?.classList.contains("active") === false
    return isHidden || inHiddenTabPane
  }

  bindDeferredInitialization() {
    this.deferredInitHandler = (event) => {
      this.initializeTomSelect()

      // When initialized from click/touch, open immediately so first interaction works.
      if (event && event.type !== "focus") {
        requestAnimationFrame(() => this.tomSelect?.open())
      }
    }
    this.element.addEventListener("focus", this.deferredInitHandler, { once: true })
    this.element.addEventListener("mousedown", this.deferredInitHandler, { once: true })
    this.element.addEventListener("touchstart", this.deferredInitHandler, { once: true })

    this.tabShownHandler = () => {
      if (this.element.offsetParent !== null) this.initializeTomSelect()
    }
    document.addEventListener("shown.bs.tab", this.tabShownHandler)
  }

  initializeTomSelect() {
    if (this.tomSelect) return

    // Default configuration suitable for Bootstrap 5
    const isMultiple = this.element.hasAttribute("multiple") || this.tagsValue;

    // Only add remove_button plugin if it's a multiple select
    const plugins = {};
    if (isMultiple) {
      plugins.remove_button = { title: '' };
    }

    const config = {
      plugins: plugins,
      create: this.createValue || this.tagsValue,
      persist: false,
      allowEmptyOption: false,
      maxItems: isMultiple ? null : 1,
      dropdownParent: 'body',
      wrapperClass: 'ts-wrapper p-0',
      onDropdownOpen: () => {
        this.element.closest('.ts-wrapper')?.classList.remove('is-invalid')
      },
      ...this.optionsValue
    }

    // If it's a tag input (jsonb array), we want to behave like one
    if (this.tagsValue) {
      config.create = true
      config.persist = false
      config.createOnBlur = true
    }

    this.tomSelect = new TomSelect(this.element, config)

    // Inherit sizing classes from the original element
    if (this.element.classList.contains('form-select-sm') || this.element.classList.contains('form-control-sm')) {
      this.tomSelect.wrapper.classList.add('form-control-sm')
    }

    this.unbindDeferredInitialization()
  }

  unbindDeferredInitialization() {
    if (this.deferredInitHandler) {
      this.element.removeEventListener("focus", this.deferredInitHandler)
      this.element.removeEventListener("mousedown", this.deferredInitHandler)
      this.element.removeEventListener("touchstart", this.deferredInitHandler)
      this.deferredInitHandler = null
    }
    if (this.tabShownHandler) {
      document.removeEventListener("shown.bs.tab", this.tabShownHandler)
      this.tabShownHandler = null
    }
  }

  disconnect() {
    this.unbindDeferredInitialization()
    if (this.tomSelect) {
      this.tomSelect.destroy()
    }
  }
}
