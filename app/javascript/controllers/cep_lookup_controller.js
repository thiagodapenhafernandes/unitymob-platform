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
  static values = { geocodeUrl: String }

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
      this.setStatus("success", `${data.logradouro || ''}, ${data.localidade}/${data.uf}. Informe o número para localizar o ponto exato.`.replace(/^,\s*/, ""))

      if (this.hasNumberTarget) {
        this.numberTarget.focus()
        this.numberTarget.select && this.numberTarget.select()
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

  geocodeFromNumber(event) {
    if (event) event.preventDefault()
    if (!this.hasNumberTarget || !this.numberTarget.value.trim()) {
      this.setStatus("warn", "Informe o número do endereço para localizar o ponto exato no mapa.")
      return
    }
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
    const requests = this.buildGeocodeRequests(cepData)
    if (requests.length === 0) return

    const fullAddress = this.fullAddressLabel(cepData)
    this.setStatus("info", `Consultando no mapa: ${fullAddress}`)
    try {
      const result = this.hasGeocodeUrlValue ? await this.serverGeocode() : await this.firstGeocodeResult(requests)
      if (!result) {
        this.setStatus("warn", `Endereço não localizado para: ${fullAddress}. Clique no mapa para ajustar.`)
        return
      }
      const lat = result.lat || result.latitude
      const lng = result.lng || result.lon || result.longitude
      const displayName = result.display_name
      const feedback = this.locationFeedback(result, displayName, fullAddress)
      this.setStatus(feedback.kind, feedback.message)
      document.dispatchEvent(new CustomEvent("cep-lookup:geocoded", {
        detail: { lat: parseFloat(lat), lng: parseFloat(lng) }
      }))
    } catch (e) {
      console.error("[cep-lookup] geocode falhou:", e)
      this.setStatus("warn", "Não foi possível geocodar. Clique no mapa manualmente.")
    }
  }

  async serverGeocode() {
    const params = new URLSearchParams({
      address: this.hasAddressTarget ? this.addressTarget.value : "",
      number: this.hasNumberTarget ? this.numberTarget.value : "",
      neighborhood: this.hasNeighborhoodTarget ? this.neighborhoodTarget.value : "",
      city: this.hasCityTarget ? this.cityTarget.value : "",
      state: this.hasUfTarget ? this.ufTarget.value : "",
      zip_code: this.hasCepTarget ? this.cepTarget.value : ""
    })

    const response = await fetch(`${this.geocodeUrlValue}?${params.toString()}`, {
      headers: { "Accept": "application/json" }
    })
    if (!response.ok) return null

    const data = await response.json()
    return data.ok ? data : null
  }

  buildGeocodeRequests(cepData) {
    const parts = []
    const addr = this.hasAddressTarget ? this.addressTarget.value : (cepData?.logradouro || "")
    const num  = this.hasNumberTarget  ? this.numberTarget.value  : ""
    const hood = this.hasNeighborhoodTarget ? this.neighborhoodTarget.value : (cepData?.bairro || "")
    const city = this.hasCityTarget ? this.cityTarget.value : (cepData?.localidade || "")
    const st   = this.hasUfTarget ? this.ufTarget.value : (cepData?.uf || "")
    const cep = this.hasCepTarget ? this.cepTarget.value.replace(/\D/g, "") : ""

    if (addr) parts.push(num ? `${addr}, ${num}` : addr)
    if (hood) parts.push(hood)
    if (city) parts.push(city)
    if (st) parts.push(st)
    parts.push("Brasil")
    const fallbackQuery = parts.filter(Boolean).join(", ")

    const requests = []
    if (addr && num) {
      requests.push({
        street: `${num} ${addr}`,
        city,
        state: st,
        postalcode: cep,
        country: "Brasil"
      })
      requests.push({
        street: `${addr}, ${num}`,
        city,
        state: st,
        postalcode: cep,
        country: "Brasil"
      })
    }
    if (fallbackQuery) requests.push({ q: fallbackQuery })
    return requests
  }

  fullAddressLabel(cepData = null) {
    const addr = this.hasAddressTarget ? this.addressTarget.value : (cepData?.logradouro || "")
    const num  = this.hasNumberTarget ? this.numberTarget.value : ""
    const hood = this.hasNeighborhoodTarget ? this.neighborhoodTarget.value : (cepData?.bairro || "")
    const city = this.hasCityTarget ? this.cityTarget.value : (cepData?.localidade || "")
    const st   = this.hasUfTarget ? this.ufTarget.value : (cepData?.uf || "")
    const cep  = this.hasCepTarget ? this.cepTarget.value : ""

    const streetLine = [addr, num].filter(Boolean).join(", ")
    const cityLine = [city, st].filter(Boolean).join("/")
    return [streetLine, hood, cityLine, cep, "Brasil"].filter(Boolean).join(" - ")
  }

  async firstGeocodeResult(requests) {
    for (const request of requests) {
      const params = new URLSearchParams({ format: "json", limit: "1", countrycodes: "br", addressdetails: "1" })
      Object.entries(request).forEach(([key, value]) => {
        if (value) params.set(key, value)
      })

      const res = await fetch(`https://nominatim.openstreetmap.org/search?${params.toString()}`, {
        headers: { "Accept": "application/json" }
      })
      const list = await res.json()
      if (Array.isArray(list) && list.length > 0) return list[0]
    }
    return null
  }

  locationFeedback(result, displayName, fullAddress) {
    const requestedNumber = this.hasNumberTarget ? this.numberTarget.value.trim() : ""
    const foundNumber = (result?.house_number || result?.address?.house_number)?.toString()
    const provider = result?.provider === "google" ? "Google Maps" : "OpenStreetMap"
    const precision = result?.precision?.toString()

    if (requestedNumber && foundNumber && foundNumber === requestedNumber && ["rooftop", "house_number"].includes(precision)) {
      return { kind: "success", message: `Localizado com precisão pelo ${provider}: ${displayName}` }
    }

    if (requestedNumber && foundNumber && foundNumber === requestedNumber) {
      return { kind: "success", message: `Localizado no número ${requestedNumber} pelo ${provider}: ${displayName}` }
    }

    if (requestedNumber && !foundNumber) {
      return { kind: "warn", message: `Consulta feita com número: ${fullAddress}. A base do ${provider} retornou só a rua, sem confirmar o número ${requestedNumber}. Clique no mapa ou arraste o marcador para o ponto exato.` }
    }

    if (requestedNumber && foundNumber !== requestedNumber) {
      return { kind: "warn", message: `Consulta feita com número: ${fullAddress}. A base do ${provider} retornou o número ${foundNumber} em vez de ${requestedNumber}. Clique no mapa ou arraste o marcador para o ponto exato.` }
    }

    return { kind: "warn", message: `Localizado: ${displayName}. Informe o número para ter ajuste fino.` }
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
