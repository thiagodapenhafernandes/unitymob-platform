import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

// Connects to data-controller="tom-select"
export default class extends Controller {
  static values = {
    options: Object,
    create: Boolean,
    tags: Boolean, // New value to enable tagging behavior clearly
    url: String,
    searchParam: String,
    minLength: Number,
    optionDescriptions: Object
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
    if (this.element.tomselect) {
      this.tomSelect = this.element.tomselect
      this.unbindDeferredInitialization()
      return
    }

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

    this.applyOptionDescriptions(config)

    if (this.hasUrlValue) {
      const minLength = this.hasMinLengthValue ? this.minLengthValue : 2
      const searchParam = this.hasSearchParamValue ? this.searchParamValue : "q"

      config.valueField = config.valueField || "value"
      config.labelField = config.labelField || "text"
      config.searchField = config.searchField || "text"
      config.loadThrottle = config.loadThrottle || 250
      config.shouldLoad = config.shouldLoad || ((query) => query.trim().length >= minLength)
      config.load = config.load || ((query, callback) => {
        const term = query.trim()
        if (term.length < minLength) {
          callback()
          return
        }

        const url = new URL(this.urlValue, window.location.origin)
        url.searchParams.set(searchParam, term)

        fetch(url.toString(), { headers: { Accept: "application/json" } })
          .then((response) => response.ok ? response.json() : [])
          .then((items) => callback(items))
          .catch(() => callback())
      })
    }

    // If it's a tag input (jsonb array), we want to behave like one
    if (this.tagsValue) {
      config.create = true
      config.persist = false
      config.createOnBlur = true
    }

    // dropdown no <body>: escapa de qualquer card/painel com overflow hidden
    if (config.dropdownParent === undefined) config.dropdownParent = "body"

    this.tomSelect = new TomSelect(this.element, config)
    this.bindDropdownViewportSync()
    if (!isMultiple) {
      this.tomSelect.wrapper.classList.add("ax-ts-single-search")
    }

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

  applyOptionDescriptions(config) {
    const descriptions = this.hasOptionDescriptionsValue ? this.optionDescriptionsValue : {}
    if (!descriptions || Object.keys(descriptions).length === 0) return

    const existingRender = config.render || {}
    config.render = {
      ...existingRender,
      option: existingRender.option || ((data, escape) => {
        const description = data.description || descriptions[data.value] || ""
        return `
          <div class="ax-select-option">
            <div class="ax-select-option__label">${escape(data.text || "")}</div>
            ${description ? `<div class="ax-select-option__description">${escape(description)}</div>` : ""}
          </div>
        `
      }),
      item: existingRender.item || ((data, escape) => {
        return `<div class="ax-select-item">${escape(data.text || "")}</div>`
      })
    }
  }

  // Com dropdownParent: body o dropdown é posicionado uma única vez ao abrir; se a
  // página rolar depois (teclado do celular abrindo, scroll do usuário), ele fica
  // órfão fora da tela. Enquanto aberto, reancora a cada scroll/resize e, no mobile,
  // rola o campo para o meio da área visível acima do teclado.
  bindDropdownViewportSync() {
    this.repositionDropdown = () => this.tomSelect?.positionDropdown()

    this.tomSelect.on("dropdown_open", () => {
      window.addEventListener("scroll", this.repositionDropdown, true)
      window.addEventListener("resize", this.repositionDropdown)
      window.visualViewport?.addEventListener("resize", this.repositionDropdown)

      if (window.matchMedia("(max-width: 767.98px)").matches) {
        clearTimeout(this.mobileScrollTimeout)
        this.mobileScrollTimeout = setTimeout(() => {
          this.tomSelect?.control.scrollIntoView({ block: "center", behavior: "smooth" })
          this.repositionDropdown()
        }, 250) // espera o teclado terminar de abrir
      }
    })

    this.tomSelect.on("dropdown_close", () => this.unbindDropdownViewportSync())
  }

  unbindDropdownViewportSync() {
    clearTimeout(this.mobileScrollTimeout)
    if (!this.repositionDropdown) return
    window.removeEventListener("scroll", this.repositionDropdown, true)
    window.removeEventListener("resize", this.repositionDropdown)
    window.visualViewport?.removeEventListener("resize", this.repositionDropdown)
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
    this.unbindDropdownViewportSync()
    if (this.tomSelect && this.element.tomselect === this.tomSelect) {
      this.tomSelect.destroy()
    }
    this.tomSelect = null
  }
}
