import { Controller } from "@hotwired/stimulus"

// Busca CEP via ViaCEP e, quando o usuário terminar de digitar o número,
// geocoda via Nominatim (OpenStreetMap) e dispara evento "cep-lookup:geocoded"
// com { lat, lng } no document pra que outros controllers (ex: store-map-picker)
// possam centralizar o mapa.
//
// Targets:
//   cep           — input do CEP (obrigatório)
//   address       — logradouro
//   neighborhood  — bairro
//   city          — cidade
//   uf            — UF
//   number        — número (recebe focus automático após CEP resolver)
//   button        — opcional: botão "Buscar" (troca ícone enquanto carrega)
//   status        — opcional: elemento para mostrar mensagens de status
export default class extends Controller {
  static targets = ["cep", "address", "neighborhood", "city", "uf", "number", "button", "status"]

  connect() {
    // Formata CEP enquanto digita (xxxxx-xxx)
    if (this.hasCepTarget) {
      this.cepTarget.addEventListener("input", (e) => this.formatCep(e))
    }
  }

  formatCep(event) {
    let v = event.target.value.replace(/\D/g, "").slice(0, 8)
    if (v.length > 5) v = `${v.slice(0, 5)}-${v.slice(5)}`
    event.target.value = v
  }

  // Action: blur no CEP ou click no botão
  lookup(event) {
    if (event) event.preventDefault()
    if (!this.hasCepTarget) return

    const cep = this.cepTarget.value.replace(/\D/g, "")
    if (cep.length !== 8) {
      this.setStatus("error", "CEP inválido — precisa de 8 dígitos.")
      return
    }

    this.fetchCep(cep)
  }

  async fetchCep(cep) {
    this.setLoading(true)
    this.setStatus("info", "Buscando endereço…")
    try {
      const res = await fetch(`https://viacep.com.br/ws/${cep}/json/`)
      const data = await res.json()
      if (data.erro) {
        this.setStatus("error", "CEP não encontrado.")
        return
      }

      this.fillFields(data)
      this.setStatus("success", `${data.logradouro || ''}, ${data.localidade}/${data.uf}`.replace(/^,\s*/, ""))

      if (this.hasNumberTarget) {
        this.numberTarget.focus()
        this.numberTarget.select && this.numberTarget.select()

        // Geocode automático quando usuário terminar de preencher o número
        this.bindNumberBlur()
      } else {
        // Sem campo número — já tenta geocodar só com CEP+logradouro
        this.triggerGeocode(data)
      }
    } catch (e) {
      console.error("[cep-lookup] erro:", e)
      this.setStatus("error", "Falha de rede ao consultar CEP.")
    } finally {
      this.setLoading(false)
    }
  }

  bindNumberBlur() {
    if (this._numberBlurBound) return
    this._numberBlurBound = true
    if ((this.numberTarget.dataset.action || "").includes("cep-lookup#geocodeFromNumber")) return

    this.numberTarget.addEventListener("blur", () => this.geocodeFromNumber())
  }

  geocodeFromNumber(event) {
    if (event) event.preventDefault()
    if (!this.hasNumberTarget || !this.numberTarget.value.trim()) return
    if (this.hasAddressTarget && !this.addressTarget.value.trim()) return
    if (this.hasCityTarget && !this.cityTarget.value.trim()) return

    this.triggerGeocode()
  }

  fillFields(data) {
    if (this.hasAddressTarget && data.logradouro) this.addressTarget.value = data.logradouro
    if (this.hasNeighborhoodTarget && data.bairro) this.neighborhoodTarget.value = data.bairro
    if (this.hasCityTarget && data.localidade) this.cityTarget.value = data.localidade
    if (this.hasUfTarget && data.uf) this.ufTarget.value = data.uf.toUpperCase()
  }

  async triggerGeocode(cepData = null) {
    const query = this.buildGeocodeQuery(cepData)
    if (!query) return

    this.setStatus("info", "Localizando no mapa…")
    try {
      const url = `https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=br&q=${encodeURIComponent(query)}`
      const res = await fetch(url, { headers: { "Accept": "application/json" } })
      const list = await res.json()
      if (!Array.isArray(list) || list.length === 0) {
        this.setStatus("warn", "Endereço não localizado. Clique no mapa para ajustar.")
        return
      }
      const { lat, lon, display_name } = list[0]
      this.setStatus("success", `Localizado: ${display_name}`)
      document.dispatchEvent(new CustomEvent("cep-lookup:geocoded", {
        detail: { lat: parseFloat(lat), lng: parseFloat(lon) }
      }))
    } catch (e) {
      console.error("[cep-lookup] geocode falhou:", e)
      this.setStatus("warn", "Não foi possível geocodar. Clique no mapa manualmente.")
    }
  }

  buildGeocodeQuery(cepData) {
    const parts = []
    const addr = this.hasAddressTarget ? this.addressTarget.value : (cepData?.logradouro || "")
    const num  = this.hasNumberTarget  ? this.numberTarget.value  : ""
    const hood = this.hasNeighborhoodTarget ? this.neighborhoodTarget.value : (cepData?.bairro || "")
    const city = this.hasCityTarget ? this.cityTarget.value : (cepData?.localidade || "")
    const st   = this.hasUfTarget ? this.ufTarget.value : (cepData?.uf || "")

    if (addr) parts.push(num ? `${addr}, ${num}` : addr)
    if (hood) parts.push(hood)
    if (city) parts.push(city)
    if (st) parts.push(st)
    parts.push("Brasil")
    return parts.filter(Boolean).join(", ")
  }

  setLoading(isLoading) {
    if (!this.hasButtonTarget) return
    if (isLoading) {
      this.buttonTarget.disabled = true
      this.buttonTarget.dataset.originalLabel ||= this.buttonTarget.innerHTML
      this.buttonTarget.innerHTML = this.usesAxControls()
        ? `<span class="ax-spinner" aria-hidden="true"></span>`
        : `<span class="spinner-border spinner-border-sm"></span>`
    } else {
      this.buttonTarget.disabled = false
      if (this.buttonTarget.dataset.originalLabel) {
        this.buttonTarget.innerHTML = this.buttonTarget.dataset.originalLabel
      }
    }
  }

  setStatus(level, message) {
    if (!this.hasStatusTarget) return
    if (this.statusTarget.classList.contains("ax-status-text")) {
      this.statusTarget.className = `ax-status-text ax-status-text--${level || "info"}`
    } else {
      const classes = {
        info:    "text-info",
        success: "text-success",
        warn:    "text-warning",
        error:   "text-danger"
      }
      this.statusTarget.className = `form-text small ${classes[level] || "text-muted"}`
    }
    this.statusTarget.textContent = message
  }

  usesAxControls() {
    return this.buttonTarget.classList.contains("ax-btn") ||
      !!this.buttonTarget.closest(".ax-admin-shell, .habitation-form-ui, .ax-form")
  }
}
