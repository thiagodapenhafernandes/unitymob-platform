import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cep", "logradouro", "bairro", "cidade", "uf", "tipo", "numero", "complemento"]

  connect() {
    this.lastSearchedCep = ""
    this.loading = false
  }

  async search(event) {
    if (event) event.preventDefault()
    if (this.loading) return

    // If triggered by blur and value hasn't changed or is empty, ignore
    if (event?.type === 'blur') {
      const currentCep = this.normalizedCep()
      if (currentCep === this.lastSearchedCep || currentCep === "") return
    }

    const cep = this.normalizedCep()

    if (cep.length !== 8) return

    // UI Feedback
    const btn = this.element.querySelector('button[data-action*="cep-search#search"]')

    if (btn) {
      btn.dataset.originalLabel ||= btn.innerHTML
      btn.innerHTML = '<span class="ax-spinner" aria-hidden="true"></span>'
      btn.disabled = true
      btn.setAttribute("aria-busy", "true")
    }

    // Add loading class to input
    this.loading = true
    this.cepTarget.classList.add("ax-control--loading")

    try {
      const response = await fetch(`https://brasilapi.com.br/api/cep/v2/${cep}`)

      if (!response.ok) throw new Error('CEP não encontrado')

      const data = await response.json()

      this.populateForm(data)
      this.lastSearchedCep = cep

      // Visual success feedback
      this.cepTarget.classList.remove("is-invalid", "ax-control--invalid")
      this.cepTarget.classList.add("ax-control--valid")
      setTimeout(() => this.cepTarget.classList.remove("ax-control--valid"), 2000)

    } catch (error) {
      console.error(error)
      this.cepTarget.classList.add("ax-control--invalid")
      // Optional: Clean invalid class on input change
    } finally {
      if (btn) {
        btn.innerHTML = btn.dataset.originalLabel || btn.innerHTML
        btn.disabled = false
        btn.removeAttribute("aria-busy")
      }
      this.loading = false
      this.cepTarget.classList.remove("ax-control--loading")
    }
  }

  populateForm(data) {
    if (!data.street) return

    // 1. UF
    if (this.hasUfTarget) {
      this.setTomSelectValue(this.ufTarget, data.state)
      this.triggerChange(this.ufTarget)
    }

    // 2. Cidade (TomSelect)
    if (this.hasCidadeTarget) {
      this.setTomSelectValue(this.cidadeTarget, data.city)
    }

    // 3. Bairro (TomSelect)
    if (this.hasBairroTarget) {
      this.setTomSelectValue(this.bairroTarget, data.neighborhood)
    }

    // 4. Logradouro & Tipo
    // Try to split Street Type from Name
    let streetName = data.street

    if (this.hasTipoTarget) {
      const matched = this.matchStreetType(data.street)
      if (matched) {
        this.setTomSelectValue(this.tipoTarget, matched.value)
        this.triggerChange(this.tipoTarget)
        streetName = matched.streetName
      }
    }

    if (this.hasLogradouroTarget) {
      this.logradouroTarget.value = streetName
    }

    // 5. Focus Number
    if (this.hasNumeroTarget) {
      setTimeout(() => this.numeroTarget.focus(), 100)
    }
  }

  normalizedCep() {
    return this.cepTarget.value.replace(/\D/g, "")
  }

  setTomSelectValue(element, value) {
    if (!value) return

    // Check for TomSelect instance
    let ts = element.tomselect

    if (ts) {
      // TomSelect doesn't auto-add option if create is true programmatically usually, 
      // we must add it if it doesn't exist.
      // Check if value exists in options (check keys or text)
      // TomSelect options are stored in ts.options = { value: {text, value} }

      // We need to find if there is an option with this text (case insensitive?)
      // BrasilAPI returns standardized case.

      // Let's try to find an existing option by text to get its value
      let existingValue = null
      Object.values(ts.options).forEach(opt => {
        if (opt.value.toLowerCase() === value.toLowerCase() || opt.text.toLowerCase() === value.toLowerCase()) {
          existingValue = opt.value
        }
      })

      if (existingValue) {
        ts.setValue(existingValue)
      } else {
        // Create new option
        ts.addOption({ value: value, text: value })
        ts.setValue(value)
      }
    } else {
      // Fallback for native select
      element.value = value
    }
  }

  triggerChange(element) {
    const event = new Event('change', { bubbles: true })
    element.dispatchEvent(event)
  }

  matchStreetType(fullStreet) {
    const raw = (fullStreet || "").trim()
    if (!raw) return null

    const normalizedRaw = this.normalize(raw)
    const options = Array.from(this.tipoTarget.options)
      .filter((opt) => opt.value && opt.text)
      .map((opt) => ({
        value: opt.value,
        text: opt.text,
        normalized: this.normalize(opt.text)
      }))

    // Primeiro tenta bater com o nome completo da opção.
    const direct = options.find((opt) => normalizedRaw.startsWith(`${opt.normalized} `))
    if (direct) {
      return {
        value: direct.value,
        streetName: raw.substring(direct.text.length).trim()
      }
    }

    // Depois tenta aliases comuns vindos de CEP (Av., Rod., Trav., etc).
    const aliasMap = {
      "av": "avenida",
      "av.": "avenida",
      "aven": "avenida",
      "r": "rua",
      "r.": "rua",
      "rod": "rodovia",
      "rod.": "rodovia",
      "trav": "travessa",
      "trav.": "travessa",
      "al": "alameda",
      "al.": "alameda",
      "estr": "estrada",
      "estr.": "estrada",
      "vl": "viela",
      "vl.": "viela"
    }

    const firstTokenRaw = raw.split(/\s+/)[0] || ""
    const firstToken = this.normalize(firstTokenRaw)
    const canonical = aliasMap[firstToken] || firstToken
    const byAlias = options.find((opt) => opt.normalized === canonical)

    if (!byAlias) return null

    const rest = raw.replace(new RegExp(`^${this.escapeRegex(firstTokenRaw)}\\s*`, "i"), "").trim()
    return {
      value: byAlias.value,
      streetName: rest
    }
  }

  normalize(value) {
    return value
      .toString()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^\w\s./-]/g, "")
      .trim()
      .toLowerCase()
  }

  escapeRegex(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  }
}
