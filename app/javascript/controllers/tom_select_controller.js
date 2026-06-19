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
      if (this.element.offsetParent === null) return

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
    document.addEventListener("ax:tab-shown", this.tabShownHandler)

    const tabPane = this.element.closest(".tab-pane")
    if (tabPane) {
      this.tabPaneObserver = new MutationObserver(() => {
        if (this.element.offsetParent !== null) this.initializeTomSelect()
      })
      this.tabPaneObserver.observe(tabPane, { attributes: true, attributeFilter: ["class", "style"] })
    }

    // Inicializa assim que o campo ficar visível (ex.: seção d-none removida por um
    // toggle), sem depender de foco/clique do usuário. O guard em initializeTomSelect
    // evita inicialização dupla.
    if (typeof IntersectionObserver !== "undefined") {
      this.visibilityObserver = new IntersectionObserver((entries) => {
        if (entries.some((entry) => entry.isIntersecting) && this.element.offsetParent !== null) {
          this.initializeTomSelect()
        }
      })
      this.visibilityObserver.observe(this.element)
    }
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

    const placeholder = this.element.dataset.placeholder || this.element.getAttribute("placeholder")

    const config = {
      plugins: plugins,
      create: this.createValue || this.tagsValue,
      persist: false,
      allowEmptyOption: false,
      maxItems: isMultiple ? null : 1,
      dropdownParent: 'body',
      wrapperClass: 'ts-wrapper p-0',
      dropdownClass: 'ts-dropdown ax-select-dropdown',
      ...(placeholder ? { placeholder } : {}),
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

    if (this.element.closest('.habitation-form-ui')) {
      this.tomSelect.wrapper.classList.remove('form-select', 'form-control', 'form-select-sm', 'form-control-sm')
      this.tomSelect.wrapper.classList.add('ax-form-ts-wrapper')
      if (this.element.closest('.ax-multiselect')) {
        this.tomSelect.wrapper.classList.add('ax-multiselect__tom')
      }
    } else if (this.element.classList.contains('form-select-sm') || this.element.classList.contains('form-control-sm')) {
      this.tomSelect.wrapper.classList.add('form-control-sm')
    }

    this.element.closest('.ax-multiselect')?.classList.remove('ax-multiselect--pending')
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
      document.removeEventListener("ax:tab-shown", this.tabShownHandler)
      this.tabShownHandler = null
    }
    if (this.tabPaneObserver) {
      this.tabPaneObserver.disconnect()
      this.tabPaneObserver = null
    }
    if (this.visibilityObserver) {
      this.visibilityObserver.disconnect()
      this.visibilityObserver = null
    }
  }

  disconnect() {
    this.unbindDeferredInitialization()
    if (this.tomSelect) {
      this.tomSelect.destroy()
    }
  }
}
