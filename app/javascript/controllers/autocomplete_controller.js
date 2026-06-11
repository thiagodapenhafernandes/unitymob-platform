import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results"]
  static values = {
    url: String,
    options: Array,  // Para opções estáticas (tipos de imóveis)
    minChars: { type: Number, default: 2 } // Mínimo de caracteres para buscar (0 para buscar ao focar)
  }

  connect() {
    this.timeout = null
    this.closeResults = this.closeResults.bind(this)
    this.isOpen = false

    // Close results when clicking outside
    document.addEventListener('click', this.closeResults)
  }

  disconnect() {
    document.removeEventListener('click', this.closeResults)
  }

  // Mostra dropdown quando focar no input
  focus(event) {
    if (this.isOpen) return

    // Se tem opções estáticas (tipos), mostra todas
    if (this.hasOptionsValue && this.optionsValue.length > 0) {
      this.displayStaticOptions()
    } else {
      // Se minChars for 0 ou tem valor suficiente, busca
      const query = this.inputTarget.value.trim()
      if (this.minCharsValue === 0 || query.length >= this.minCharsValue) {
        this.fetchResults(query)
      }
    }
  }

  // Toggle dropdown on click
  toggle(event) {
    // Se clicou e já está aberto, fecha. Se está fechado, abre.
    // O evento de focus geralmente dispara antes do click no primeiro foco.
    if (this.isOpen) {
      // Pequeno delay para evitar fechar imediatamente se o focus acabou de abrir
      if (this.lastOpenTime && (Date.now() - this.lastOpenTime < 300)) return
      this.hideResults()
    } else {
      this.focus(event)
    }
  }

  search(event) {
    clearTimeout(this.timeout)

    const query = this.inputTarget.value.trim()

    // Se tem opções estáticas, filtra localmente
    if (this.hasOptionsValue && this.optionsValue.length > 0) {
      this.filterStaticOptions(query)
      return
    }

    // Senão, busca via AJAX
    if (query.length < this.minCharsValue) {
      this.hideResults()
      return
    }

    // Debounce the search
    this.timeout = setTimeout(() => {
      this.fetchResults(query)
    }, 300)
  }

  // Mostra todas as opções estáticas (usado no focus)
  displayStaticOptions() {
    if (!this.hasOptionsValue || this.optionsValue.length === 0) return

    const html = this.optionsValue.map(option => `
      <div class="autocomplete-item px-4 py-2 hover:bg-gray-100 cursor-pointer border-b border-gray-100 last:border-0" 
           data-action="click->autocomplete#select" 
           data-value="${option}">
        <div class="flex items-center gap-2">
          <i class="bi bi-building text-gray-400 text-sm"></i>
          <span class="text-sm text-gray-800">${option}</span>
        </div>
      </div>
    `).join('')

    this.resultsTarget.innerHTML = html
    this.showResults()
  }

  // Filtra opções estáticas localmente
  filterStaticOptions(query) {
    if (!this.hasOptionsValue || this.optionsValue.length === 0) {
      this.hideResults()
      return
    }

    if (query === '') {
      this.displayStaticOptions()
      return
    }

    const filtered = this.optionsValue.filter(option =>
      option.toLowerCase().includes(query.toLowerCase())
    )

    if (filtered.length === 0) {
      this.hideResults()
      return
    }

    const html = filtered.map(option => `
      <div class="autocomplete-item px-4 py-2 hover:bg-gray-100 cursor-pointer border-b border-gray-100 last:border-0" 
           data-action="click->autocomplete#select" 
           data-value="${option}">
        <div class="flex items-center gap-2">
          <i class="bi bi-building text-gray-400 text-sm"></i>
          <span class="text-sm text-gray-800">${option}</span>
        </div>
      </div>
    `).join('')

    this.resultsTarget.innerHTML = html
    this.showResults()
  }

  async fetchResults(query) {
    try {
      const url = this.urlValue || '/imoveis/autocomplete'
      const response = await fetch(`${url}?q=${encodeURIComponent(query)}`)
      const data = await response.json()

      this.displayResults(data)
    } catch (error) {
      console.error('Error fetching autocomplete results:', error)
    }
  }

  displayResults(data) {
    // Só mostra se houver resultados
    if (!data || data.length === 0) {
      this.hideResults()
      return
    }

    const html = data.map(item => `
      <div class="autocomplete-item px-4 py-2 hover:bg-gray-100 cursor-pointer border-b border-gray-100 last:border-0" 
           data-action="click->autocomplete#select" 
           data-value="${item.value}"
           data-url="${item.url || ''}"
           data-type="${item.type}">
        <div class="flex items-center gap-2">
          <span class="text-xs text-gray-500 uppercase">${this.getIcon(item.type)}</span>
          <span class="text-sm text-gray-800">${item.label}</span>
        </div>
      </div>
    `).join('')

    this.resultsTarget.innerHTML = html
    this.showResults()
  }

  getIcon(type) {
    const icons = {
      cidade: '🏙️',
      bairro: '📍',
      empreendimento: '🏢'
    }
    return icons[type] || '📍'
  }

  select(event) {
    const item = event.currentTarget
    const value = item.dataset.value
    const url = item.dataset.url
    const type = item.dataset.type

    // Se for empreendimento e tiver URL, redireciona
    if (type === 'empreendimento' && url) {
      window.location.href = url
      return
    }

    this.inputTarget.value = value
    this.hideResults()

    // Dispara evento de input para atualizar outros controllers se necessário
    this.inputTarget.dispatchEvent(new Event('input'))
  }

  showResults() {
    this.resultsTarget.classList.remove('hidden')
    this.isOpen = true
    this.lastOpenTime = Date.now()
  }

  hideResults() {
    this.resultsTarget.classList.add('hidden')
    this.isOpen = false
  }

  closeResults(event) {
    if (!this.element.contains(event.target)) {
      this.hideResults()
    }
  }
}

