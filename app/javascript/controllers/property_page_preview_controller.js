import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="property-page-preview"
export default class extends Controller {
  static targets = ["results", "count"]
  static values = { url: String }

  connect() {
    this.refresh()
  }

  disconnect() {
    this.requestController?.abort()
  }

  refresh() {
    const formData = new FormData(this.element)
    const params = new URLSearchParams()

    for (let [key, value] of formData.entries()) {
      // Logic to extract parameters from Rails-style names like 'landing_page[filter_params][min_area]'
      // or 'landing_page[filter_params][characteristics][]'
      const nameMatch = key.match(/\[filter_params\]\[(.*?)\]/)
      if (nameMatch) {
        let fieldName = nameMatch[1]

        // Handle array fields
        if (fieldName.endsWith('[]')) {
          params.append(fieldName, value)
        } else if (['neighborhood', 'characteristics', 'category', 'city'].includes(fieldName)) {
          // Force array format if it's one of these fields
          params.append(fieldName + "[]", value)
        } else {
          params.append(fieldName, value)
        }
      }
    }

    const url = `${this.urlValue}?${params.toString()}`

    this.requestController?.abort()
    this.requestController = new AbortController()
    const requestController = this.requestController
    this.resultsTarget.setAttribute("aria-busy", "true")

    fetch(url, {
      signal: requestController.signal,
      headers: {
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
      .then(response => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        return response.json()
      })
      .then(data => {
        this.renderDashboard(data)
      })
      .catch(error => {
        if (error.name === "AbortError") return

        this.resultsTarget.innerHTML = `
        <div class="ax-inline-notice ax-inline-notice--danger" role="alert">
          Não foi possível carregar a prévia. Tente novamente.
        </div>
      `
      })
      .finally(() => {
        if (this.requestController === requestController) {
          this.resultsTarget.setAttribute("aria-busy", "false")
        }
      })
  }

  renderDashboard(data) {
    const { count, metrics } = data

    if (count === 0) {
      this.resultsTarget.innerHTML = `
        <div class="landing-page-preview__empty" role="status">
          <i class="bi bi-search" aria-hidden="true"></i>
          <div>Nenhum imóvel encontrado com esses filtros.</div>
        </div>
      `
      // Update the hero count too if visible
      if (this.hasCountTarget) {
        this.countTarget.hidden = false
        this.countTarget.textContent = "0 imóveis"
      }
      return
    }

    // Sort categories by volume
    const sortedDistribution = Object.entries(metrics.distribution)
      .sort(([, a], [, b]) => b - a)

    const distributionHtml = sortedDistribution.map(([cat, qty]) => {
      const safeCategory = this.escapeHtml(cat)
      return `
        <div class="landing-page-preview__distribution-item">
          <div class="landing-page-preview__distribution-header">
            <span class="landing-page-preview__distribution-label">${safeCategory}</span>
            <span class="landing-page-preview__distribution-count">${qty}</span>
          </div>
          <progress class="landing-page-preview__progress" value="${qty}" max="${count}" aria-label="${safeCategory}: ${qty} de ${count} imóveis"></progress>
        </div>
      `
    }).join('')

    const averagePrice = this.escapeHtml(metrics.avg_price)
    const minimumPrice = this.escapeHtml(metrics.min_price)
    const maximumPrice = this.escapeHtml(metrics.max_price)

    this.resultsTarget.innerHTML = `
      <div class="landing-page-preview__hero">
        <span class="landing-page-preview__hero-value">${count}</span>
        <span class="landing-page-preview__hero-label">Imóveis encontrados</span>
      </div>

      <div class="landing-page-preview__stats">
        <div class="landing-page-preview__stat">
          <div class="landing-page-preview__stat-label"><i class="bi bi-tag-fill" aria-hidden="true"></i> Preço médio</div>
          <div class="landing-page-preview__stat-value">${averagePrice}</div>
          <div class="landing-page-preview__stat-hint">Média dos resultados</div>
        </div>

        <div class="landing-page-preview__stat">
          <div class="landing-page-preview__stat-label"><i class="bi bi-bar-chart-fill" aria-hidden="true"></i> Variação de preço</div>
          <div class="landing-page-preview__stat-value landing-page-preview__stat-value--compact">
            Mín.: <span>${minimumPrice}</span>
          </div>
          <div class="landing-page-preview__stat-value landing-page-preview__stat-value--compact">
            Máx.: <span>${maximumPrice}</span>
          </div>
        </div>

        <div class="landing-page-preview__stat">
          <div class="landing-page-preview__stat-label"><i class="bi bi-pie-chart-fill" aria-hidden="true"></i> Por categoria</div>
          <div class="landing-page-preview__distribution">
            ${distributionHtml}
          </div>
        </div>
      </div>
    `

    // Hide the legacy count badge if it exists
    if (this.hasCountTarget) {
      this.countTarget.hidden = true
    }
  }

  escapeHtml(value) {
    const element = document.createElement("div")
    element.textContent = String(value ?? "")
    return element.innerHTML
  }
}
